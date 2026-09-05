#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <set>
#include <filesystem>
#include <cstring>
#include <unistd.h>
#include <sys/statvfs.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>

namespace fs = std::filesystem;

static const char* LOG_FILE = "/tmp/qs_popup.log";

static void log_popup(const std::string& category, const std::string& title,
                      const std::string& message, const std::string& cat = "generic",
                      const std::string& act = "") {
    std::ofstream f(LOG_FILE, std::ios::app);
    if (f.is_open()) {
        f << category << "|" << title << "|" << message << "|" << cat << "|" << act << "\n";
        f.flush();
    }
}

// -----------------------------------------------------------------------------
// State Management
// -----------------------------------------------------------------------------
static std::string g_ac_state = "Unknown";
static std::string g_last_song = "";
static std::set<std::string> g_connected_bt_devices;
static int g_last_bt_count = 0;

// -----------------------------------------------------------------------------
// Power / AC Status (Sysfs + UPower)
// -----------------------------------------------------------------------------
static void check_power_status() {
    std::string ac_path = "";
    std::string base = "/sys/class/power_supply";
    std::error_code ec;
    if (fs::exists(base, ec)) {
        for (const auto& entry : fs::directory_iterator(base, ec)) {
            std::string name = entry.path().filename().string();
            if (name.rfind("AC", 0) == 0 || name.rfind("ADP", 0) == 0) {
                ac_path = entry.path().string();
                break;
            }
        }
    }

    if (!ac_path.empty()) {
        std::string online_file = ac_path + "/online";
        std::ifstream f(online_file);
        if (f.is_open()) {
            std::string status;
            f >> status;
            if (status != g_ac_state) {
                if (status == "1") {
                    log_popup("good", "POWER", "Plugged In", "battery", "charging");
                } else {
                    log_popup("bad", "POWER", "Unplugged", "battery", "unplugged");
                }
                g_ac_state = status;
            }
        }
    }
}

static int upower_handler(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    check_power_status();
    return 0;
}

// -----------------------------------------------------------------------------
// Bluetooth (BlueZ)
// -----------------------------------------------------------------------------
static void init_bluetooth_state(sd_bus* bus) {
    sd_bus_error error = SD_BUS_ERROR_NULL;
    sd_bus_message *reply = nullptr;

    int r = sd_bus_call_method(bus, "org.bluez", "/",
                               "org.freedesktop.DBus.ObjectManager",
                               "GetManagedObjects", &error, &reply, "");
    if (r >= 0 && reply) {
        r = sd_bus_message_enter_container(reply, 'a', "{oa{sa{sv}}}");
        if (r >= 0) {
            while (sd_bus_message_enter_container(reply, 'e', "oa{sa{sv}}") > 0) {
                const char* obj_path = nullptr;
                sd_bus_message_read(reply, "o", &obj_path);
                
                if (sd_bus_message_enter_container(reply, 'a', "{sa{sv}}") >= 0) {
                    while (sd_bus_message_enter_container(reply, 'e', "sa{sv}") > 0) {
                        const char* iface = nullptr;
                        sd_bus_message_read(reply, "s", &iface);
                        
                        if (iface && std::string(iface) == "org.bluez.Device1") {
                            if (sd_bus_message_enter_container(reply, 'a', "{sv}") >= 0) {
                                while (sd_bus_message_enter_container(reply, 'e', "sv") > 0) {
                                    const char* prop = nullptr;
                                    sd_bus_message_read(reply, "s", &prop);
                                    if (prop && std::string(prop) == "Connected") {
                                        int b = 0;
                                        if (sd_bus_message_enter_container(reply, 'v', "b") >= 0) {
                                            sd_bus_message_read(reply, "b", &b);
                                            sd_bus_message_exit_container(reply);
                                            if (b && obj_path) {
                                                g_connected_bt_devices.insert(obj_path);
                                            }
                                        } else {
                                            sd_bus_message_skip(reply, "v");
                                        }
                                    } else {
                                        sd_bus_message_skip(reply, "v");
                                    }
                                    sd_bus_message_exit_container(reply);
                                }
                                sd_bus_message_exit_container(reply);
                            }
                        } else {
                            sd_bus_message_skip(reply, "a{sv}");
                        }
                        sd_bus_message_exit_container(reply);
                    }
                    sd_bus_message_exit_container(reply);
                }
                sd_bus_message_exit_container(reply);
            }
            sd_bus_message_exit_container(reply);
        }
        sd_bus_message_unref(reply);
    }
    sd_bus_error_free(&error);
    g_last_bt_count = static_cast<int>(g_connected_bt_devices.size());
}

static int bt_handler(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    const char *iface = nullptr;
    if (sd_bus_message_read(m, "s", &iface) < 0 || !iface) return 0;
    if (std::string(iface) != "org.bluez.Device1") return 0;

    const char *dev_path = sd_bus_message_get_path(m);
    if (!dev_path) return 0;

    int r = sd_bus_message_enter_container(m, 'a', "{sv}");
    if (r < 0) return 0;

    bool found_connected = false;
    int is_connected = 0;

    while ((r = sd_bus_message_enter_container(m, 'e', "sv")) > 0) {
        const char *prop = nullptr;
        sd_bus_message_read(m, "s", &prop);
        if (prop && std::string(prop) == "Connected") {
            found_connected = true;
            if (sd_bus_message_enter_container(m, 'v', "b") >= 0) {
                sd_bus_message_read(m, "b", &is_connected);
                sd_bus_message_exit_container(m);
            } else {
                sd_bus_message_skip(m, "v");
            }
        } else {
            sd_bus_message_skip(m, "v");
        }
        sd_bus_message_exit_container(m);
    }
    sd_bus_message_exit_container(m);

    if (found_connected) {
        if (is_connected) {
            g_connected_bt_devices.insert(dev_path);
            
            // Query device name or alias
            sd_bus *bus = sd_bus_message_get_bus(m);
            char *alias = nullptr;
            sd_bus_error err = SD_BUS_ERROR_NULL;
            sd_bus_get_property_string(bus, "org.bluez", dev_path, "org.bluez.Device1", "Alias", &err, &alias);
            std::string name_str = alias ? alias : "Device";
            free(alias);
            sd_bus_error_free(&err);

            if (static_cast<int>(g_connected_bt_devices.size()) > g_last_bt_count) {
                log_popup("good", "BLUETOOTH", "Connected: " + name_str, "bluetooth", "connected");
            }
        } else {
            g_connected_bt_devices.erase(dev_path);
            if (static_cast<int>(g_connected_bt_devices.size()) < g_last_bt_count) {
                log_popup("bad", "BLUETOOTH", "Disconnected", "bluetooth", "disconnected");
            }
        }
        g_last_bt_count = static_cast<int>(g_connected_bt_devices.size());
    }

    return 0;
}

// -----------------------------------------------------------------------------
// NetworkManager
// -----------------------------------------------------------------------------
static int nm_handler(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    uint32_t state_val = 0;
    if (sd_bus_message_read(m, "u", &state_val) >= 0) {
        // NM_STATE_CONNECTED_GLOBAL = 70
        if (state_val == 70) {
            log_popup("good", "WIFI", "Connected", "wifi", "connected");
        } else if (state_val == 20 || state_val == 10) { // Disconnected / Asleep
            log_popup("bad", "WIFI", "Disconnected", "wifi", "disconnected");
        }
    }
    return 0;
}

// -----------------------------------------------------------------------------
// Disk Space Polling
// -----------------------------------------------------------------------------
static void check_disk_space() {
    struct statvfs st;
    if (statvfs("/", &st) == 0 && st.f_blocks > 0) {
        unsigned long long used = st.f_blocks - st.f_bfree;
        int usage_pct = static_cast<int>((used * 100ULL) / st.f_blocks);
        if (usage_pct >= 90) {
            log_popup("bad", "SYSTEM", "Low Disk Space (" + std::to_string(usage_pct) + "%)", "generic", "low");
        }
    }
}

static int disk_timer_handler(sd_event_source* s, uint64_t usec, void* userdata) {
    check_disk_space();

    uint64_t next_usec = 0;
    sd_event_now(sd_event_source_get_event(s), CLOCK_MONOTONIC, &next_usec);
    sd_event_source_set_time(s, next_usec + 60ULL * 1000000ULL);
    sd_event_source_set_enabled(s, SD_EVENT_ONESHOT);
    return 0;
}

// -----------------------------------------------------------------------------
// MPRIS (Now Playing)
// -----------------------------------------------------------------------------
static int mpris_handler(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    const char *iface = nullptr;
    if (sd_bus_message_read(m, "s", &iface) < 0 || !iface) return 0;
    if (std::string(iface) != "org.mpris.MediaPlayer2.Player") return 0;

    int r = sd_bus_message_enter_container(m, 'a', "{sv}");
    if (r < 0) return 0;

    std::string title = "";
    std::string artist = "";

    while ((r = sd_bus_message_enter_container(m, 'e', "sv")) > 0) {
        const char *key = nullptr;
        sd_bus_message_read(m, "s", &key);
        if (key && std::string(key) == "Metadata") {
            if (sd_bus_message_enter_container(m, 'v', "a{sv}") >= 0) {
                while (sd_bus_message_enter_container(m, 'e', "sv") > 0) {
                    const char *meta_key = nullptr;
                    sd_bus_message_read(m, "s", &meta_key);
                    if (meta_key && std::string(meta_key) == "xesam:title") {
                        const char *t = nullptr;
                        if (sd_bus_message_enter_container(m, 'v', "s") >= 0) {
                            sd_bus_message_read(m, "s", &t);
                            if (t) title = t;
                            sd_bus_message_exit_container(m);
                        } else {
                            sd_bus_message_skip(m, "v");
                        }
                    } else if (meta_key && std::string(meta_key) == "xesam:artist") {
                        if (sd_bus_message_enter_container(m, 'v', "as") >= 0) {
                            if (sd_bus_message_enter_container(m, 'a', "s") >= 0) {
                                const char *a = nullptr;
                                if (sd_bus_message_read(m, "s", &a) > 0 && a) {
                                    artist = a;
                                }
                                sd_bus_message_exit_container(m);
                            }
                            sd_bus_message_exit_container(m);
                        } else {
                            sd_bus_message_skip(m, "v");
                        }
                    } else {
                        sd_bus_message_skip(m, "v");
                    }
                    sd_bus_message_exit_container(m);
                }
                sd_bus_message_exit_container(m);
            } else {
                sd_bus_message_skip(m, "v");
            }
        } else {
            sd_bus_message_skip(m, "v");
        }
        sd_bus_message_exit_container(m);
    }
    sd_bus_message_exit_container(m);

    if (!title.empty()) {
        std::string song_str = title + (artist.empty() ? "" : " - " + artist);
        if (song_str.length() > 40) {
            song_str = song_str.substr(0, 40) + "...";
        }
        if (song_str != g_last_song) {
            if (!g_last_song.empty()) {
                log_popup("neutral", "Now Playing", song_str, "media", "playing");
            }
            g_last_song = song_str;
        }
    }

    return 0;
}

// -----------------------------------------------------------------------------
// Main Entry Point
// -----------------------------------------------------------------------------
int main() {
    sd_event *event = nullptr;
    sd_bus *sys_bus = nullptr;
    sd_bus *user_bus = nullptr;

    if (sd_event_default(&event) < 0) {
        std::cerr << "Failed to allocate default sd_event\n";
        return 1;
    }

    // 1. Initial State
    check_power_status();
    check_disk_space();

    // 2. Open System Bus (UPower, BlueZ, NetworkManager)
    if (sd_bus_default_system(&sys_bus) >= 0) {
        sd_bus_attach_event(sys_bus, event, 0);

        init_bluetooth_state(sys_bus);

        // Match UPower
        sd_bus_add_match(sys_bus, nullptr,
                         "type='signal',sender='org.freedesktop.UPower',"
                         "interface='org.freedesktop.DBus.Properties',"
                         "member='PropertiesChanged',path='/org/freedesktop/UPower'",
                         upower_handler, nullptr);

        // Match BlueZ Device1 PropertiesChanged
        sd_bus_add_match(sys_bus, nullptr,
                         "type='signal',sender='org.bluez',"
                         "interface='org.freedesktop.DBus.Properties',"
                         "member='PropertiesChanged',arg0='org.bluez.Device1'",
                         bt_handler, nullptr);

        // Match NetworkManager StateChanged
        sd_bus_add_match(sys_bus, nullptr,
                         "type='signal',sender='org.freedesktop.NetworkManager',"
                         "interface='org.freedesktop.NetworkManager',"
                         "member='StateChanged'",
                         nm_handler, nullptr);
    } else {
        std::cerr << "Warning: Could not connect to system D-Bus\n";
    }

    // 3. Open Session Bus (MPRIS)
    if (sd_bus_default_user(&user_bus) >= 0) {
        sd_bus_attach_event(user_bus, event, 0);

        sd_bus_add_match(user_bus, nullptr,
                         "type='signal',interface='org.freedesktop.DBus.Properties',"
                         "member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'",
                         mpris_handler, nullptr);
    } else {
        std::cerr << "Warning: Could not connect to user/session D-Bus\n";
    }

    // 4. Setup 60s Disk Timer
    sd_event_source *timer_source = nullptr;
    uint64_t now_usec = 0;
    sd_event_now(event, CLOCK_MONOTONIC, &now_usec);
    sd_event_add_time(event, &timer_source, CLOCK_MONOTONIC, now_usec + 60ULL * 1000000ULL, 0, disk_timer_handler, nullptr);
    sd_event_source_set_enabled(timer_source, SD_EVENT_ONESHOT);

    // 5. Run Event Loop
    sd_event_loop(event);

    // Cleanup
    if (timer_source) sd_event_source_unref(timer_source);
    if (sys_bus) {
        sd_bus_close(sys_bus);
        sd_bus_unref(sys_bus);
    }
    if (user_bus) {
        sd_bus_close(user_bus);
        sd_bus_unref(user_bus);
    }
    if (event) sd_event_unref(event);

    return 0;
}
