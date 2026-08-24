#include <iostream>
#include <string>
#include <vector>
#include <deque>
#include <chrono>
#include <thread>
#include <cstring>
#include <cstdlib>
#include <csignal>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <sstream>

#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <linux/input.h>
#include <glob.h>

namespace fs = std::filesystem;

static constexpr double WINDOW = 0.6;           // seconds a reversal stays "recent"
static constexpr double MIN_SEG = 30.0;         // px a swing must cover to count as a reversal
static constexpr size_t MIN_REVERSALS = 4;      // reversals within WINDOW to trigger zoom
static constexpr double SUPERVISE = 1.0;        // seconds between parent-liveness checks
static constexpr double TAKEOVER = 3.0;         // seconds to wait for an older watcher
static constexpr double DEAD_AFTER = 5.0;       // seconds before compositor counts as gone
static constexpr useconds_t POLL_US = 16666;    // ~60 Hz (16.66ms)

static std::string g_mode = "grow";             // "off", "grow", "zoom"
static double g_zoom_factor = 2.0;
static double g_grow_factor = 2.5;

static std::string g_sock_path;
static std::string g_instance_sig;
static std::string g_base_theme = "Bibata-Modern-Classic";
static int g_base_size = 24;
static int g_orig_nohw = 2;
static bool g_active = false;
static int g_lock_fd = -1;

static double get_time_sec() {
    using namespace std::chrono;
    return duration_cast<duration<double>>(steady_clock::now().time_since_epoch()).count();
}

static std::string get_runtime_dir() {
    const char* xdg = getenv("XDG_RUNTIME_DIR");
    if (xdg && strlen(xdg) > 0) return std::string(xdg);
    return "/run/user/" + std::to_string(getuid());
}

static std::pair<std::string, std::string> find_hypr_instance() {
    const char* sig_env = getenv("HYPRLAND_INSTANCE_SIGNATURE");
    std::string sig = sig_env ? sig_env : "";
    std::string base = get_runtime_dir() + "/hypr";

    if (sig.empty()) {
        try {
            if (fs::exists(base) && fs::is_directory(base)) {
                for (const auto& entry : fs::directory_iterator(base)) {
                    if (entry.is_directory()) {
                        sig = entry.path().filename().string();
                        break;
                    }
                }
            }
        } catch (...) {}
    }

    if (sig.empty()) return {"", ""};
    return {base + "/" + sig + "/.socket.sock", sig};
}

static std::string send_hypr_command(const std::string& cmd) {
    if (g_sock_path.empty()) return "";

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return "";

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, g_sock_path.c_str(), sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd);
        return "";
    }

    send(fd, cmd.c_str(), cmd.size(), 0);

    std::string response;
    char buffer[512];
    ssize_t bytes_read = 0;
    while ((bytes_read = recv(fd, buffer, sizeof(buffer) - 1, 0)) > 0) {
        buffer[bytes_read] = '\0';
        response.append(buffer, bytes_read);
    }

    close(fd);
    return response;
}

static bool get_cursor_pos(int& x, int& y) {
    std::string resp = send_hypr_command("cursorpos");
    if (resp.empty()) return false;

    size_t comma = resp.find(',');
    if (comma == std::string::npos) return false;

    try {
        x = std::stoi(resp.substr(0, comma));
        y = std::stoi(resp.substr(comma + 1));
        return true;
    } catch (...) {
        return false;
    }
}

static void query_gsettings_cursor(std::string& theme, int& size) {
    theme = "Bibata-Modern-Classic";
    size = 24;

    FILE* fp = popen("gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null", "r");
    if (fp) {
        char buf[128];
        if (fgets(buf, sizeof(buf), fp)) {
            std::string s = buf;
            while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == '\'')) s.pop_back();
            if (!s.empty() && s.front() == '\'') s.erase(0, 1);
            if (!s.empty()) theme = s;
        }
        pclose(fp);
    }

    fp = popen("gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null", "r");
    if (fp) {
        char buf[64];
        if (fgets(buf, sizeof(buf), fp)) {
            try { size = std::stoi(buf); } catch (...) {}
        }
        pclose(fp);
    }
}

static void set_nohw(int val) {
    send_hypr_command("eval hl.config({ cursor = { no_hardware_cursors = " + std::to_string(val) + " } })");
}

static void set_zoom(double factor) {
    send_hypr_command("eval hl.config({ cursor = { zoom_factor = " + std::to_string(factor) + " } })");
}

static void activate() {
    if (g_mode == "grow") {
        query_gsettings_cursor(g_base_theme, g_base_size);
        set_nohw(1);
        int enlarged = static_cast<int>(g_base_size * g_grow_factor);
        send_hypr_command("setcursor " + g_base_theme + " " + std::to_string(enlarged));
    } else if (g_mode == "zoom") {
        set_zoom(g_zoom_factor);
    }
}

static void deactivate() {
    if (g_mode == "grow") {
        send_hypr_command("setcursor " + g_base_theme + " " + std::to_string(g_base_size));
        set_nohw(g_orig_nohw);
    } else if (g_mode == "zoom") {
        set_zoom(1.0);
    }
}

static void cleanup(int = 0) {
    if (g_active) {
        deactivate();
        g_active = false;
    }
    if (g_lock_fd >= 0) {
        close(g_lock_fd);
        g_lock_fd = -1;
    }
    _exit(0);
}

static bool is_watcher_proc(pid_t pid) {
    std::string cmdline_path = "/proc/" + std::to_string(pid) + "/cmdline";
    std::ifstream ifs(cmdline_path, std::ios::binary);
    if (!ifs) return false;
    std::string content((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
    return content.find("shake-zoom") != std::string::npos;
}

static int claim_instance_lock(const std::string& sig) {
    std::string lock_path = get_runtime_dir() + "/shake-zoom." + sig + ".lock";
    int fd = open(lock_path.c_str(), O_RDWR | O_CREAT, 0600);
    if (fd < 0) return -1;

    double deadline = get_time_sec() + TAKEOVER;
    std::vector<pid_t> asked;

    while (true) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
            ftruncate(fd, 0);
            lseek(fd, 0, SEEK_SET);
            std::string pid_str = std::to_string(getpid());
            write(fd, pid_str.c_str(), pid_str.size());
            return fd;
        }

        lseek(fd, 0, SEEK_SET);
        char buf[32] = {0};
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        pid_t holder = 0;
        if (n > 0) {
            try { holder = std::stoi(buf); } catch (...) { holder = 0; }
        }

        if (holder > 0 && holder != getpid() && is_watcher_proc(holder)) {
            bool already_asked = false;
            for (pid_t p : asked) {
                if (p == holder) { already_asked = true; break; }
            }
            if (!already_asked) {
                asked.push_back(holder);
                kill(holder, SIGTERM);
            }
        }

        if (get_time_sec() >= deadline) {
            close(fd);
            return -1;
        }
        usleep(50000);
    }
}

// Direction-agnostic shake detector
class ShakeDetector {
public:
    struct Point { double x, y; };
    struct Vec { double dx, dy; };

    ShakeDetector() : has_prev_vec(false), has_anchor(false), prev_vec{0, 0}, anchor{0, 0} {}

    bool feed(double now, double x, double y, double dx, double dy) {
        if (dx * dx + dy * dy >= 4.0) {
            Vec vec{dx, dy};
            if (has_prev_vec && (vec.dx * prev_vec.dx + vec.dy * prev_vec.dy) < 0.0) {
                if (!has_anchor || ((x - anchor.x) * (x - anchor.x) + (y - anchor.y) * (y - anchor.y)) >= MIN_SEG * MIN_SEG) {
                    reversals.push_back(now);
                    anchor = {x, y};
                    has_anchor = true;
                }
            } else if (!has_anchor) {
                anchor = {x, y};
                has_anchor = true;
            }
            prev_vec = vec;
            has_prev_vec = true;
        }

        while (!reversals.empty() && (now - reversals.front()) > WINDOW) {
            reversals.pop_front();
        }

        return reversals.size() >= MIN_REVERSALS;
    }

    void reset() {
        reversals.clear();
        has_prev_vec = false;
        has_anchor = false;
    }

private:
    bool has_prev_vec;
    bool has_anchor;
    Vec prev_vec;
    Point anchor;
    std::deque<double> reversals;
};

int main(int argc, char* argv[]) {
    if (argc >= 2) g_mode = argv[1];
    if (argc >= 3) {
        try { g_zoom_factor = std::stod(argv[2]); } catch (...) {}
    }
    if (argc >= 4) {
        try { g_grow_factor = std::stod(argv[3]); } catch (...) {}
    }

    if (g_mode == "off") {
        return 0;
    }

    auto [sock_path, sig] = find_hypr_instance();
    if (sock_path.empty()) {
        std::cerr << "Hyprland socket not found." << std::endl;
        return 1;
    }
    g_sock_path = sock_path;
    g_instance_sig = sig;

    signal(SIGTERM, cleanup);
    signal(SIGINT, cleanup);
    signal(SIGHUP, cleanup);

    g_lock_fd = claim_instance_lock(sig);
    if (g_lock_fd < 0) {
        return 0; // Another instance is taking over
    }

    query_gsettings_cursor(g_base_theme, g_base_size);

    std::string nohw_str = send_hypr_command("j/getoption cursor:no_hardware_cursors");
    size_t int_pos = nohw_str.find("\"int\":");
    if (int_pos != std::string::npos) {
        try {
            g_orig_nohw = std::stoi(nohw_str.substr(int_pos + 6));
        } catch (...) {
            g_orig_nohw = 2;
        }
    }

    ShakeDetector det;
    int prev_x = 0, prev_y = 0;
    bool has_prev = get_cursor_pos(prev_x, prev_y);

    pid_t parent = getppid();
    double hold_duration = (g_mode == "grow") ? 1.0 : 3.0;
    double active_until = 0.0;
    double answered = get_time_sec();
    double supervised = 0.0;

    while (true) {
        usleep(POLL_US);
        double now = get_time_sec();

        // Check if parent process (Quickshell / caller) is still alive
        if (now - supervised >= SUPERVISE) {
            supervised = now;
            if (getppid() != parent) {
                cleanup(0);
            }
        }

        int curr_x = 0, curr_y = 0;
        if (!get_cursor_pos(curr_x, curr_y)) {
            if (now - answered > DEAD_AFTER) {
                cleanup(0); // Compositor is gone
            }
            continue;
        }
        answered = now;

        if (!has_prev) {
            prev_x = curr_x;
            prev_y = curr_y;
            has_prev = true;
            continue;
        }

        int dx = curr_x - prev_x;
        int dy = curr_y - prev_y;
        prev_x = curr_x;
        prev_y = curr_y;

        if (det.feed(now, curr_x, curr_y, dx, dy)) {
            if (!g_active) {
                activate();
                g_active = true;
            }
            active_until = now + hold_duration;
        }

        if (g_active && now > active_until) {
            deactivate();
            g_active = false;
            det.reset();
        }
    }

    cleanup(0);
    return 0;
}
