#include "avm/core/android_version.h"
#include <algorithm>
#include <cctype>
#include <iostream>
#include <iomanip>
#include <sstream>

namespace avm {

// -----------------------------------------------------------------------
// Version metadata table
// -----------------------------------------------------------------------
static const std::vector<AndroidVersionInfo> kVersionTable = {
    {
        AndroidVersion::Android10, 29, "Q", "Android 10",
        "4.14", false, 2048, 2
    },
    {
        AndroidVersion::Android11, 30, "R", "Android 11",
        "4.19", false, 3072, 2
    },
    {
        AndroidVersion::Android12, 31, "S", "Android 12",
        "5.4", false, 4096, 4
    },
    {
        AndroidVersion::Android12L, 32, "Sv2", "Android 12L",
        "5.10", false, 4096, 4
    },
    {
        AndroidVersion::Android13, 33, "Tiramisu", "Android 13",
        "5.15", false, 4096, 4
    },
    {
        AndroidVersion::Android14, 34, "Upside Down Cake", "Android 14",
        "6.1",  false, 6144, 4
    },
    {
        AndroidVersion::Android15, 35, "Vanilla Ice Cream", "Android 15",
        "6.6",  false, 6144, 6
    },
};

const std::vector<AndroidVersionInfo>& android_version_table() {
    return kVersionTable;
}

const AndroidVersionInfo* find_version_info(AndroidVersion v) {
    if (v == AndroidVersion::Auto) return nullptr;
    for (auto& info : kVersionTable) {
        if (info.version == v) return &info;
    }
    return nullptr;
}

// -----------------------------------------------------------------------
// Parser: accepts "10","11",..."15", "android14", "API34", "tiramisu", etc.
// -----------------------------------------------------------------------
AndroidVersion parse_android_version(const std::string& raw) {
    if (raw.empty()) return AndroidVersion::Auto;

    // Lowercase copy for case-insensitive matching
    std::string s = raw;
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    // Strip common prefixes: "android", "api"
    for (auto prefix : {"android", "api"}) {
        if (s.rfind(prefix, 0) == 0)
            s = s.substr(std::string(prefix).size());
    }
    // Trim leading whitespace/hyphens that might remain
    s.erase(0, s.find_first_not_of(" -"));

    // Try matching numeric API level or version number
    // e.g. "33", "13" → try both
    auto try_number = [](const std::string& t, AndroidVersion& out) -> bool {
        try {
            int n = std::stoi(t);
            // Accept both API level (29-35) and version number (10-15)
            for (auto& info : kVersionTable) {
                if ((int)info.api_level == n ||
                    (n >= 10 && n <= 15 && (int)info.api_level == (n + 19))) {
                    // n+19: Android 10 = API 29, 11=30, 12=31, 13=33, 14=34, 15=35
                    // (12L is a special case — handle separately)
                    out = info.version;
                    return true;
                }
            }
            // Direct API level match
            for (auto& info : kVersionTable) {
                if ((int)info.api_level == n) { out = info.version; return true; }
            }
        } catch (...) {}
        return false;
    };

    AndroidVersion result = AndroidVersion::Auto;
    if (try_number(s, result)) return result;

    // Match "12l", "12.1", "sv2"
    if (s == "12l" || s == "12.1" || s == "sv2")
        return AndroidVersion::Android12L;

    // Code name matching
    for (auto& info : kVersionTable) {
        std::string cn = info.code_name;
        std::transform(cn.begin(), cn.end(), cn.begin(),
                       [](unsigned char c){ return std::tolower(c); });
        // Remove spaces for "upsidedowncake" → "upside down cake"
        std::string cn_nospace = cn;
        cn_nospace.erase(std::remove(cn_nospace.begin(), cn_nospace.end(), ' '),
                         cn_nospace.end());
        if (s == cn || s == cn_nospace) return info.version;
    }

    return AndroidVersion::Auto; // not recognised
}

std::string android_version_string(AndroidVersion v) {
    if (v == AndroidVersion::Auto) return "Auto (detect from image)";
    auto* info = find_version_info(v);
    if (!info) return "Unknown";
    std::ostringstream oss;
    oss << info->release_name
        << " (" << info->code_name
        << ", API " << (int)info->api_level << ")";
    return oss.str();
}

void print_version_table() {
    std::cout << "\n";
    std::cout << "  Supported Android Versions\n";
    std::cout << "  "
              << std::string(60, '-') << "\n";
    std::cout << "  "
              << std::left
              << std::setw(14) << "Version"
              << std::setw(22) << "Code Name"
              << std::setw(8)  << "API"
              << std::setw(10) << "Min RAM"
              << "Min Kernel"
              << "\n";
    std::cout << "  " << std::string(60, '-') << "\n";
    for (auto& info : kVersionTable) {
        std::cout << "  "
                  << std::left
                  << std::setw(14) << info.release_name
                  << std::setw(22) << info.code_name
                  << std::setw(8)  << (int)info.api_level
                  << std::setw(10) << (std::to_string(info.recommended_ram_mb) + " MB")
                  << info.min_kernel
                  << "\n";
    }
    std::cout << "\n";
    std::cout << "  Usage: avm --android 13 --image android13.img\n";
    std::cout << "         avm --android tiramisu --image android13.img\n";
    std::cout << "         avm --android API33 --image android13.img\n";
    std::cout << "\n";
}

} // namespace avm
