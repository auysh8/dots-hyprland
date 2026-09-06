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

#include <thread>
#include <mutex>
#include <atomic>
#include <unordered_set>
#include <cstdlib>
#include <unistd.h>

#if __has_include(<webp/decode.h>)
#include <webp/decode.h>
#define HAVE_LIBWEBP 1
#else
#define HAVE_LIBWEBP 0
#endif

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

// RFC 1321 MD5 Implementation (Byte-for-byte Freedesktop thumbnail spec parity)
struct MD5Context {
    uint32_t state[4];
    uint32_t count[2];
    uint8_t buffer[64];
};

static void MD5Transform(uint32_t state[4], const uint8_t block[64]);

static void MD5Init(MD5Context *ctx) {
    ctx->count[0] = ctx->count[1] = 0;
    ctx->state[0] = 0x67452301;
    ctx->state[1] = 0xefcdab89;
    ctx->state[2] = 0x98badcfe;
    ctx->state[3] = 0x10325476;
}

static void MD5Update(MD5Context *ctx, const uint8_t *input, size_t inputLen) {
    size_t i, index, partLen;
    index = (size_t)((ctx->count[0] >> 3) & 0x3F);
    if ((ctx->count[0] += ((uint32_t)inputLen << 3)) < ((uint32_t)inputLen << 3))
        ctx->count[1]++;
    ctx->count[1] += ((uint32_t)inputLen >> 29);
    partLen = 64 - index;
    if (inputLen >= partLen) {
        std::memcpy(&ctx->buffer[index], input, partLen);
        MD5Transform(ctx->state, ctx->buffer);
        for (i = partLen; i + 63 < inputLen; i += 64)
            MD5Transform(ctx->state, &input[i]);
        index = 0;
    } else {
        i = 0;
    }
    std::memcpy(&ctx->buffer[index], &input[i], inputLen - i);
}

static void MD5Final(uint8_t digest[16], MD5Context *ctx) {
    static const uint8_t PADDING[64] = { 0x80 };
    uint8_t bits[8];
    for (int i = 0; i < 4; ++i) {
        bits[i] = (uint8_t)((ctx->count[0] >> (i * 8)) & 0xFF);
        bits[i + 4] = (uint8_t)((ctx->count[1] >> (i * 8)) & 0xFF);
    }
    size_t index = (size_t)((ctx->count[0] >> 3) & 0x3f);
    size_t padLen = (index < 56) ? (56 - index) : (120 - index);
    MD5Update(ctx, PADDING, padLen);
    MD5Update(ctx, bits, 8);
    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < 4; ++j) {
            digest[i * 4 + j] = (uint8_t)((ctx->state[i] >> (j * 8)) & 0xFF);
        }
    }
}

#define MD5_F(x, y, z) (((x) & (y)) | ((~x) & (z)))
#define MD5_G(x, y, z) (((x) & (z)) | ((y) & (~z)))
#define MD5_H(x, y, z) ((x) ^ (y) ^ (z))
#define MD5_I(x, y, z) ((y) ^ ((x) | (~z)))
#define MD5_ROTATE_LEFT(x, n) (((x) << (n)) | ((x) >> (32-(n))))
#define MD5_FF(a, b, c, d, x, s, ac) { (a) += MD5_F ((b), (c), (d)) + (x) + (uint32_t)(ac); (a) = MD5_ROTATE_LEFT ((a), (s)); (a) += (b); }
#define MD5_GG(a, b, c, d, x, s, ac) { (a) += MD5_G ((b), (c), (d)) + (x) + (uint32_t)(ac); (a) = MD5_ROTATE_LEFT ((a), (s)); (a) += (b); }
#define MD5_HH(a, b, c, d, x, s, ac) { (a) += MD5_H ((b), (c), (d)) + (x) + (uint32_t)(ac); (a) = MD5_ROTATE_LEFT ((a), (s)); (a) += (b); }
#define MD5_II(a, b, c, d, x, s, ac) { (a) += MD5_I ((b), (c), (d)) + (x) + (uint32_t)(ac); (a) = MD5_ROTATE_LEFT ((a), (s)); (a) += (b); }

static void MD5Transform(uint32_t state[4], const uint8_t block[64]) {
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3], x[16];
    for (int i = 0, j = 0; j < 64; ++i, j += 4)
        x[i] = ((uint32_t)block[j]) | (((uint32_t)block[j+1]) << 8) |
               (((uint32_t)block[j+2]) << 16) | (((uint32_t)block[j+3]) << 24);

    MD5_FF (a, b, c, d, x[ 0],  7, 0xd76aa478);
    MD5_FF (d, a, b, c, x[ 1], 12, 0xe8c7b756);
    MD5_FF (c, d, a, b, x[ 2], 17, 0x242070db);
    MD5_FF (b, c, d, a, x[ 3], 22, 0xc1bdceee);
    MD5_FF (a, b, c, d, x[ 4],  7, 0xf57c0faf);
    MD5_FF (d, a, b, c, x[ 5], 12, 0x4787c62a);
    MD5_FF (c, d, a, b, x[ 6], 17, 0xa8304613);
    MD5_FF (b, c, d, a, x[ 7], 22, 0xfd469501);
    MD5_FF (a, b, c, d, x[ 8],  7, 0x698098d8);
    MD5_FF (d, a, b, c, x[ 9], 12, 0x8b44f7af);
    MD5_FF (c, d, a, b, x[10], 17, 0xffff5bb1);
    MD5_FF (b, c, d, a, x[11], 22, 0x895cd7be);
    MD5_FF (a, b, c, d, x[12],  7, 0x6b901122);
    MD5_FF (d, a, b, c, x[13], 12, 0xfd987193);
    MD5_FF (c, d, a, b, x[14], 17, 0xa679438e);
    MD5_FF (b, c, d, a, x[15], 22, 0x49b40821);

    MD5_GG (a, b, c, d, x[ 1],  5, 0xf61e2562);
    MD5_GG (d, a, b, c, x[ 6],  9, 0xc040b340);
    MD5_GG (c, d, a, b, x[11], 14, 0x265e5a51);
    MD5_GG (b, c, d, a, x[ 0], 20, 0xe9b6c7aa);
    MD5_GG (a, b, c, d, x[ 5],  5, 0xd62f105d);
    MD5_GG (d, a, b, c, x[10],  9,  0x2441453);
    MD5_GG (c, d, a, b, x[15], 14, 0xd8a1e681);
    MD5_GG (b, c, d, a, x[ 4], 20, 0xe7d3fbc8);
    MD5_GG (a, b, c, d, x[ 9],  5, 0x21e1cde6);
    MD5_GG (d, a, b, c, x[14],  9, 0xc33707d6);
    MD5_GG (c, d, a, b, x[ 3], 14, 0xf4d50d87);
    MD5_GG (b, c, d, a, x[ 8], 20, 0x455a14ed);
    MD5_GG (a, b, c, d, x[13],  5, 0xa9e3e905);
    MD5_GG (d, a, b, c, x[ 2],  9, 0xfcefa3f8);
    MD5_GG (c, d, a, b, x[ 7], 14, 0x676f02d9);
    MD5_GG (b, c, d, a, x[12], 20, 0x8d2a4c8a);

    MD5_HH (a, b, c, d, x[ 5],  4, 0xfffa3942);
    MD5_HH (d, a, b, c, x[ 8], 11, 0x8771f681);
    MD5_HH (c, d, a, b, x[11], 16, 0x6d9d6122);
    MD5_HH (b, c, d, a, x[14], 23, 0xfde5380c);
    MD5_HH (a, b, c, d, x[ 1],  4, 0xa4beea44);
    MD5_HH (d, a, b, c, x[ 4], 11, 0x4bdecfa9);
    MD5_HH (c, d, a, b, x[ 7], 16, 0xf6bb4b60);
    MD5_HH (b, c, d, a, x[10], 23, 0xbebfbc70);
    MD5_HH (a, b, c, d, x[13],  4, 0x289b7ec6);
    MD5_HH (d, a, b, c, x[ 0], 11, 0xeaa127fa);
    MD5_HH (c, d, a, b, x[ 3], 16, 0xd4ef3085);
    MD5_HH (b, c, d, a, x[ 6], 23,  0x4881d05);
    MD5_HH (a, b, c, d, x[ 9],  4, 0xd9d4d039);
    MD5_HH (d, a, b, c, x[12], 11, 0xe6db99e5);
    MD5_HH (c, d, a, b, x[15], 16, 0x1fa27cf8);
    MD5_HH (b, c, d, a, x[ 2], 23, 0xc4ac5665);

    MD5_II (a, b, c, d, x[ 0],  6, 0xf4292244);
    MD5_II (d, a, b, c, x[ 7], 10, 0x432aff97);
    MD5_II (c, d, a, b, x[14], 15, 0xab9423a7);
    MD5_II (b, c, d, a, x[ 5], 21, 0xfc93a039);
    MD5_II (a, b, c, d, x[12],  6, 0x655b59c3);
    MD5_II (d, a, b, c, x[ 3], 10, 0x8f0ccc92);
    MD5_II (c, d, a, b, x[10], 15, 0xffeff47d);
    MD5_II (b, c, d, a, x[ 1], 21, 0x85845dd1);
    MD5_II (a, b, c, d, x[ 8],  6, 0x6fa87e4f);
    MD5_II (d, a, b, c, x[15], 10, 0xfe2ce6e0);
    MD5_II (c, d, a, b, x[ 6], 15, 0xa3014314);
    MD5_II (b, c, d, a, x[13], 21, 0x4e0811a1);
    MD5_II (a, b, c, d, x[ 4],  6, 0xf7537e82);
    MD5_II (d, a, b, c, x[11], 10, 0xbd3af235);
    MD5_II (c, d, a, b, x[ 2], 15, 0x2ad7d2bb);
    MD5_II (b, c, d, a, x[ 9], 21, 0xeb86d391);

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
}

static inline std::string md5_hex(const std::string& input) {
    MD5Context ctx;
    MD5Init(&ctx);
    MD5Update(&ctx, reinterpret_cast<const uint8_t*>(input.data()), input.size());
    uint8_t digest[16];
    MD5Final(digest, &ctx);
    std::ostringstream ss;
    ss << std::hex << std::setfill('0');
    for (int i = 0; i < 16; ++i) {
        ss << std::setw(2) << (int)digest[i];
    }
    return ss.str();
}

static inline std::string freedesktop_uri(const std::string& abs_path) {
    std::ostringstream escaped;
    escaped.fill('0');
    for (unsigned char c : abs_path) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~' || c == '/' || c == '(' || c == ')' || c == '*') {
            escaped << (char)c;
        } else {
            escaped << '%' << std::hex << std::uppercase << std::setw(2) << (int)c << std::nouppercase;
        }
    }
    return "file://" + escaped.str();
}

static inline std::string get_cache_root() {
    const char* env = std::getenv("XDG_CACHE_HOME");
    if (env && env[0] != '\0') return std::string(env);
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') return std::string(home) + "/.cache";
    return "/tmp";
}

static inline bool is_cache_fresh(const std::string& src_path, const std::string& cache_path) {
    std::error_code ec;
    if (!fs::exists(cache_path, ec)) return false;
    auto t_src = fs::last_write_time(src_path, ec);
    if (ec) return false;
    auto t_cache = fs::last_write_time(cache_path, ec);
    if (ec) return false;
    return t_cache >= t_src;
}

// Unified Image Buffer
struct ImageBuffer {
    int w = 0;
    int h = 0;
    int channels = 3;
    unsigned char* data = nullptr;
    bool is_webp = false;

    ~ImageBuffer() {
        if (data) {
#if HAVE_LIBWEBP
            if (is_webp) {
                WebPFree(data);
                return;
            }
#endif
            stbi_image_free(data);
        }
    }
};

static std::unique_ptr<ImageBuffer> load_image(const std::string& path) {
    auto img = std::make_unique<ImageBuffer>();
    std::string ext = fs::path(path).extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

#if HAVE_LIBWEBP
    if (ext == ".webp") {
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (file.is_open()) {
            std::streamsize size = file.tellg();
            file.seekg(0, std::ios::beg);
            std::vector<uint8_t> buffer(size);
            if (file.read(reinterpret_cast<char*>(buffer.data()), size)) {
                img->data = WebPDecodeRGB(buffer.data(), buffer.size(), &img->w, &img->h);
                if (img->data) {
                    img->channels = 3;
                    img->is_webp = true;
                    return img;
                }
            }
        }
    }
#endif

    img->data = stbi_load(path.c_str(), &img->w, &img->h, &img->channels, 3);
    if (img->data) {
        img->channels = 3;
        img->is_webp = false;
        return img;
    }
    return nullptr;
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

// 5. High-Performance Multi-Threaded Batch Wallpaper Cropping
static bool process_single_crop(const std::string& src_path, const std::string& out_path, int tw, int th) {
    fs::path out_file(out_path);
    if (out_file.has_parent_path()) {
        std::error_code ec;
        fs::create_directories(out_file.parent_path(), ec);
    }

    auto img = load_image(src_path);
    if (img && img->data && img->w > 0 && img->h > 0) {
        int w = img->w;
        int h = img->h;
        int crop_w = w;
        int crop_h = h;
        int src_x = 0;
        int src_y = 0;

        if ((int64_t)w * th > (int64_t)h * tw) {
            crop_h = h;
            crop_w = std::max(1, static_cast<int>((int64_t)h * tw / th));
            src_x = std::max(0, (w - crop_w) / 2);
            src_y = 0;
        } else {
            crop_w = w;
            crop_h = std::max(1, static_cast<int>((int64_t)w * th / tw));
            src_x = 0;
            src_y = std::max(0, (h - crop_h) / 2);
        }

        if (w == tw && h == th && src_x == 0 && src_y == 0) {
            return stbi_write_png(out_path.c_str(), tw, th, 3, img->data, tw * 3) != 0;
        }

        std::vector<unsigned char> out_data(tw * th * 3);
        const unsigned char* in_sub = img->data + (src_y * w + src_x) * 3;
        
        STBIR_RESIZE resize;
        stbir_resize_init(&resize, in_sub, crop_w, crop_h, w * 3, out_data.data(), tw, th, tw * 3, STBIR_RGB, STBIR_TYPE_UINT8);
        stbir_set_filters(&resize, STBIR_FILTER_MITCHELL, STBIR_FILTER_MITCHELL);
        if (!stbir_resize_extended(&resize)) {
            stbir_resize_uint8_linear(in_sub, crop_w, crop_h, w * 3, out_data.data(), tw, th, 0, STBIR_RGB);
        }
        return stbi_write_png(out_path.c_str(), tw, th, 3, out_data.data(), tw * 3) != 0;
    }

    // Fallback to ImageMagick for formats stb doesn't support directly (e.g. svg, avif)
    std::string cmd = "magick '" + src_path + "' -gravity Center -resize '" +
                      std::to_string(tw) + "x" + std::to_string(th) + "^' -extent '" +
                      std::to_string(tw) + "x" + std::to_string(th) + "' +repage '" +
                      out_path + "' >/dev/null 2>&1";
    return system(cmd.c_str()) == 0;
}

static std::unordered_set<std::string> parse_extensions(const std::string& ext_str) {
    std::unordered_set<std::string> exts;
    std::stringstream ss(ext_str);
    std::string item;
    while (std::getline(ss, item, '|')) {
        item = trim(item);
        if (item.empty()) continue;
        if (item.rfind("*.", 0) == 0) item = item.substr(1);
        if (!item.empty() && item[0] != '.') item = "." + item;
        std::transform(item.begin(), item.end(), item.begin(), ::tolower);
        exts.insert(item);
    }
    return exts;
}

int cmd_crop_batch(int argc, char** argv) {
    std::string mode = "";
    std::string target = "";
    std::string resolution = "1920x1080";
    std::string extensions_pattern = "*.jpg|*.jpeg|*.png|*.webp|*.avif|*.bmp";
    bool machine_progress = false;

    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "--file" || arg == "-f") && i + 1 < argc) {
            mode = "file";
            target = argv[++i];
        } else if ((arg == "--directory" || arg == "-d") && i + 1 < argc) {
            mode = "dir";
            target = argv[++i];
        } else if ((arg == "--resolution" || arg == "-r") && i + 1 < argc) {
            resolution = argv[++i];
        } else if ((arg == "--extensions" || arg == "-e") && i + 1 < argc) {
            extensions_pattern = argv[++i];
        } else if (arg == "--machine_progress") {
            machine_progress = true;
        }
    }

    if (target.empty()) {
        std::cerr << "Error: No target specified. Use --file or --directory.\n";
        return 1;
    }

    int tw = 1920, th = 1080;
    auto x_pos = resolution.find('x');
    if (x_pos != std::string::npos) {
        try {
            tw = std::stoi(resolution.substr(0, x_pos));
            th = std::stoi(resolution.substr(x_pos + 1));
        } catch (...) {
            tw = 1920; th = 1080;
        }
    }

    std::string cache_dir = get_cache_root() + "/wallpapers/" + resolution;
    std::unordered_set<std::string> allowed_exts = parse_extensions(extensions_pattern);

    std::vector<std::string> all_files;
    if (mode == "file") {
        std::error_code ec;
        if (fs::is_regular_file(target, ec)) {
            all_files.push_back(fs::canonical(target, ec).string());
        }
    } else {
        std::error_code ec;
        if (fs::is_directory(target, ec)) {
            for (const auto& entry : fs::directory_iterator(target, ec)) {
                if (entry.is_regular_file(ec)) {
                    std::string ext = entry.path().extension().string();
                    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                    if (allowed_exts.count(ext)) {
                        all_files.push_back(entry.path().string());
                    }
                }
            }
        }
    }

    int total_files = static_cast<int>(all_files.size());
    if (total_files == 0) return 0;

    std::vector<std::pair<std::string, std::string>> cached_tasks;
    std::vector<std::pair<std::string, std::string>> work_tasks;

    for (const auto& file_path : all_files) {
        std::string uri = freedesktop_uri(file_path);
        std::string hash = md5_hex(uri);
        std::string out_path = cache_dir + "/" + hash + ".png";
        if (is_cache_fresh(file_path, out_path)) {
            cached_tasks.push_back({file_path, out_path});
        } else {
            work_tasks.push_back({file_path, out_path});
        }
    }

    std::mutex out_mtx;
    std::atomic<int> completed_count(0);

    auto report = [&](const std::string& file) {
        int done = ++completed_count;
        if (machine_progress) {
            std::lock_guard<std::mutex> lock(out_mtx);
            std::cout << "PROGRESS " << done << "/" << total_files << " FILE " << file << "\n" << std::flush;
        }
    };

    // Fast-path report cached files
    for (const auto& item : cached_tasks) {
        report(item.first);
    }

    if (!work_tasks.empty()) {
        size_t hw = std::thread::hardware_concurrency();
        size_t num_threads = std::clamp(hw, static_cast<size_t>(1), std::min(static_cast<size_t>(16), work_tasks.size()));
        std::atomic<size_t> next_idx(0);
        std::vector<std::thread> workers;
        workers.reserve(num_threads);

        for (size_t t = 0; t < num_threads; ++t) {
            workers.emplace_back([&]() {
                while (true) {
                    size_t idx = next_idx.fetch_add(1);
                    if (idx >= work_tasks.size()) break;
                    const auto& task = work_tasks[idx];
                    process_single_crop(task.first, task.second, tw, th);
                    report(task.first);
                }
            });
        }

        for (auto& w : workers) {
            if (w.joinable()) w.join();
        }
    }

    return 0;
}

// 6. High-Performance Multi-Threaded Batch Thumbnail Generation
static int get_thumbnail_size_dim(const std::string& size_str, std::string& size_dir) {
    if (size_str == "normal") { size_dir = "normal"; return 128; }
    if (size_str == "large") { size_dir = "large"; return 256; }
    if (size_str == "x-large") { size_dir = "x-large"; return 512; }
    if (size_str == "xx-large") { size_dir = "xx-large"; return 1024; }

    try {
        int val = std::stoi(size_str);
        if (val <= 128) { size_dir = "normal"; return 128; }
        if (val <= 256) { size_dir = "large"; return 256; }
        if (val <= 512) { size_dir = "x-large"; return 512; }
        size_dir = "xx-large"; return 1024;
    } catch (...) {
        size_dir = "normal";
        return 128;
    }
}

static bool process_single_thumbnail(const std::string& src_path, const std::string& out_path, int max_dim) {
    fs::path out_file(out_path);
    if (out_file.has_parent_path()) {
        std::error_code ec;
        fs::create_directories(out_file.parent_path(), ec);
    }

    auto img = load_image(src_path);
    if (img && img->data && img->w > 0 && img->h > 0) {
        int w = img->w;
        int h = img->h;
        int out_w = w;
        int out_h = h;
        if (std::max(w, h) > max_dim) {
            if (w >= h) {
                out_w = max_dim;
                out_h = std::max(1, static_cast<int>((int64_t)h * max_dim / w));
            } else {
                out_h = max_dim;
                out_w = std::max(1, static_cast<int>((int64_t)w * max_dim / h));
            }
        }

        if (w == out_w && h == out_h) {
            return stbi_write_png(out_path.c_str(), out_w, out_h, 3, img->data, out_w * 3) != 0;
        }

        std::vector<unsigned char> out_data(out_w * out_h * 3);
        stbir_resize_uint8_linear(img->data, w, h, 0, out_data.data(), out_w, out_h, 0, STBIR_RGB);
        return stbi_write_png(out_path.c_str(), out_w, out_h, 3, out_data.data(), out_w * 3) != 0;
    }

    // Fallback to ImageMagick
    std::string cmd = "magick '" + src_path + "' -resize '" +
                      std::to_string(max_dim) + "x" + std::to_string(max_dim) + "' '" +
                      out_path + "' >/dev/null 2>&1";
    return system(cmd.c_str()) == 0;
}

int cmd_thumbnail_batch(int argc, char** argv) {
    std::string mode = "";
    std::string target = "";
    std::string size_arg = "normal";
    std::string extensions_pattern = "*.jpg|*.jpeg|*.png|*.webp|*.avif|*.bmp|*.svg";
    bool machine_progress = false;

    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "--file" || arg == "-f") && i + 1 < argc) {
            mode = "file";
            target = argv[++i];
        } else if ((arg == "--directory" || arg == "-d") && i + 1 < argc) {
            mode = "dir";
            target = argv[++i];
        } else if ((arg == "--size" || arg == "-s") && i + 1 < argc) {
            size_arg = argv[++i];
        } else if ((arg == "--extensions" || arg == "-e") && i + 1 < argc) {
            extensions_pattern = argv[++i];
        } else if (arg == "--machine_progress") {
            machine_progress = true;
        }
    }

    if (target.empty()) {
        std::cerr << "Error: No target specified. Use --file or --directory.\n";
        return 1;
    }

    std::string size_dir = "normal";
    int max_dim = get_thumbnail_size_dim(size_arg, size_dir);
    std::string cache_dir = get_cache_root() + "/thumbnails/" + size_dir;
    std::unordered_set<std::string> allowed_exts = parse_extensions(extensions_pattern);

    std::vector<std::string> all_files;
    if (mode == "file") {
        std::error_code ec;
        if (fs::is_regular_file(target, ec)) {
            all_files.push_back(fs::canonical(target, ec).string());
        }
    } else {
        std::error_code ec;
        if (fs::is_directory(target, ec)) {
            for (const auto& entry : fs::directory_iterator(target, ec)) {
                if (entry.is_regular_file(ec)) {
                    std::string ext = entry.path().extension().string();
                    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                    if (allowed_exts.count(ext)) {
                        all_files.push_back(entry.path().string());
                    }
                }
            }
        }
    }

    int total_files = static_cast<int>(all_files.size());
    if (total_files == 0) return 0;

    std::vector<std::pair<std::string, std::string>> cached_tasks;
    std::vector<std::pair<std::string, std::string>> work_tasks;

    for (const auto& file_path : all_files) {
        std::string uri = freedesktop_uri(file_path);
        std::string hash = md5_hex(uri);
        std::string out_path = cache_dir + "/" + hash + ".png";
        if (is_cache_fresh(file_path, out_path)) {
            cached_tasks.push_back({file_path, out_path});
        } else {
            work_tasks.push_back({file_path, out_path});
        }
    }

    std::mutex out_mtx;
    std::atomic<int> completed_count(0);

    auto report = [&](const std::string& file) {
        int done = ++completed_count;
        if (machine_progress) {
            std::lock_guard<std::mutex> lock(out_mtx);
            std::cout << "PROGRESS " << done << "/" << total_files << " FILE " << file << "\n" << std::flush;
        }
    };

    // Fast-path report cached files
    for (const auto& item : cached_tasks) {
        report(item.first);
    }

    if (!work_tasks.empty()) {
        size_t hw = std::thread::hardware_concurrency();
        size_t num_threads = std::clamp(hw, static_cast<size_t>(1), std::min(static_cast<size_t>(16), work_tasks.size()));
        std::atomic<size_t> next_idx(0);
        std::vector<std::thread> workers;
        workers.reserve(num_threads);

        for (size_t t = 0; t < num_threads; ++t) {
            workers.emplace_back([&]() {
                while (true) {
                    size_t idx = next_idx.fetch_add(1);
                    if (idx >= work_tasks.size()) break;
                    const auto& task = work_tasks[idx];
                    process_single_thumbnail(task.first, task.second, max_dim);
                    report(task.first);
                }
            });
        }

        for (auto& w : workers) {
            if (w.joinable()) w.join();
        }
    }

    return 0;
}

// 7. High-Performance Least Busy Region Detection (Widget Placement)
int cmd_least_busy_region(int argc, char** argv) {
    std::string image_path = "";
    int region_width = 300;
    int region_height = 200;
    int screen_width = -1;
    int screen_height = -1;
    int stride = 2;
    std::string screen_mode = "fill";
    int horizontal_padding = 50;
    int vertical_padding = 50;
    bool busiest = false;

    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--width" && i + 1 < argc) {
            region_width = std::atoi(argv[++i]);
        } else if (arg == "--height" && i + 1 < argc) {
            region_height = std::atoi(argv[++i]);
        } else if (arg == "--screen-width" && i + 1 < argc) {
            screen_width = std::atoi(argv[++i]);
        } else if (arg == "--screen-height" && i + 1 < argc) {
            screen_height = std::atoi(argv[++i]);
        } else if (arg == "--stride" && i + 1 < argc) {
            stride = std::atoi(argv[++i]);
        } else if (arg == "--screen-mode" && i + 1 < argc) {
            screen_mode = argv[++i];
        } else if (arg == "--horizontal-padding" && i + 1 < argc) {
            horizontal_padding = std::atoi(argv[++i]);
        } else if (arg == "--vertical-padding" && i + 1 < argc) {
            vertical_padding = std::atoi(argv[++i]);
        } else if (arg == "--busiest") {
            busiest = true;
        } else if (arg[0] != '-' && image_path.empty()) {
            image_path = arg;
        }
    }

    if (image_path.empty()) {
        std::cerr << "Error: No image path specified.\n";
        return 1;
    }

    auto img = load_image(image_path);
    if (!img || !img->data || img->w <= 0 || img->h <= 0) {
        std::cerr << "Error: Could not load image " << image_path << "\n";
        return 1;
    }

    const int PROCESSING_MAX_DIM = 512;
    int orig_w = img->w;
    int orig_h = img->h;
    int target_w = (screen_width > 0) ? screen_width : orig_w;
    int target_h = (screen_height > 0) ? screen_height : orig_h;

    double scale_factor = 1.0;
    if (std::max(target_w, target_h) > PROCESSING_MAX_DIM) {
        scale_factor = static_cast<double>(PROCESSING_MAX_DIM) / std::max(target_w, target_h);
    }

    int proc_w = std::max(1, static_cast<int>(target_w * scale_factor));
    int proc_h = std::max(1, static_cast<int>(target_h * scale_factor));

    int proc_region_w = std::max(1, static_cast<int>(region_width * scale_factor));
    int proc_region_h = std::max(1, static_cast<int>(region_height * scale_factor));
    int proc_h_padding = static_cast<int>(horizontal_padding * scale_factor);
    int proc_v_padding = static_cast<int>(vertical_padding * scale_factor);
    int proc_stride = std::max(1, static_cast<int>(stride * scale_factor));

    // Scale and center crop to proc_w x proc_h
    double scale_w_img = static_cast<double>(proc_w) / orig_w;
    double scale_h_img = static_cast<double>(proc_h) / orig_h;
    double scale = (screen_mode == "fill") ? std::max(scale_w_img, scale_h_img) : std::min(scale_w_img, scale_h_img);

    int crop_orig_w = std::min(orig_w, std::max(1, static_cast<int>(std::round(proc_w / scale))));
    int crop_orig_h = std::min(orig_h, std::max(1, static_cast<int>(std::round(proc_h / scale))));
    int src_x = std::max(0, (orig_w - crop_orig_w) / 2);
    int src_y = std::max(0, (orig_h - crop_orig_h) / 2);

    std::vector<unsigned char> proc_data(proc_w * proc_h * 3);
    const unsigned char* in_sub = img->data + (src_y * orig_w + src_x) * 3;
    stbir_resize_uint8_linear(in_sub, crop_orig_w, crop_orig_h, orig_w * 3, proc_data.data(), proc_w, proc_h, 0, STBIR_RGB);

    // Padding checks
    if (proc_h_padding * 2 >= proc_w || proc_v_padding * 2 >= proc_h) {
        proc_h_padding = std::max(0, std::min(proc_h_padding, (proc_w - 1) / 2));
        proc_v_padding = std::max(0, std::min(proc_v_padding, (proc_h - 1) / 2));
    }
    int max_region_w = proc_w - 2 * proc_h_padding;
    int max_region_h = proc_h - 2 * proc_v_padding;
    if (max_region_w <= 0 || max_region_h <= 0) {
        std::cout << "{\"center_x\": 0, \"center_y\": 0, \"width\": " << region_width << ", \"height\": " << region_height << ", \"variance\": 0, \"dominant_color\": \"#000000\"}\n";
        return 0;
    }
    if (proc_region_w > max_region_w) proc_region_w = max_region_w;
    if (proc_region_h > max_region_h) proc_region_h = max_region_h;

    // Build Integral and Squared Integral Tables
    std::vector<double> integral((proc_w + 1) * (proc_h + 1), 0.0);
    std::vector<double> integral_sq((proc_w + 1) * (proc_h + 1), 0.0);

    for (int y = 0; y < proc_h; ++y) {
        double row_sum = 0.0;
        double row_sum_sq = 0.0;
        for (int x = 0; x < proc_w; ++x) {
            int idx = (y * proc_w + x) * 3;
            double r = static_cast<double>(proc_data[idx]);
            double g = static_cast<double>(proc_data[idx + 1]);
            double b = static_cast<double>(proc_data[idx + 2]);
            double gray = 0.299 * r + 0.587 * g + 0.114 * b;

            row_sum += gray;
            row_sum_sq += gray * gray;

            int curr_pos = (y + 1) * (proc_w + 1) + (x + 1);
            int prev_pos = y * (proc_w + 1) + (x + 1);

            integral[curr_pos] = integral[prev_pos] + row_sum;
            integral_sq[curr_pos] = integral_sq[prev_pos] + row_sum_sq;
        }
    }

    auto region_sum = [&](const std::vector<double>& ii, int x1, int y1, int x2, int y2) -> double {
        return ii[(y2 + 1) * (proc_w + 1) + (x2 + 1)]
             - ii[y1 * (proc_w + 1) + (x2 + 1)]
             - ii[(y2 + 1) * (proc_w + 1) + x1]
             + ii[y1 * (proc_w + 1) + x1];
    };

    double area = static_cast<double>(proc_region_w) * proc_region_h;
    double min_var = -1.0;
    double max_var = -1.0;
    int min_x = proc_h_padding, min_y = proc_v_padding;
    int max_x = proc_h_padding, max_y = proc_v_padding;

    int x_start = proc_h_padding;
    int y_start = proc_v_padding;
    int x_end = proc_w - proc_region_w - proc_h_padding;
    int y_end = proc_h - proc_region_h - proc_v_padding;
    if (x_end < x_start) x_end = x_start;
    if (y_end < y_start) y_end = y_start;

    for (int y = y_start; y <= y_end; y += proc_stride) {
        for (int x = x_start; x <= x_end; x += proc_stride) {
            int x1 = x, y1 = y;
            int x2 = x + proc_region_w - 1;
            int y2 = y + proc_region_h - 1;
            if (x2 >= proc_w || y2 >= proc_h) continue;

            double s = region_sum(integral, x1, y1, x2, y2);
            double s2 = region_sum(integral_sq, x1, y1, x2, y2);

            double mean = s / area;
            double var = (s2 / area) - (mean * mean);
            if (var < 0.0) var = 0.0;

            if (min_var < 0.0 || var < min_var) {
                min_var = var;
                min_x = x;
                min_y = y;
            }
            if (max_var < 0.0 || var > max_var) {
                max_var = var;
                max_x = x;
                max_y = y;
            }
        }
    }

    int res_x = busiest ? max_x : min_x;
    int res_y = busiest ? max_y : min_y;
    double res_var = busiest ? max_var : min_var;

    int final_x = static_cast<int>(res_x / scale_factor);
    int final_y = static_cast<int>(res_y / scale_factor);
    int center_x = final_x + region_width / 2;
    int center_y = final_y + region_height / 2;

    // Dominant color in selected region using K-means
    struct RGBPoint { double r, g, b; };
    std::vector<RGBPoint> pts;
    pts.reserve(proc_region_w * proc_region_h);

    for (int y = res_y; y < res_y + proc_region_h && y < proc_h; ++y) {
        for (int x = res_x; x < res_x + proc_region_w && x < proc_w; ++x) {
            int idx = (y * proc_w + x) * 3;
            double r = proc_data[idx];
            double g = proc_data[idx + 1];
            double b = proc_data[idx + 2];
            if (r > 10.0 || g > 10.0 || b > 10.0) {
                pts.push_back({r, g, b});
            }
        }
    }

    if (pts.empty()) {
        for (int y = res_y; y < res_y + proc_region_h && y < proc_h; ++y) {
            for (int x = res_x; x < res_x + proc_region_w && x < proc_w; ++x) {
                int idx = (y * proc_w + x) * 3;
                pts.push_back({static_cast<double>(proc_data[idx]), static_cast<double>(proc_data[idx + 1]), static_cast<double>(proc_data[idx + 2])});
            }
        }
    }

    int dom_r = 0, dom_g = 0, dom_b = 0;
    if (!pts.empty()) {
        int K = std::min(static_cast<int>(pts.size()), 3);
        std::vector<RGBPoint> centers(K);
        for (int k = 0; k < K; ++k) {
            centers[k] = pts[k * pts.size() / K];
        }
        std::vector<int> cluster_counts(K, 0);

        for (int iter = 0; iter < 10; ++iter) {
            std::vector<RGBPoint> new_centers(K, {0.0, 0.0, 0.0});
            std::vector<int> counts(K, 0);
            for (const auto& p : pts) {
                int best_k = 0;
                double best_dist = 1e18;
                for (int k = 0; k < K; ++k) {
                    double dr = p.r - centers[k].r;
                    double dg = p.g - centers[k].g;
                    double db = p.b - centers[k].b;
                    double d = dr * dr + dg * dg + db * db;
                    if (d < best_dist) {
                        best_dist = d;
                        best_k = k;
                    }
                }
                new_centers[best_k].r += p.r;
                new_centers[best_k].g += p.g;
                new_centers[best_k].b += p.b;
                counts[best_k]++;
            }
            for (int k = 0; k < K; ++k) {
                if (counts[k] > 0) {
                    centers[k].r = new_centers[k].r / counts[k];
                    centers[k].g = new_centers[k].g / counts[k];
                    centers[k].b = new_centers[k].b / counts[k];
                }
            }
            cluster_counts = counts;
        }

        int best_k = 0;
        int max_c = -1;
        for (int k = 0; k < K; ++k) {
            if (cluster_counts[k] > max_c) {
                max_c = cluster_counts[k];
                best_k = k;
            }
        }
        dom_r = std::clamp(static_cast<int>(std::round(centers[best_k].r)), 0, 255);
        dom_g = std::clamp(static_cast<int>(std::round(centers[best_k].g)), 0, 255);
        dom_b = std::clamp(static_cast<int>(std::round(centers[best_k].b)), 0, 255);
    }

    std::string dom_color_hex = to_hex(dom_r, dom_g, dom_b);

    std::cout << "{\"center_x\": " << center_x
              << ", \"center_y\": " << center_y
              << ", \"width\": " << region_width
              << ", \"height\": " << region_height
              << ", \"variance\": " << res_var
              << ", \"dominant_color\": \"" << dom_color_hex << "\"}\n";
    return 0;
}

// 8. Wait for File to be Ready and Non-Empty (eliminates shell retry loops)
int cmd_file_ready(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: material-color-helper file-ready <path> [timeout_ms=1500]\n";
        return 1;
    }
    std::string path = argv[2];
    int timeout_ms = (argc >= 4) ? std::atoi(argv[3]) : 1500;
    int elapsed = 0;
    const int step_ms = 30;

    while (elapsed <= timeout_ms) {
        std::error_code ec;
        if (fs::exists(path, ec) && fs::is_regular_file(path, ec)) {
            auto sz = fs::file_size(path, ec);
            if (!ec && sz > 0) {
                return 0; // Ready!
            }
        }
        if (elapsed + step_ms > timeout_ms) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(step_ms));
        elapsed += step_ms;
    }
    return 1; // Timeout / not ready
}

// 9. Download Cover Art with Atomic Cache Verification
int cmd_download_cover(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: material-color-helper download-cover <url> <dest_path>\n";
        return 1;
    }
    std::string url = argv[2];
    std::string dest_path = argv[3];

    std::error_code ec;
    if (fs::exists(dest_path, ec) && fs::is_regular_file(dest_path, ec)) {
        auto sz = fs::file_size(dest_path, ec);
        if (!ec && sz > 0) {
            return 0; // Already cached and non-empty!
        }
    }

    fs::path p(dest_path);
    if (p.has_parent_path()) {
        fs::create_directories(p.parent_path(), ec);
    }

    std::string tmp_path = dest_path + ".tmp." + std::to_string(getpid());
    std::string cmd = "curl -sSL -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0' '"
                    + url + "' -o '" + tmp_path + "' >/dev/null 2>&1";
    int ret = system(cmd.c_str());
    if (ret == 0 && fs::exists(tmp_path, ec)) {
        auto sz = fs::file_size(tmp_path, ec);
        if (!ec && sz > 0) {
            fs::rename(tmp_path, dest_path, ec);
            return 0;
        }
    }
    fs::remove(tmp_path, ec);
    return 1;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: material-color-helper <subcommand> [args...]\n"
                  << "Subcommands:\n"
                  << "  scheme <image_path>\n"
                  << "  thumbnail <image_path> <out_path> [max_dim] [quality]\n"
                  << "  crop-batch --directory <path> --resolution <WxH> [--machine_progress] [--extensions <pattern>]\n"
                  << "  thumbnail-batch --directory <path> [--size <normal|large|x-large|xx-large>] [--machine_progress]\n"
                  << "  least-busy-region <image_path> [--screen-width <W>] [--screen-height <H>] [--width <W>] [--height <H>] [--horizontal-padding <P>] [--vertical-padding <P>] [--busiest]\n"
                  << "  file-ready <path> [timeout_ms=1500]\n"
                  << "  download-cover <url> <dest_path>\n"
                  << "  template --scss <file.scss> --out-dir <out_dir> [--templates-dir <dir>] [--alpha 100]\n"
                  << "  text-color [image_path|-]\n";
        return 1;
    }

    std::string subcmd = argv[1];
    if (subcmd == "scheme") {
        return cmd_scheme(argc, argv);
    } else if (subcmd == "thumbnail") {
        return cmd_thumbnail(argc, argv);
    } else if (subcmd == "crop-batch") {
        return cmd_crop_batch(argc, argv);
    } else if (subcmd == "thumbnail-batch") {
        return cmd_thumbnail_batch(argc, argv);
    } else if (subcmd == "least-busy-region") {
        return cmd_least_busy_region(argc, argv);
    } else if (subcmd == "file-ready") {
        return cmd_file_ready(argc, argv);
    } else if (subcmd == "download-cover") {
        return cmd_download_cover(argc, argv);
    } else if (subcmd == "template") {
        return cmd_template(argc, argv);
    } else if (subcmd == "text-color") {
        return cmd_text_color(argc, argv);
    } else {
        std::cerr << "Unknown subcommand: " << subcmd << "\n";
        return 1;
    }
}
