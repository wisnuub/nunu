#include "avm/core/gapps.h"
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace avm {

// ---------------------------------------------------------------------------
// Built-in certified device fingerprints
//
// Strategy per profile type:
//
//  SAFETY-NET / PLAY INTEGRITY  →  Use Google Pixel (pixel8pro default)
//      Google's own devices have the best CTS pass rate and are on every
//      game's allowlist. Safest for Play Store / banking apps.
//
//  HIGH-FPS UNLOCK (120/144/165 Hz)  →  Use ROG Phone (rog9pro)
//      ROG Phone 9 Pro is explicitly whitelisted for 120/144 fps in PUBG
//      Mobile, Genshin Impact, Mobile Legends, CoD Mobile, and most major
//      titles. ASUS gaming phones hold the most game-specific high-fps
//      entries in game server-side configs.
//
//  SAMSUNG HIGH-FPS  →  Use Galaxy S25 Ultra (s25ultra)
//      Samsung S-series flagships unlock 90/120 fps in most titles.
//      Samsung Game Booster hints (ro.samsung.freecess.*) are included
//      to trigger Samsung-specific game optimisation paths.
//
// Source: public build fingerprints, XDA community verified CTS device list,
//         PUBG Mobile 120fps device list (sportsdunia.com/gaming),
//         ASUS OTA manifest (ota.asus.com/fw/ASUS_AI2501)
// ---------------------------------------------------------------------------

static const DeviceFingerprint BUILTIN_PROFILES[] = {
    // [0] Pixel 8 Pro  —  best SafetyNet / Play Integrity pass rate
    {
        .brand           = "google",
        .device          = "husky",
        .manufacturer    = "Google",
        .model           = "Pixel 8 Pro",
        .name            = "husky",
        .fingerprint     = "google/husky/husky:14/AD1A.240905.004/12117344:user/release-keys",
        .description     = "husky-user 14 AD1A.240905.004 12117344 release-keys",
        .version_release = "14",
        .version_sdk     = 34,
    },
    // [1] Pixel 7 Pro
    {
        .brand           = "google",
        .device          = "cheetah",
        .manufacturer    = "Google",
        .model           = "Pixel 7 Pro",
        .name            = "cheetah",
        .fingerprint     = "google/cheetah/cheetah:14/AP1A.240905.005/12117347:user/release-keys",
        .description     = "cheetah-user 14 AP1A.240905.005 12117347 release-keys",
        .version_release = "14",
        .version_sdk     = 34,
    },
    // [2] Pixel Fold
    {
        .brand           = "google",
        .device          = "felix",
        .manufacturer    = "Google",
        .model           = "Pixel Fold",
        .name            = "felix",
        .fingerprint     = "google/felix/felix:14/AD1A.240905.004/12117344:user/release-keys",
        .description     = "felix-user 14 AD1A.240905.004 12117344 release-keys",
        .version_release = "14",
        .version_sdk     = 34,
    },
    // [3] ASUS ROG Phone 9 Pro  —  BEST for high-FPS unlock (120/144 Hz)
    //     Codename: ASUS_AI2501  (ROG Phone 9 / 9 Pro share AI2501 family)
    //     Whitelisted in PUBG Mobile, Genshin, CoD Mobile, MLBB, Honkai SR
    //     for 120fps+ at Ultra/HDR settings.
    //     Snapdragon 8 Elite, Android 15, X-Mode gaming hints included.
    {
        .brand           = "asus",
        .device          = "ASUS_AI2501",
        .manufacturer    = "asus",
        .model           = "ASUS_AI2501",
        .name            = "WW_AI2501",
        .fingerprint     = "asus/WW_AI2501/ASUS_AI2501:15/AP3A.240905.015.A2/24.0825.2060.99:user/release-keys",
        .description     = "WW_AI2501-user 15 AP3A.240905.015.A2 24.0825.2060.99 release-keys",
        .version_release = "15",
        .version_sdk     = 35,
    },
    // [4] ASUS ROG Phone 8 Pro  —  fallback, Android 14, wider game compat
    //     Codename: ASUS_AI2401
    {
        .brand           = "asus",
        .device          = "ASUS_AI2401",
        .manufacturer    = "asus",
        .model           = "ASUS_AI2401",
        .name            = "WW_AI2401",
        .fingerprint     = "asus/WW_AI2401/ASUS_AI2401:14/AP1A.240905.005/24.0410.2060.81:user/release-keys",
        .description     = "WW_AI2401-user 14 AP1A.240905.005 24.0410.2060.81 release-keys",
        .version_release = "14",
        .version_sdk     = 34,
    },
    // [5] Samsung Galaxy S25 Ultra  —  best Samsung 120fps unlock
    //     Model: SM-S938B (international/global variant)
    //     Snapdragon 8 Elite, Android 15, One UI 7
    //     Game Booster hints included for Samsung-specific 120fps paths
    {
        .brand           = "samsung",
        .device          = "dm3q",
        .manufacturer    = "samsung",
        .model           = "SM-S938B",
        .name            = "dm3qxxx",
        .fingerprint     = "samsung/dm3qxxx/dm3q:15/AP3A.240905.015.A2/S938BXXU3AXKB:user/release-keys",
        .description     = "dm3qxxx-user 15 AP3A.240905.015.A2 S938BXXU3AXKB release-keys",
        .version_release = "15",
        .version_sdk     = 35,
    },
    // [6] Samsung Galaxy S24 Ultra  —  Android 14, very wide 120fps whitelist
    //     Model: SM-S928B
    {
        .brand           = "samsung",
        .device          = "e3q",
        .manufacturer    = "samsung",
        .model           = "SM-S928B",
        .name            = "e3qxxx",
        .fingerprint     = "samsung/e3qxxx/e3q:14/UP1A.231005.007/S928BXXU3AXKB:user/release-keys",
        .description     = "e3qxxx-user 14 UP1A.231005.007 S928BXXU3AXKB release-keys",
        .version_release = "14",
        .version_sdk     = 34,
    },
    // [7] Pixel 9 Pro  —  Android 15, newest Google flagship
    {
        .brand           = "google",
        .device          = "caiman",
        .manufacturer    = "Google",
        .model           = "Pixel 9 Pro",
        .name            = "caiman",
        .fingerprint     = "google/caiman/caiman:15/AP3A.240905.015/12117344:user/release-keys",
        .description     = "caiman-user 15 AP3A.240905.015 12117344 release-keys",
        .version_release = "15",
        .version_sdk     = 35,
    },
};

// ---------------------------------------------------------------------------
// Extra QEMU -prop entries per profile for game-specific FPS unlock hints.
// Games like PUBG Mobile, Genshin Impact, CoD Mobile check these props
// (in addition to model/fingerprint) to decide which FPS tier to allow.
// ---------------------------------------------------------------------------
struct ExtraProps {
    const char* profile;
    std::vector<std::pair<std::string,std::string>> props;
};

static const ExtraProps EXTRA_PROPS[] = {
    // ROG Phone 9 Pro extras  —  X-Mode + ASUS gaming hints
    { "rog9pro", {
        {"ro.vendor.asus.gaming_mode",        "1"},
        {"ro.asus.gamekey.support",            "1"},
        {"vendor.perf.fps_switch",             "1"},
        {"ro.vendor.perf.interaction.boost",   "1"},
        // PUBG Mobile 120fps allowlist check: must be in this list
        {"ro.product.system.model",            "ASUS_AI2501"},
        {"ro.product.vendor.model",            "ASUS_AI2501"},
    }},
    // ROG Phone 8 Pro extras
    { "rog8pro", {
        {"ro.vendor.asus.gaming_mode",         "1"},
        {"ro.asus.gamekey.support",            "1"},
        {"ro.product.system.model",            "ASUS_AI2401"},
        {"ro.product.vendor.model",            "ASUS_AI2401"},
    }},
    // Samsung S25 Ultra extras  —  Game Booster + One UI hints
    { "s25ultra", {
        {"ro.vendor.samsung.freecess.enable",  "1"},
        {"ro.config.low_ram",                  "false"},
        {"ro.product.system.model",            "SM-S938B"},
        {"ro.product.vendor.model",            "SM-S938B"},
        // Game optimiser mode flag
        {"debug.sf.hw",                        "1"},
    }},
    // Samsung S24 Ultra extras
    { "s24ultra", {
        {"ro.vendor.samsung.freecess.enable",  "1"},
        {"ro.config.low_ram",                  "false"},
        {"ro.product.system.model",            "SM-S928B"},
        {"ro.product.vendor.model",            "SM-S928B"},
        {"debug.sf.hw",                        "1"},
    }},
};

// ---------------------------------------------------------------------------

DeviceFingerprint get_builtin_fingerprint(const std::string& profile) {
    if (profile == "pixel8pro"   || profile == "husky")     return BUILTIN_PROFILES[0];
    if (profile == "pixel7pro"   || profile == "cheetah")   return BUILTIN_PROFILES[1];
    if (profile == "pixelfold"   || profile == "felix")     return BUILTIN_PROFILES[2];
    if (profile == "rog9pro"     || profile == "AI2501")    return BUILTIN_PROFILES[3];
    if (profile == "rog8pro"     || profile == "AI2401")    return BUILTIN_PROFILES[4];
    if (profile == "s25ultra"    || profile == "SM-S938B")  return BUILTIN_PROFILES[5];
    if (profile == "s24ultra"    || profile == "SM-S928B")  return BUILTIN_PROFILES[6];
    if (profile == "pixel9pro"   || profile == "caiman")    return BUILTIN_PROFILES[7];
    // Legacy aliases
    if (profile == "pixel7")                                return BUILTIN_PROFILES[1];
    throw std::invalid_argument(
        "Unknown spoof profile: '" + profile + "'.\n"
        "Available: pixel8pro, pixel9pro, pixel7pro, pixelfold, "
        "rog9pro, rog8pro, s25ultra, s24ultra"
    );
}

DeviceFingerprint load_fingerprint_file(const std::filesystem::path& path) {
    std::ifstream f(path);
    if (!f.is_open()) {
        throw std::runtime_error("Cannot open fingerprint file: " + path.string());
    }

    DeviceFingerprint fp;
    std::string line;
    auto extract = [](const std::string& l, const std::string& key) -> std::string {
        auto pos = l.find('"' + key + '"');
        if (pos == std::string::npos) return {};
        auto colon = l.find(':', pos);
        if (colon == std::string::npos) return {};
        auto q1 = l.find('"', colon + 1);
        if (q1 == std::string::npos) return {};
        auto q2 = l.find('"', q1 + 1);
        if (q2 == std::string::npos) return {};
        return l.substr(q1 + 1, q2 - q1 - 1);
    };

    while (std::getline(f, line)) {
        if (auto v = extract(line, "brand");           !v.empty()) fp.brand = v;
        if (auto v = extract(line, "device");          !v.empty()) fp.device = v;
        if (auto v = extract(line, "manufacturer");    !v.empty()) fp.manufacturer = v;
        if (auto v = extract(line, "model");           !v.empty()) fp.model = v;
        if (auto v = extract(line, "name");            !v.empty()) fp.name = v;
        if (auto v = extract(line, "fingerprint");     !v.empty()) fp.fingerprint = v;
        if (auto v = extract(line, "description");     !v.empty()) fp.description = v;
        if (auto v = extract(line, "version_release"); !v.empty()) fp.version_release = v;
        auto sdk_pos = line.find("\"version_sdk\"");
        if (sdk_pos != std::string::npos) {
            auto colon = line.find(':', sdk_pos);
            if (colon != std::string::npos) {
                try { fp.version_sdk = std::stoi(line.substr(colon + 1)); } catch (...) {}
            }
        }
    }
    return fp;
}

void build_gapps_qemu_props(
    const DeviceFingerprint& fp,
    std::vector<std::pair<std::string, std::string>>& out
) {
    out.emplace_back("ro.product.brand",        fp.brand);
    out.emplace_back("ro.product.device",       fp.device);
    out.emplace_back("ro.product.manufacturer", fp.manufacturer);
    out.emplace_back("ro.product.model",        fp.model);
    out.emplace_back("ro.product.name",         fp.name);
    out.emplace_back("ro.build.fingerprint",    fp.fingerprint);
    out.emplace_back("ro.build.description",    fp.description);
    out.emplace_back("ro.build.version.release",fp.version_release);
    out.emplace_back("ro.build.version.sdk",    std::to_string(fp.version_sdk));
    out.emplace_back("ro.build.tags",           "release-keys");
    out.emplace_back("ro.build.type",           "user");
    out.emplace_back("ro.debuggable",           "0");
    out.emplace_back("ro.secure",               "1");
    out.emplace_back("ro.adb.secure",           "1");
    out.emplace_back("ro.build.keys",           "release-keys");
    // Also set system/vendor product props for games that cross-check them
    out.emplace_back("ro.product.system.brand",        fp.brand);
    out.emplace_back("ro.product.system.device",       fp.device);
    out.emplace_back("ro.product.system.manufacturer", fp.manufacturer);
    out.emplace_back("ro.product.system.name",         fp.name);
    out.emplace_back("ro.product.vendor.brand",        fp.brand);
    out.emplace_back("ro.product.vendor.device",       fp.device);
    out.emplace_back("ro.product.vendor.manufacturer", fp.manufacturer);
    out.emplace_back("ro.product.vendor.name",         fp.name);
}

void build_highfps_qemu_props(
    const std::string& profile,
    std::vector<std::pair<std::string, std::string>>& out
) {
    for (const auto& ep : EXTRA_PROPS) {
        if (ep.profile == profile) {
            for (const auto& kv : ep.props) {
                out.push_back(kv);
            }
            return;
        }
    }
}

bool verify_gapps_image(const std::filesystem::path& image_path) {
    std::error_code ec;
    auto sz = std::filesystem::file_size(image_path, ec);
    if (ec) return false;
    constexpr uintmax_t GAPPS_SIZE_THRESHOLD = 2'800'000'000ULL;
    return sz >= GAPPS_SIZE_THRESHOLD;
}

} // namespace avm
