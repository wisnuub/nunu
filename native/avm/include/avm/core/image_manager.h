#pragma once
// image_manager.h — resolves, validates and optionally downloads AOSP
// system images for a requested AndroidVersion.
//
// The design separates image concerns from VmManager so the latter
// just receives a validated Config with system_image_path already set.

#include "android_version.h"
#include "config.h"
#include <string>
#include <functional>

namespace avm {

struct ImageInfo {
    std::string       path;          // absolute path to the .img file
    AndroidVersion    version;       // detected or user-supplied version
    uint8_t           api_level = 0;
    std::string       arch;          // "x86_64" or "arm64"
    uint64_t          size_bytes = 0;
    bool              is_writable = false;
};

class ImageManager {
public:
    // Validate an existing image file and detect its Android version.
    // Returns false if the file is missing, unreadable, or obviously wrong.
    static bool validate(const std::string& path, ImageInfo& out_info);

    // Apply recommended defaults from the version metadata to a Config.
    // Only overrides memory/vCPUs if the config has the default values,
    // so explicit user flags are always respected.
    static void apply_version_defaults(Config& config,
                                       const AndroidVersionInfo& info);

    // Print a summary of a validated image.
    static void print_image_info(const ImageInfo& info);

    // Warn if the image arch mismatches the host (e.g. x86 image on M1).
    // Returns false if the mismatch is fatal (no TCG flag set).
    static bool check_arch_compat(const ImageInfo& info,
                                  const Config& config,
                                  bool allow_tcg_fallback);
};

} // namespace avm
