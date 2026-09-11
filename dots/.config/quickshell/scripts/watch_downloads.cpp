#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <filesystem>
#include <cstring>
#include <unistd.h>
#include <sys/inotify.h>
#include <limits.h>
#include <cstdlib>

namespace fs = std::filesystem;

static const char* LOG_FILE = "/tmp/qs_popup.log";

static void log_popup(const std::string& type, const std::string& title, const std::string& message,
                      const std::string& category = "download", const std::string& action = "complete") {
    std::ofstream f(LOG_FILE, std::ios::app);
    if (f.is_open()) {
        f << type << "|" << title << "|" << message << "|" << category << "|" << action << "\n";
        f.flush();
    }
}

static bool should_ignore(const std::string& filename) {
    if (filename.empty() || filename[0] == '.') return true;
    if (filename.size() >= 11 && filename.rfind(".crdownload") == filename.size() - 11) return true;
    if (filename.size() >= 5 && filename.rfind(".part") == filename.size() - 5) return true;
    if (filename.size() >= 4 && filename.rfind(".tmp") == filename.size() - 4) return true;
    return false;
}

int main() {
    const char* home = std::getenv("HOME");
    if (!home) {
        std::cerr << "HOME environment variable not set.\n";
        return 1;
    }

    std::string downloads_dir = std::string(home) + "/Downloads";
    if (!fs::exists(downloads_dir)) {
        try {
            fs::create_directories(downloads_dir);
        } catch (...) {
            std::cerr << "Could not create or find Downloads directory: " << downloads_dir << "\n";
            return 1;
        }
    }

    int inotify_fd = inotify_init1(IN_CLOEXEC);
    if (inotify_fd < 0) {
        std::cerr << "Failed to initialize inotify.\n";
        return 1;
    }

    // Watch for completed writes (IN_CLOSE_WRITE) and files moved into directory (IN_MOVED_TO)
    int wd = inotify_add_watch(inotify_fd, downloads_dir.c_str(), IN_CLOSE_WRITE | IN_MOVED_TO);
    if (wd < 0) {
        std::cerr << "Failed to add inotify watch for " << downloads_dir << "\n";
        close(inotify_fd);
        return 1;
    }

    std::cout << "Watching " << downloads_dir << " with kernel inotify...\n";

    constexpr size_t BUF_LEN = (1024 * (sizeof(struct inotify_event) + NAME_MAX + 1));
    std::vector<char> buffer(BUF_LEN);

    while (true) {
        ssize_t num_read = read(inotify_fd, buffer.data(), BUF_LEN);
        if (num_read <= 0) {
            if (num_read < 0 && errno == EINTR) continue;
            break;
        }

        ssize_t i = 0;
        while (i < num_read) {
            auto* event = reinterpret_cast<struct inotify_event*>(&buffer[i]);
            if (event->len > 0) {
                std::string filename(event->name);
                if ((event->mask & (IN_CLOSE_WRITE | IN_MOVED_TO)) && !(event->mask & IN_ISDIR)) {
                    if (!should_ignore(filename)) {
                        std::cout << "New download: " << filename << std::endl;
                        log_popup("good", "Download", "Completed: " + filename, "download", "complete");
                    }
                }
            }
            i += sizeof(struct inotify_event) + event->len;
        }
    }

    inotify_rm_watch(inotify_fd, wd);
    close(inotify_fd);
    return 0;
}
