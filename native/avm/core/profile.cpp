#include "avm/core/profile.h"
#include "avm/core/platform.h"
#include <iostream>
#include <fstream>
#include <sstream>

// Minimal JSON helpers — no external dependency.
// We only need to read/write flat key:value pairs.
// For a real implementation, swap in nlohmann/json or RapidJSON.

namespace avm {

// -----------------------------------------------------------------------
// Profile directory
// -----------------------------------------------------------------------
std::string profiles_dir() {
#if AVM_OS_WINDOWS
    const char* appdata = getenv("APPDATA");
    std::string base = appdata ? appdata : "C:\\Users\\Default\\AppData\\Roaming";
    return base + "\\AVM\\profiles";
#elif AVM_OS_MACOS
    const char* home = getenv("HOME");
    std::string base = home ? home : "/tmp";
    return base + "/Library/Application Support/AVM/profiles";
#else
    const char* xdg = getenv("XDG_CONFIG_HOME");
    if (xdg && xdg[0]) return std::string(xdg) + "/avm/profiles";
    const char* home = getenv("HOME");
    std::string base = home ? home : "/tmp";
    return base + "/.config/avm/profiles";
#endif
}

// -----------------------------------------------------------------------
// apply_profile
// -----------------------------------------------------------------------
void apply_profile(Config& config, const Profile& profile) {
    if (!profile.keymapper_profile.empty())
        config.keymapper_profile = profile.keymapper_profile;
    if (profile.memory_mb > 0)
        config.memory_mb = profile.memory_mb;
    if (profile.vcpu_cores > 0)
        config.vcpu_cores = profile.vcpu_cores;
    if (profile.target_fps > 0)
        config.target_fps = profile.target_fps;
    if (profile.android_version != AndroidVersion::Auto)
        config.android_version = profile.android_version;
    if (profile.gpu_backend.has_value())
        config.gpu_backend = profile.gpu_backend.value();
    config.vsync_override = profile.vsync_override;
    std::cout << "[Profile] Applied profile '" << profile.name << "'\n";
}

// -----------------------------------------------------------------------
// Minimal JSON read/write (flat key:value only)
// -----------------------------------------------------------------------
static std::string json_escape(const std::string& s) {
    std::string out;
    for (char c : s) {
        if (c == '"')  out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else out += c;
    }
    return out;
}

bool save_profile(const std::string& path, const Profile& p) {
    std::ofstream f(path);
    if (!f.is_open()) { std::cerr << "[Profile] Cannot write: " << path << "\n"; return false; }
    f << "{\n";
    f << "  \"name\": \""          << json_escape(p.name)           << "\",\n";
    f << "  \"package_name\": \"" << json_escape(p.package_name)  << "\",\n";
    f << "  \"display_name\": \"" << json_escape(p.display_name)  << "\",\n";
    f << "  \"keymapper\": \""    << json_escape(p.keymapper_profile) << "\",\n";
    f << "  \"android_version\": " << (int)p.android_version       << ",\n";
    f << "  \"memory_mb\": "       << p.memory_mb                   << ",\n";
    f << "  \"vcpu_cores\": "      << p.vcpu_cores                  << ",\n";
    f << "  \"target_fps\": "      << p.target_fps                  << ",\n";
    f << "  \"fps_unlock\": "      << (p.fps_unlock ? "true" : "false") << "\n";
    f << "}\n";
    std::cout << "[Profile] Saved: " << path << "\n";
    return true;
}

bool load_profile(const std::string& path, Profile& p) {
    std::ifstream f(path);
    if (!f.is_open()) { std::cerr << "[Profile] Not found: " << path << "\n"; return false; }

    auto strip = [](std::string s) {
        // Remove surrounding quotes and whitespace
        s.erase(0, s.find_first_not_of(" \t\r\n"));
        s.erase(s.find_last_not_of(" \t\r\n,") + 1);
        if (s.size() >= 2 && s.front() == '"' && s.back() == '"')
            s = s.substr(1, s.size() - 2);
        return s;
    };

    std::string line;
    while (std::getline(f, line)) {
        auto colon = line.find(':');
        if (colon == std::string::npos) continue;
        std::string key = strip(line.substr(0, colon));
        std::string val = strip(line.substr(colon + 1));
        if (key == "name")             p.name             = val;
        else if (key == "package_name") p.package_name     = val;
        else if (key == "display_name") p.display_name     = val;
        else if (key == "keymapper")    p.keymapper_profile = val;
        else if (key == "android_version") {
            try { p.android_version = (AndroidVersion)std::stoi(val); } catch (...) {}
        }
        else if (key == "memory_mb")   { try { p.memory_mb  = std::stoi(val); } catch (...) {} }
        else if (key == "vcpu_cores")  { try { p.vcpu_cores = std::stoi(val); } catch (...) {} }
        else if (key == "target_fps")  { try { p.target_fps = std::stoi(val); } catch (...) {} }
        else if (key == "fps_unlock")  p.fps_unlock = (val == "true");
    }
    std::cout << "[Profile] Loaded: " << p.name << " (" << path << ")\n";
    return true;
}

std::vector<std::string> list_profiles() {
    std::vector<std::string> results;
    // Cross-platform directory listing without boost/std::filesystem
    // (C++17 std::filesystem should be available given our CMake minimum)
#if defined(__cpp_lib_filesystem) || defined(__cpp_lib_experimental_filesystem)
#  include <filesystem>
    namespace fs = std::filesystem;
    std::string dir = profiles_dir();
    std::error_code ec;
    for (auto& entry : fs::directory_iterator(dir, ec)) {
        if (entry.path().extension() == ".json")
            results.push_back(entry.path().string());
    }
#endif
    return results;
}

} // namespace avm
