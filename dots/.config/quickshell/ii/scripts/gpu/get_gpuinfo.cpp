#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <chrono>
#include <filesystem>
#include <iomanip>
#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <algorithm>
#include <unistd.h>

namespace fs = std::filesystem;

static inline int64_t get_time_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

static std::string read_file_str(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) return "";
    std::string s;
    std::getline(f, s);
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' ')) s.pop_back();
    return s;
}

static int64_t read_file_int64(const std::string& path, int64_t def = 0) {
    std::ifstream f(path);
    if (!f.is_open()) return def;
    int64_t val = def;
    if (f >> val) return val;
    return def;
}

static std::string to_lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c){ return std::tolower(c); });
    return s;
}

// -----------------------------------------------------------------------------
// Intel GPU Name resolution with cache to avoid repeating lspci
// -----------------------------------------------------------------------------
static std::string get_intel_gpu_name(const std::string& bdf) {
    std::string cache_file = "/tmp/quickshell_intel_gpu_name";
    std::string cached = read_file_str(cache_file);
    if (!cached.empty()) return cached;

    std::string name = "Intel Graphics";
    if (!bdf.empty()) {
        std::string cmd = "LC_ALL=C lspci -s '" + bdf + "' 2>/dev/null";
        FILE* fp = popen(cmd.c_str(), "r");
        if (fp) {
            char buf[512];
            if (fgets(buf, sizeof(buf), fp)) {
                std::string desc = buf;
                if (desc.find("Iris") != std::string::npos) {
                    name = "Iris Xe";
                } else if (desc.find("UHD") != std::string::npos) {
                    name = "UHD Graphics";
                }
            }
            pclose(fp);
        }
    }

    std::ofstream out(cache_file);
    if (out.is_open()) {
        out << name << "\n";
    }
    return name;
}

// -----------------------------------------------------------------------------
// Temperature detection
// -----------------------------------------------------------------------------
static std::string get_intel_temperature() {
    for (int i = 0; i < 20; ++i) {
        std::string base = "/sys/class/thermal/thermal_zone" + std::to_string(i);
        std::string type_file = base + "/type";
        if (!fs::exists(type_file)) continue;
        std::string t = read_file_str(type_file);
        if (t.find("x86_pkg_temp") != std::string::npos || t.find("coretemp") != std::string::npos) {
            int64_t raw_temp = read_file_int64(base + "/temp", -1);
            if (raw_temp > 0) {
                return std::to_string(raw_temp / 1000);
            }
        }
    }
    return "null";
}

static std::string get_hwmon_temp(const std::string& card_device_dir) {
    std::string hwmon_dir = card_device_dir + "/hwmon";
    if (fs::exists(hwmon_dir)) {
        for (const auto& entry : fs::directory_iterator(hwmon_dir)) {
            std::string temp_input = entry.path().string() + "/temp1_input";
            if (fs::exists(temp_input)) {
                int64_t val = read_file_int64(temp_input, -1);
                if (val > 0) return std::to_string(val / 1000);
            }
        }
    }
    return "null";
}

// -----------------------------------------------------------------------------
// Intel iGPU Handler
// -----------------------------------------------------------------------------
static bool handle_intel_igpu(const std::string& card_dir, const std::string& device_dir) {
    std::string bdf;
    try {
        bdf = fs::canonical(device_dir).filename().string();
    } catch (...) {
        bdf = "";
    }
    std::string gpu_name = get_intel_gpu_name(bdf);

    // Calculate usage % via RC6 residency
    int usage = 0;
    std::string state_file = "/tmp/quickshell_intel_rc6";
    int64_t now_ms = get_time_ms();

    std::string rc6_path = card_dir + "/gt/gt0/rc6_residency_ms";
    if (!fs::exists(rc6_path)) {
        rc6_path = card_dir + "/power/rc6_residency_ms";
    }

    if (fs::exists(rc6_path)) {
        int64_t curr_rc6 = read_file_int64(rc6_path, -1);
        if (curr_rc6 >= 0) {
            int64_t prev_time = 0, prev_rc6 = 0;
            std::ifstream sf(state_file);
            if (sf >> prev_time >> prev_rc6) {
                int64_t dt = now_ms - prev_time;
                int64_t d_rc6 = curr_rc6 - prev_rc6;
                if (dt > 50 && dt < 10000 && d_rc6 >= 0) {
                    int64_t rc6_pct = (d_rc6 * 100) / dt;
                    if (rc6_pct > 100) rc6_pct = 100;
                    usage = static_cast<int>(100 - rc6_pct);
                    if (usage < 0) usage = 0;
                    if (usage > 100) usage = 100;
                }
            }
            std::ofstream out(state_file);
            if (out.is_open()) {
                out << now_ms << " " << curr_rc6 << "\n";
            }
        }
    }

    // Frequency fallback if usage is 0
    if (usage == 0) {
        int64_t act_freq = read_file_int64(card_dir + "/gt/gt0/rps_act_freq_mhz", -1);
        if (act_freq < 0) act_freq = read_file_int64(card_dir + "/gt_act_freq_mhz", 0);

        int64_t min_freq = read_file_int64(card_dir + "/gt/gt0/rps_min_freq_mhz", -1);
        if (min_freq < 0) min_freq = read_file_int64(card_dir + "/gt_min_freq_mhz", 100);

        int64_t max_freq = read_file_int64(card_dir + "/gt/gt0/rps_max_freq_mhz", -1);
        if (max_freq < 0) max_freq = read_file_int64(card_dir + "/gt_max_freq_mhz", 1200);

        if (act_freq > min_freq && max_freq > min_freq) {
            usage = static_cast<int>((act_freq - min_freq) * 100 / (max_freq - min_freq));
            if (usage > 100) usage = 100;
        }
    }

    // VRAM from /proc/meminfo
    int64_t vram_total_kib = 0;
    int64_t vram_avail_kib = 0;
    std::ifstream meminfo("/proc/meminfo");
    if (meminfo.is_open()) {
        std::string line;
        while (std::getline(meminfo, line)) {
            if (line.compare(0, 9, "MemTotal:") == 0) {
                std::istringstream iss(line.substr(9));
                iss >> vram_total_kib;
            } else if (line.compare(0, 13, "MemAvailable:") == 0) {
                std::istringstream iss(line.substr(13));
                iss >> vram_avail_kib;
            }
            if (vram_total_kib > 0 && vram_avail_kib > 0) break;
        }
    }

    int64_t vram_used_kib = (vram_total_kib > vram_avail_kib) ? (vram_total_kib - vram_avail_kib) : 0;
    double vram_used_gb = vram_used_kib / (1024.0 * 1024.0);
    double vram_total_gb = vram_total_kib / (1024.0 * 1024.0);
    int vram_percent = (vram_total_kib > 0) ? static_cast<int>(vram_used_kib * 100 / vram_total_kib) : 0;

    std::string temp = get_intel_temperature();

    std::cout << "{\"vendor\": \"intel\", \"name\": \"" << gpu_name << "\", "
              << "\"usagePercent\": " << usage << ", "
              << std::fixed << std::setprecision(1)
              << "\"vramUsedGB\": " << vram_used_gb << ", "
              << "\"vramTotalGB\": " << vram_total_gb << ", "
              << "\"vramPercent\": " << vram_percent << ", "
              << "\"tempEdgeC\": " << temp << ", "
              << "\"tempJunctionC\": null, \"tempMemC\": null, "
              << "\"fanRpm\": null, \"fanPercent\": null, "
              << "\"powerW\": null, \"powerLimitW\": null}\n";
    return true;
}

// -----------------------------------------------------------------------------
// AMD iGPU Handler
// -----------------------------------------------------------------------------
static bool handle_amd_igpu(const std::string& card_dir, const std::string& device_dir) {
    std::string name = read_file_str(device_dir + "/product_name");
    if (name.empty()) name = read_file_str(device_dir + "/device_name");
    if (name.empty()) name = "AMD Radeon Graphics";

    int usage = static_cast<int>(read_file_int64(device_dir + "/gpu_busy_percent", 0));
    if (usage < 0) usage = 0;
    if (usage > 100) usage = 100;

    int64_t vram_used_bytes = read_file_int64(device_dir + "/mem_info_vis_vram_used", 0);
    int64_t vram_total_bytes = read_file_int64(device_dir + "/mem_info_vis_vram_total", 0);
    if (vram_total_bytes == 0) {
        vram_used_bytes = read_file_int64(device_dir + "/mem_info_vram_used", 0);
        vram_total_bytes = read_file_int64(device_dir + "/mem_info_vram_total", 0);
    }
    if (vram_total_bytes == 0) {
        vram_used_bytes = read_file_int64(device_dir + "/mem_info_gtt_used", 0);
        vram_total_bytes = read_file_int64(device_dir + "/mem_info_gtt_total", 0);
    }

    double vram_used_gb = vram_used_bytes / (1024.0 * 1024.0 * 1024.0);
    double vram_total_gb = vram_total_bytes / (1024.0 * 1024.0 * 1024.0);
    int vram_percent = (vram_total_bytes > 0) ? static_cast<int>(vram_used_bytes * 100 / vram_total_bytes) : 0;

    std::string temp = get_hwmon_temp(device_dir);

    std::cout << "{\"vendor\": \"amd\", \"name\": \"" << name << "\", "
              << "\"usagePercent\": " << usage << ", "
              << std::fixed << std::setprecision(1)
              << "\"vramUsedGB\": " << vram_used_gb << ", "
              << "\"vramTotalGB\": " << vram_total_gb << ", "
              << "\"vramPercent\": " << vram_percent << ", "
              << "\"tempEdgeC\": " << temp << ", "
              << "\"tempJunctionC\": null, \"tempMemC\": null, "
              << "\"fanRpm\": null, \"fanPercent\": null, "
              << "\"powerW\": null, \"powerLimitW\": null}\n";
    return true;
}

// -----------------------------------------------------------------------------
// NVIDIA dGPU Handler (if needed)
// -----------------------------------------------------------------------------
static bool handle_nvidia_dgpu() {
    // Check D3cold state
    for (int i = 0; i < 8; ++i) {
        std::string dev_dir = "/sys/class/drm/card" + std::to_string(i) + "/device";
        if (fs::exists(dev_dir)) {
            std::string vendor = read_file_str(dev_dir + "/vendor");
            if (vendor == "0x10de") {
                std::string pstate = read_file_str(dev_dir + "/power_state");
                if (pstate == "d3cold") {
                    return false; // Powered down
                }
            }
        }
    }

    std::string cmd = "nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,fan.speed --format=csv,noheader,nounits 2>/dev/null";
    FILE* fp = popen(cmd.c_str(), "r");
    if (!fp) return false;
    char buf[512];
    std::string out;
    if (fgets(buf, sizeof(buf), fp)) {
        out = buf;
    }
    pclose(fp);

    if (out.empty()) return false;
    while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) out.pop_back();

    std::vector<std::string> parts;
    std::stringstream ss(out);
    std::string item;
    while (std::getline(ss, item, ',')) {
        // trim whitespace
        size_t first = item.find_first_not_of(" \t");
        size_t last = item.find_last_not_of(" \t");
        if (first != std::string::npos && last != std::string::npos) {
            parts.push_back(item.substr(first, last - first + 1));
        } else {
            parts.push_back("");
        }
    }
    if (parts.size() < 4) return false;

    std::string name = parts[0];
    int usage = std::atoi(parts[1].c_str());
    double used_mb = std::atof(parts[2].c_str());
    double total_mb = std::atof(parts[3].c_str());
    double vram_used_gb = used_mb / 1024.0;
    double vram_total_gb = total_mb / 1024.0;
    int vram_percent = (total_mb > 0) ? static_cast<int>((used_mb * 100.0) / total_mb) : 0;
    std::string temp = (parts.size() > 4 && !parts[4].empty() && parts[4] != "[N/A]") ? parts[4] : "null";
    std::string pwr = (parts.size() > 5 && !parts[5].empty() && parts[5] != "[N/A]") ? parts[5] : "null";
    std::string pwr_lim = (parts.size() > 6 && !parts[6].empty() && parts[6] != "[N/A]") ? parts[6] : "null";
    std::string fan = (parts.size() > 7 && !parts[7].empty() && parts[7] != "[N/A]") ? parts[7] : "null";

    std::cout << "{\"vendor\": \"nvidia\", \"name\": \"" << name << "\", "
              << "\"usagePercent\": " << usage << ", "
              << std::fixed << std::setprecision(1)
              << "\"vramUsedGB\": " << vram_used_gb << ", "
              << "\"vramTotalGB\": " << vram_total_gb << ", "
              << "\"vramPercent\": " << vram_percent << ", "
              << "\"tempEdgeC\": " << temp << ", "
              << "\"tempJunctionC\": null, \"tempMemC\": null, "
              << "\"fanRpm\": " << fan << ", \"fanPercent\": " << fan << ", "
              << "\"powerW\": " << pwr << ", \"powerLimitW\": " << pwr_lim << "}\n";
    return true;
}

// -----------------------------------------------------------------------------
// Main Dispatcher
// -----------------------------------------------------------------------------
int main(int argc, char** argv) {
    bool query_dgpu = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--dgpu") == 0) query_dgpu = true;
    }

    if (query_dgpu) {
        if (handle_nvidia_dgpu()) return 0;
        // Search for AMD or Intel dGPU
        for (int i = 0; i < 8; ++i) {
            std::string card_dir = "/sys/class/drm/card" + std::to_string(i);
            std::string dev_dir = card_dir + "/device";
            if (!fs::exists(dev_dir)) continue;

            std::string vendor = to_lower(read_file_str(dev_dir + "/vendor"));
            if (vendor == "0x1002") {
                // AMD dGPU has dedicated VRAM
                if (fs::exists(dev_dir + "/mem_info_vram_total") && read_file_int64(dev_dir + "/mem_info_vram_total", 0) > 0) {
                    if (handle_amd_igpu(card_dir, dev_dir)) return 0;
                }
            } else if (vendor == "0x8086") {
                // Intel dGPU (Arc) has lmem_total_bytes
                if (fs::exists(dev_dir + "/lmem_total_bytes")) {
                    if (handle_intel_igpu(card_dir, dev_dir)) return 0;
                }
            }
        }
        std::cout << "{}\n";
        return 0;
    }

    // Default: Query iGPU (or primary active display GPU)
    for (int i = 0; i < 8; ++i) {
        std::string card_dir = "/sys/class/drm/card" + std::to_string(i);
        std::string dev_dir = card_dir + "/device";
        if (!fs::exists(dev_dir)) continue;

        std::string vendor = to_lower(read_file_str(dev_dir + "/vendor"));
        if (vendor == "0x8086") {
            // Intel iGPU: should NOT have lmem_total_bytes
            if (!fs::exists(dev_dir + "/lmem_total_bytes")) {
                if (handle_intel_igpu(card_dir, dev_dir)) return 0;
            }
        } else if (vendor == "0x1002") {
            // AMD iGPU
            if (handle_amd_igpu(card_dir, dev_dir)) return 0;
        }
    }

    // Fallback: check NVIDIA
    if (handle_nvidia_dgpu()) return 0;

    std::cout << "{}\n";
    return 0;
}
