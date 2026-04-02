#pragma once
// profile.h — Per-game / per-app performance profiles.
// A profile is a named overlay on top of the base Config that overrides
// specific fields (memory, GPU backend, keymapper file, etc.) for a
// specific Android package.
//
// Profiles are stored as JSON files in ~/.config/avm/profiles/<name>.json
// (Linux/macOS) or %APPDATA%\AVM\profiles\<name>.json (Windows).

#include "config.h"
#include "android_version.h"
#include <string>
#include <vector>
#include <optional>

namespace avm {

struct Profile {
    std::string     name;               // e.g. "genshin", "mlbb", "default"
    std::string     package_name;       // e.g. "com.miHoYo.GenshinImpact"
    std::string     display_name;       // friendly name shown in UI
    std::string     icon_path;          // optional .png path
    std::string     keymapper_profile;  // path to .json keymapper

    // Version override — use Auto to inherit from CLI
    AndroidVersion  android_version = AndroidVersion::Auto;

    // Resource overrides (-1 = use Config default)
    int             memory_mb    = -1;
    int             vcpu_cores   = -1;
    int             target_fps   = -1;
    bool            vsync_override = true;
    bool            fps_unlock   = false;

    // GPU
    std::optional<GpuBackend> gpu_backend;

    // Performance hints passed to QEMU via -cpu flags
    std::vector<std::string> extra_qemu_args;
};

// Apply a profile on top of a base Config.
// Only non-default (-1 / empty / Auto) profile fields overwrite config.
void apply_profile(Config& config, const Profile& profile);

// Load profile from a JSON file. Returns false if file not found / invalid.
bool load_profile(const std::string& path, Profile& out);

// Save profile to a JSON file.
bool save_profile(const std::string& path, const Profile& profile);

// Return the platform profiles directory.
// Linux/macOS: ~/.config/avm/profiles
// Windows:     %APPDATA%\AVM\profiles
std::string profiles_dir();

// List all .json files in profiles_dir().
std::vector<std::string> list_profiles();

} // namespace avm
