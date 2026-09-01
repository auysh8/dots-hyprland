#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <cmath>
#include <numeric>
#include <algorithm>
#include <filesystem>
#include <iomanip>
#include <cstring>

#define STB_IMAGE_IMPLEMENTATION
#include "include/stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "include/stb_image_write.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "include/stb_image_resize2.h"

namespace fs = std::filesystem;

// Helpers
static inline std::string to_hex(int r, int g, int b) {
    std::ostringstream ss;
    ss << "#" << std::hex << std::setfill('0')
       << std::setw(2) << (r & 0xFF)
       << std::setw(2) << (g & 0xFF)
       << std::setw(2) << (b & 0xFF);
    return ss.str();
}

static inline std::string trim(const std::string& str) {
    size_t first = str.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return "";
    size_t last = str.find_last_not_of(" \t\r\n");
    return str.substr(first, (last - first + 1));
}

// 1. Colorfulness & Scheme detection (Hasler-Süsstrunk algorithm)
int cmd_scheme(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: material-color-helper scheme <image_path>\n";
        return 1;
    }
    const char* img_path = argv[2];
    int w = 0, h = 0, channels = 0;
    unsigned char* data = stbi_load(img_path, &w, &h, &channels, 3);
    if (!data) {
        std::cout << "scheme-tonal-spot\n";
        return 0;
    }

    int step_x = std::max(1, w / 128);
    int step_y = std::max(1, h / 128);

    std::vector<double> rg;
    std::vector<double> yb;
    rg.reserve(128 * 128);
    yb.reserve(128 * 128);

    for (int y = 0; y < h; y += step_y) {
        for (int x = 0; x < w; x += step_x) {
            int idx = (y * w + x) * 3;
            double r = static_cast<double>(data[idx]);
            double g = static_cast<double>(data[idx + 1]);
            double b = static_cast<double>(data[idx + 2]);

            rg.push_back(std::abs(r - g));
            yb.push_back(std::abs(0.5 * (r + g) - b));
        }
    }
    stbi_image_free(data);

    size_t n = rg.size();
    if (n == 0) {
        std::cout << "scheme-tonal-spot\n";
        return 0;
    }

    double sum_rg = std::accumulate(rg.begin(), rg.end(), 0.0);
    double mean_rg = sum_rg / n;
    double sq_diff_rg = 0.0;
    for (double val : rg) {
        sq_diff_rg += (val - mean_rg) * (val - mean_rg);
    }
    double std_rg = std::sqrt(sq_diff_rg / n);

    double sum_yb = std::accumulate(yb.begin(), yb.end(), 0.0);
    double mean_yb = sum_yb / n;
    double sq_diff_yb = 0.0;
    for (double val : yb) {
        sq_diff_yb += (val - mean_yb) * (val - mean_yb);
    }
    double std_yb = std::sqrt(sq_diff_yb / n);

    double colorfulness = std::sqrt(std_rg * std_rg + std_yb * std_yb) +
                          (0.3 * std::sqrt(mean_rg * mean_rg + mean_yb * mean_yb));

    if (colorfulness < 40.0) {
        std::cout << "scheme-neutral\n";
    } else {
        std::cout << "scheme-tonal-spot\n";
    }
    return 0;
}

// 2. Fast Image Thumbnailing
int cmd_thumbnail(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: material-color-helper thumbnail <image_path> <out_path> [max_dim=256] [quality=85]\n";
        return 1;
    }
    const char* in_path = argv[2];
    const char* out_path = argv[3];
    int max_dim = (argc >= 5) ? std::atoi(argv[4]) : 256;
    int quality = (argc >= 6) ? std::atoi(argv[5]) : 85;

    int w = 0, h = 0, channels = 0;
    unsigned char* data = stbi_load(in_path, &w, &h, &channels, 3);
    if (!data) {
        std::cerr << "Error: Could not load image " << in_path << "\n";
        return 1;
    }

    int out_w = w, out_h = h;
    if (std::max(w, h) > max_dim) {
        if (w >= h) {
            out_w = max_dim;
            out_h = std::max(1, (h * max_dim) / w);
        } else {
            out_h = max_dim;
            out_w = std::max(1, (w * max_dim) / h);
        }
    }

    std::vector<unsigned char> out_data(out_w * out_h * 3);
    if (w == out_w && h == out_h) {
        std::memcpy(out_data.data(), data, w * h * 3);
    } else {
        stbir_resize_uint8_linear(data, w, h, 0, out_data.data(), out_w, out_h, 0, STBIR_RGB);
    }
    stbi_image_free(data);

    fs::path out_file(out_path);
    if (out_file.has_parent_path()) {
        fs::create_directories(out_file.parent_path());
    }

    std::string ext = out_file.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    int res = 0;
    if (ext == ".png") {
        res = stbi_write_png(out_path, out_w, out_h, 3, out_data.data(), out_w * 3);
    } else {
        res = stbi_write_jpg(out_path, out_w, out_h, 3, out_data.data(), quality);
    }
    return res ? 0 : 1;
}

// 3. Fast In-Memory Template Generator (Kitty, Ghostty, Escape Sequences)
int cmd_template(int argc, char** argv) {
    std::string scss_path = "";
    std::string out_dir = "";
    std::string templates_dir = "";
    std::string alpha = "100";

    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--scss" && i + 1 < argc) {
            scss_path = argv[++i];
        } else if (arg == "--out-dir" && i + 1 < argc) {
            out_dir = argv[++i];
        } else if (arg == "--templates-dir" && i + 1 < argc) {
            templates_dir = argv[++i];
        } else if (arg == "--alpha" && i + 1 < argc) {
            alpha = argv[++i];
        }
    }

    if (scss_path.empty() || out_dir.empty()) {
        std::cerr << "Usage: material-color-helper template --scss <file.scss> --out-dir <out_dir> [--templates-dir <dir>] [--alpha 100]\n";
        return 1;
    }

    std::ifstream scss_file(scss_path);
    if (!scss_file.is_open()) {
        std::cerr << "Error: Could not open scss file " << scss_path << "\n";
        return 1;
    }

    std::unordered_map<std::string, std::string> colors;
    std::string line;
    while (std::getline(scss_file, line)) {
        line = trim(line);
        if (line.empty() || line[0] != '$') continue;
        size_t colon = line.find(':');
        size_t semi = line.find(';');
        if (colon != std::string::npos && semi != std::string::npos && colon < semi) {
            std::string key = trim(line.substr(1, colon - 1));
            std::string val = trim(line.substr(colon + 1, semi - colon - 1));
            colors[key] = val;
        }
    }
    scss_file.close();

    fs::create_directories(out_dir);

    auto replace_template = [&](const std::string& tmpl_path, const std::string& out_path, bool is_sequences) {
        std::ifstream in(tmpl_path);
        if (!in.is_open()) return false;
        std::stringstream buffer;
        buffer << in.rdbuf();
        std::string content = buffer.str();
        in.close();

        for (const auto& [k, v] : colors) {
            std::string hex_raw = (v.size() > 0 && v[0] == '#') ? v.substr(1) : v;
            
            // Pattern 1: #$key # -> #hex_raw
            std::string pat1 = "#$" + k + " #";
            std::string rep1 = "#" + hex_raw;
            size_t pos = 0;
            while ((pos = content.find(pat1, pos)) != std::string::npos) {
                content.replace(pos, pat1.length(), rep1);
                pos += rep1.length();
            }

            // Pattern 2: $key # -> hex_raw
            std::string pat2 = "$" + k + " #";
            std::string rep2 = hex_raw;
            pos = 0;
            while ((pos = content.find(pat2, pos)) != std::string::npos) {
                content.replace(pos, pat2.length(), rep2);
                pos += rep2.length();
            }
        }

        if (is_sequences) {
            std::string pat_alpha = "$alpha";
            size_t pos = 0;
            while ((pos = content.find(pat_alpha, pos)) != std::string::npos) {
                content.replace(pos, pat_alpha.length(), alpha);
                pos += alpha.length();
            }
        }

        std::ofstream out(out_path);
        if (!out.is_open()) return false;
        out << content;
        out.close();
        return true;
    };

    if (!templates_dir.empty()) {
        std::string kitty_tmpl = templates_dir + "/kitty-theme.conf";
        std::string kitty_out = out_dir + "/kitty-theme.conf";
        replace_template(kitty_tmpl, kitty_out, false);

        std::string seq_tmpl = templates_dir + "/sequences.txt";
        std::string seq_out = out_dir + "/sequences.txt";
        replace_template(seq_tmpl, seq_out, true);
    }

    auto get_col = [&](const std::string& name, const std::string& fallback = "#ffffff") -> std::string {
        auto it = colors.find(name);
        return (it != colors.end()) ? it->second : fallback;
    };

    std::ostringstream ghostty;
    for (int i = 0; i < 16; ++i) {
        std::string name = "term" + std::to_string(i);
        std::string val = get_col(name);
        if (!val.empty() && val[0] == '#') val = val.substr(1);
        ghostty << "palette = " << i << "=#" << val << "\n";
    }
    ghostty << "background = " << get_col("term0") << "\n";
    ghostty << "foreground = " << get_col("term7") << "\n";
    ghostty << "cursor-color = " << get_col("term7") << "\n";
    ghostty << "cursor-text = " << get_col("term0") << "\n";
    ghostty << "selection-background = " << get_col("onSecondaryContainer") << "\n";
    ghostty << "selection-foreground = " << get_col("secondaryContainer") << "\n";
    ghostty << "window-titlebar-background = " << get_col("term0") << "\n";
    ghostty << "window-titlebar-foreground = " << get_col("term7") << "\n";

    std::ofstream ghostty_out(out_dir + "/ghostty-theme.conf");
    if (ghostty_out.is_open()) {
        ghostty_out << ghostty.str();
        ghostty_out.close();
    }

    return 0;
}

// 4. Text Contrast Color Extraction
int cmd_text_color(int argc, char** argv) {
    int w = 0, h = 0, channels = 0;
    unsigned char* data = nullptr;

    if (argc >= 3 && std::string(argv[2]) != "-") {
        data = stbi_load(argv[2], &w, &h, &channels, 3);
    } else {
        std::vector<unsigned char> buffer;
        unsigned char chunk[4096];
        while (std::cin.read(reinterpret_cast<char*>(chunk), sizeof(chunk))) {
            buffer.insert(buffer.end(), chunk, chunk + std::cin.gcount());
        }
        if (std::cin.gcount() > 0) {
            buffer.insert(buffer.end(), chunk, chunk + std::cin.gcount());
        }
        if (!buffer.empty()) {
            data = stbi_load_from_memory(buffer.data(), static_cast<int>(buffer.size()), &w, &h, &channels, 3);
        }
    }

    if (!data || w <= 0 || h <= 0) {
        std::cout << "{\"background\": \"#000000\", \"text\": \"#ffffff\"}\n";
        return 0;
    }

    int c_idx[4] = {
        0,
        (w - 1) * 3,
        ((h - 1) * w) * 3,
        ((h - 1) * w + (w - 1)) * 3
    };

    std::vector<int> r_corners, g_corners, b_corners;
    for (int idx : c_idx) {
        r_corners.push_back(data[idx]);
        g_corners.push_back(data[idx + 1]);
        b_corners.push_back(data[idx + 2]);
    }
    std::sort(r_corners.begin(), r_corners.end());
    std::sort(g_corners.begin(), g_corners.end());
    std::sort(b_corners.begin(), b_corners.end());

    int bg_r = (r_corners[1] + r_corners[2]) / 2;
    int bg_g = (g_corners[1] + g_corners[2]) / 2;
    int bg_b = (b_corners[1] + b_corners[2]) / 2;

    int total_pixels = w * h;
    std::vector<double> distances;
    distances.reserve(total_pixels);

    for (int i = 0; i < total_pixels; ++i) {
        int idx = i * 3;
        double dr = static_cast<double>(data[idx] - bg_r);
        double dg = static_cast<double>(data[idx + 1] - bg_g);
        double db = static_cast<double>(data[idx + 2] - bg_b);
        distances.push_back(std::sqrt(dr * dr + dg * dg + db * db));
    }

    std::vector<double> sorted_dist = distances;
    std::sort(sorted_dist.begin(), sorted_dist.end());
    size_t p95_idx = static_cast<size_t>(0.95 * sorted_dist.size());
    double threshold = (p95_idx < sorted_dist.size()) ? sorted_dist[p95_idx] : 0.0;

    std::vector<int> text_r, text_g, text_b;
    for (int i = 0; i < total_pixels; ++i) {
        if (distances[i] >= threshold) {
            int idx = i * 3;
            text_r.push_back(data[idx]);
            text_g.push_back(data[idx + 1]);
            text_b.push_back(data[idx + 2]);
        }
    }
    stbi_image_free(data);

    int txt_r = 255, txt_g = 255, txt_b = 255;
    if (!text_r.empty()) {
        std::sort(text_r.begin(), text_r.end());
        std::sort(text_g.begin(), text_g.end());
        std::sort(text_b.begin(), text_b.end());
        txt_r = text_r[text_r.size() / 2];
        txt_g = text_g[text_g.size() / 2];
        txt_b = text_b[text_b.size() / 2];
    }

    std::cout << "{\"background\": \"" << to_hex(bg_r, bg_g, bg_b) << "\", \"text\": \"" << to_hex(txt_r, txt_g, txt_b) << "\"}\n";
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: material-color-helper <subcommand> [args...]\n"
                  << "Subcommands:\n"
                  << "  scheme <image_path>\n"
                  << "  thumbnail <image_path> <out_path> [max_dim] [quality]\n"
                  << "  template --scss <file.scss> --out-dir <out_dir> [--templates-dir <dir>] [--alpha 100]\n"
                  << "  text-color [image_path|-]\n";
        return 1;
    }

    std::string subcmd = argv[1];
    if (subcmd == "scheme") {
        return cmd_scheme(argc, argv);
    } else if (subcmd == "thumbnail") {
        return cmd_thumbnail(argc, argv);
    } else if (subcmd == "template") {
        return cmd_template(argc, argv);
    } else if (subcmd == "text-color") {
        return cmd_text_color(argc, argv);
    } else {
        std::cerr << "Unknown subcommand: " << subcmd << "\n";
        return 1;
    }
}
