#pragma once
// android_version.h — Android release metadata used by the version selector.
// Each entry maps a human-friendly API level to the kernel/image requirements
// so VmManager can validate the image and set correct QEMU args.

#include <string>
#include <vector>
#include <cstdint>

namespace avm {

// -----------------------------------------------------------------------
// Supported Android versions
// Add new entries here as AOSP releases new versions.
// -----------------------------------------------------------------------
enum class AndroidVersion : uint8_t {
    Android10  = 29,  // Q
    Android11  = 30,  // R
    Android12  = 31,  // S
    Android12L = 32,  // Sv2
    Android13  = 33,  // T  (Tiramisu)
    Android14  = 34,  // U  (Upside-Down Cake)
    Android15  = 35,  // V  (Vanilla Ice Cream)
    Auto       = 0,   // detect from image at runtime
};

struct AndroidVersionInfo {
    AndroidVersion  version;
    uint8_t         api_level;
    std::string     code_name;     // e.g. "Tiramisu"
    std::string     release_name;  // e.g. "Android 13"
    std::string     min_kernel;    // minimum Linux kernel version string
    bool            requires_arm64;// true on Apple Silicon builds
    int             recommended_ram_mb;
    int             recommended_vcpus;
};

// Returns the full metadata table for all supported versions.
const std::vector<AndroidVersionInfo>& android_version_table();

// Look up by enum value.
const AndroidVersionInfo* find_version_info(AndroidVersion v);

// Parse a user-supplied string like "13", "android13", "API33", "tiramisu".
// Returns AndroidVersion::Auto on parse failure.
AndroidVersion parse_android_version(const std::string& s);

// Human-readable string: "Android 13 (Tiramisu, API 33)"
std::string android_version_string(AndroidVersion v);

// Print the version selector table to stdout.
void print_version_table();

} // namespace avm
