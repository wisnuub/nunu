#pragma once
#include <filesystem>
#include <string>
#include <vector>

namespace avm {

/**
 * GAppsConfig — runtime configuration for Google Play services support.
 */
struct GAppsConfig {
    bool gapps_enabled = false;

    std::filesystem::path fingerprint_file;

    bool spoof_fingerprint = true;

    // Which device profile to spoof.
    //
    // Safety-first (Play Integrity / banking apps):
    //   pixel8pro   — Google Pixel 8 Pro    (default)
    //   pixel9pro   — Google Pixel 9 Pro
    //   pixel7pro   — Google Pixel 7 Pro
    //   pixelfold   — Google Pixel Fold
    //
    // High-FPS gaming (120/144 Hz unlock in PUBG, Genshin, CoD, MLBB):
    //   rog9pro     — ASUS ROG Phone 9 Pro  ← RECOMMENDED for gaming
    //   rog8pro     — ASUS ROG Phone 8 Pro  (wider Android 14 compat)
    //   s25ultra    — Samsung Galaxy S25 Ultra
    //   s24ultra    — Samsung Galaxy S24 Ultra
    std::string spoof_profile = "pixel8pro";

    int extra_ram_mb = 512;
};

/**
 * Fingerprint entry for a specific certified device profile.
 */
struct DeviceFingerprint {
    std::string brand;
    std::string device;
    std::string manufacturer;
    std::string model;
    std::string name;
    std::string fingerprint;
    std::string description;
    std::string version_release;
    int         version_sdk = 34;
};

/**
 * Returns the built-in spoofing fingerprint for the given profile name.
 *
 * Profile names:
 *   pixel8pro, pixel9pro, pixel7pro, pixelfold   — Google Pixel series
 *   rog9pro, rog8pro                             — ASUS ROG Phone series
 *   s25ultra, s24ultra                           — Samsung Galaxy S-Ultra series
 *
 * Throws std::invalid_argument if profile is unknown.
 */
DeviceFingerprint get_builtin_fingerprint(const std::string& profile);

/**
 * Loads a fingerprint from a JSON file.
 */
DeviceFingerprint load_fingerprint_file(const std::filesystem::path& path);

/**
 * Builds QEMU -prop entries for device identity spoofing.
 * Includes both ro.product.* and ro.product.system.*/ro.product.vendor.*
 * partitions, which games cross-check against the base model.
 */
void build_gapps_qemu_props(
    const DeviceFingerprint& fp,
    std::vector<std::pair<std::string, std::string>>& out
);

/**
 * Appends additional QEMU -prop entries that unlock high-FPS modes
 * in specific games for supported device profiles (rog9pro, s25ultra, etc.).
 *
 * Call AFTER build_gapps_qemu_props() to layer on top of the base identity.
 *
 * @param profile  Profile name (e.g. "rog9pro", "s25ultra")
 * @param out      Vector to append props to
 */
void build_highfps_qemu_props(
    const std::string& profile,
    std::vector<std::pair<std::string, std::string>>& out
);

/**
 * Verifies the image contains GApps (size heuristic).
 */
bool verify_gapps_image(const std::filesystem::path& image_path);

} // namespace avm
