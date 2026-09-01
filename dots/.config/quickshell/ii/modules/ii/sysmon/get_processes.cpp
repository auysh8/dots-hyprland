#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <filesystem>
#include <cstring>
#include <unistd.h>
#include <dirent.h>
#include <pwd.h>
#include <sys/types.h>
#include <iomanip>

namespace fs = std::filesystem;

struct ProcessInfo {
    std::string user;
    int pid;
    double cpu;
    double mem;
    double res_mb;
    std::string command;
    std::string full_command;
    std::string processIcon;
};

static std::unordered_map<uid_t, std::string> g_user_cache;

static std::string get_username(uid_t uid) {
    auto it = g_user_cache.find(uid);
    if (it != g_user_cache.end()) return it->second;
    struct passwd pwd;
    struct passwd* result;
    char buf[1024];
    if (getpwuid_r(uid, &pwd, buf, sizeof(buf), &result) == 0 && result) {
        g_user_cache[uid] = pwd.pw_name;
        return pwd.pw_name;
    }
    std::string uid_str = std::to_string(uid);
    g_user_cache[uid] = uid_str;
    return uid_str;
}

static std::string escape_json(const std::string& s) {
    std::ostringstream o;
    for (char c : s) {
        switch (c) {
            case '"': o << "\\\""; break;
            case '\\': o << "\\\\"; break;
            case '\b': o << "\\b"; break;
            case '\f': o << "\\f"; break;
            case '\n': o << "\\n"; break;
            case '\r': o << "\\r"; break;
            case '\t': o << "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) <= 0x1f) {
                    o << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(c);
                } else {
                    o << c;
                }
        }
    }
    return o.str();
}

static long get_total_system_memory_kb() {
    std::ifstream meminfo("/proc/meminfo");
    std::string line;
    while (std::getline(meminfo, line)) {
        if (line.rfind("MemTotal:", 0) == 0) {
            std::istringstream iss(line.substr(9));
            long total = 0;
            iss >> total;
            return total > 0 ? total : 1;
        }
    }
    return 1;
}

static std::string derive_icon_and_name(const std::string& full_command, const std::string& comm, std::string& display_name) {
    if (full_command.empty() || full_command[0] == '[') {
        display_name = full_command.empty() ? ("[" + comm + "]") : full_command;
        return "system-run";
    }

    std::string first_token = full_command;
    size_t space_pos = full_command.find(' ');
    if (space_pos != std::string::npos) {
        first_token = full_command.substr(0, space_pos);
    }

    std::string base_name = first_token;
    size_t slash_pos = first_token.rfind('/');
    if (slash_pos != std::string::npos) {
        base_name = first_token.substr(slash_pos + 1);
    }
    while (!base_name.empty() && (base_name.front() == ':' || base_name.front() == ' ')) base_name.erase(0, 1);
    while (!base_name.empty() && (base_name.back() == ':' || base_name.back() == ' ')) base_name.pop_back();

    std::string lower_base = base_name;
    std::transform(lower_base.begin(), lower_base.end(), lower_base.begin(), ::tolower);

    std::string icon_name = base_name;
    if (lower_base.find("python") != std::string::npos) icon_name = "application-x-python";
    else if (lower_base.find("zen") != std::string::npos) icon_name = "zen-browser";
    else if (lower_base.find("firefox") != std::string::npos) icon_name = "firefox";
    else if (lower_base.find("chrome") != std::string::npos) icon_name = "google-chrome";
    else if (lower_base.find("kitty") != std::string::npos) icon_name = "kitty";
    else if (lower_base.find("alacritty") != std::string::npos) icon_name = "Alacritty";
    else if (lower_base.find("qs") != std::string::npos || lower_base.find("quickshell") != std::string::npos) icon_name = "quickshell";
    else if (lower_base.find("hyprland") != std::string::npos) icon_name = "hyprland";

    if (lower_base.find("python") != std::string::npos && space_pos != std::string::npos) {
        std::string rest = full_command.substr(space_pos + 1);
        std::istringstream iss(rest);
        std::string tok;
        std::string script = "";
        while (iss >> tok) {
            if (!tok.empty() && tok[0] != '-') {
                script = tok;
                break;
            }
        }
        if (script.empty()) script = base_name;
        size_t script_slash = script.rfind('/');
        display_name = (script_slash != std::string::npos) ? script.substr(script_slash + 1) : script;
    } else {
        display_name = base_name;
        if (display_name.length() > 30) {
            display_name = display_name.substr(0, 30) + "...";
        }
    }

    return icon_name;
}

int main() {
    long total_mem_kb = get_total_system_memory_kb();
    long clock_ticks = sysconf(_SC_CLK_TCK);
    if (clock_ticks <= 0) clock_ticks = 100;

    // Read system uptime from /proc/uptime
    double uptime_seconds = 1.0;
    {
        std::ifstream upt("/proc/uptime");
        if (upt.is_open()) upt >> uptime_seconds;
    }

    std::vector<ProcessInfo> processes;
    processes.reserve(512);

    DIR* proc_dir = opendir("/proc");
    if (!proc_dir) {
        std::cout << "[]\n";
        return 0;
    }

    struct dirent* entry;
    while ((entry = readdir(proc_dir)) != nullptr) {
        if (entry->d_type != DT_DIR) continue;
        char* endptr = nullptr;
        long pid = std::strtol(entry->d_name, &endptr, 10);
        if (*endptr != '\0' || pid <= 0) continue;

        std::string pid_dir = std::string("/proc/") + entry->d_name;

        // 1. Read /proc/[pid]/stat
        std::string stat_path = pid_dir + "/stat";
        std::ifstream stat_file(stat_path);
        if (!stat_file.is_open()) continue;

        std::string stat_line;
        std::getline(stat_file, stat_line);
        stat_file.close();

        // comm is enclosed in parentheses
        size_t open_paren = stat_line.find('(');
        size_t close_paren = stat_line.rfind(')');
        if (open_paren == std::string::npos || close_paren == std::string::npos || close_paren <= open_paren) continue;

        std::string comm = stat_line.substr(open_paren + 1, close_paren - open_paren - 1);
        std::string rest = stat_line.substr(close_paren + 2); // after ") "
        std::istringstream rest_stream(rest);

        char state;
        long ppid, pgrp, session, tty_nr, tpgid;
        unsigned long flags, minflt, cminflt, majflt, cmajflt;
        unsigned long utime = 0, stime = 0;
        long cutime = 0, cstime = 0, priority = 0, nice_val = 0, num_threads = 0, itrealvalue = 0;
        unsigned long long starttime = 0;
        unsigned long vsize = 0;
        long rss_pages = 0;

        rest_stream >> state >> ppid >> pgrp >> session >> tty_nr >> tpgid >> flags
                    >> minflt >> cminflt >> majflt >> cmajflt
                    >> utime >> stime >> cutime >> cstime
                    >> priority >> nice_val >> num_threads >> itrealvalue
                    >> starttime >> vsize >> rss_pages;

        // 2. Read /proc/[pid]/cmdline
        std::string full_command = "";
        std::string cmdline_path = pid_dir + "/cmdline";
        std::ifstream cmd_file(cmdline_path, std::ios::binary);
        if (cmd_file.is_open()) {
            std::string content((std::istreambuf_iterator<char>(cmd_file)), std::istreambuf_iterator<char>());
            cmd_file.close();
            for (size_t i = 0; i < content.size(); ++i) {
                if (content[i] == '\0') {
                    if (i + 1 < content.size() && content[i + 1] != '\0') {
                        full_command += ' ';
                    }
                } else {
                    full_command += content[i];
                }
            }
        }
        if (full_command.empty()) {
            full_command = "[" + comm + "]";
        }

        // 3. Read /proc/[pid]/status for UID and VmRSS
        uid_t uid = 0;
        long rss_kb = 0;
        std::string status_path = pid_dir + "/status";
        std::ifstream status_file(status_path);
        if (status_file.is_open()) {
            std::string sline;
            while (std::getline(status_file, sline)) {
                if (sline.rfind("Uid:", 0) == 0) {
                    std::istringstream uiss(sline.substr(4));
                    uiss >> uid;
                } else if (sline.rfind("VmRSS:", 0) == 0) {
                    std::istringstream riss(sline.substr(6));
                    riss >> rss_kb;
                }
            }
            status_file.close();
        }
        if (rss_kb == 0 && rss_pages > 0) {
            long page_size_kb = sysconf(_SC_PAGESIZE) / 1024;
            rss_kb = rss_pages * (page_size_kb > 0 ? page_size_kb : 4);
        }

        // 4. Calculate CPU% and MEM%
        double process_time_sec = static_cast<double>(utime + stime) / clock_ticks;
        double process_age_sec = uptime_seconds - (static_cast<double>(starttime) / clock_ticks);
        double cpu_percent = 0.0;
        if (process_age_sec > 0.05) {
            cpu_percent = (process_time_sec / process_age_sec) * 100.0;
        }

        double mem_percent = (total_mem_kb > 0) ? (static_cast<double>(rss_kb) / total_mem_kb) * 100.0 : 0.0;
        double res_mb = static_cast<double>(rss_kb) / 1024.0;

        std::string display_name;
        std::string icon = derive_icon_and_name(full_command, comm, display_name);

        processes.push_back({
            get_username(uid),
            static_cast<int>(pid),
            cpu_percent,
            mem_percent,
            res_mb,
            display_name,
            full_command,
            icon
        });
    }
    closedir(proc_dir);

    std::sort(processes.begin(), processes.end(), [](const ProcessInfo& a, const ProcessInfo& b) {
        return a.cpu > b.cpu;
    });

    if (processes.size() > 500) {
        processes.resize(500);
    }

    std::cout << "[";
    for (size_t i = 0; i < processes.size(); ++i) {
        const auto& p = processes[i];
        if (i > 0) std::cout << ", ";
        std::cout << "{\"user\": \"" << escape_json(p.user) << "\""
                  << ", \"pid\": " << p.pid
                  << ", \"cpu\": " << std::fixed << std::setprecision(1) << p.cpu
                  << ", \"mem\": " << std::fixed << std::setprecision(1) << p.mem
                  << ", \"res_mb\": " << std::fixed << std::setprecision(2) << p.res_mb
                  << ", \"command\": \"" << escape_json(p.command) << "\""
                  << ", \"full_command\": \"" << escape_json(p.full_command) << "\""
                  << ", \"processIcon\": \"" << escape_json(p.processIcon) << "\"}";
    }
    std::cout << "]\n";

    return 0;
}
