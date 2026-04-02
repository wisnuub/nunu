#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <unordered_map>
#include <optional>

namespace avm::input {

// Describes where on the virtual screen a mapped key produces a tap.
struct TapTarget {
    float x, y;          // normalized [0..1]
    float radius = 0.04f; // touch radius, fraction of screen width
};

// A mapping from a host SDL scancode → a virtual screen tap.
struct KeyMapping {
    int32_t    sdl_scancode;   // SDL_Scancode value
    std::string label;         // display name, e.g. "W" or "Space"
    TapTarget  target;
};

// KeymapProfile — a named set of mappings for a specific game/app.
struct KeymapProfile {
    std::string name;          // e.g. "PUBG Mobile Default"
    std::string package_name;  // Android package to auto-activate for
    std::unordered_map<int32_t, KeyMapping> mappings; // keyed by SDL_Scancode
};

// Keymapper — manages loading, saving, and querying keymaps.
class Keymapper {
public:
    explicit Keymapper(const std::string& profile_dir);

    // Load all .json profiles from profile_dir.
    void load_profiles();

    // Save a profile to profile_dir/<profile.name>.json.
    void save_profile(const KeymapProfile& profile);

    // Activate profile for the given package (nullptr = deactivate all).
    void activate_for_package(const std::string& package_name);

    // Look up a tap target for a pressed SDL scancode in the active profile.
    std::optional<TapTarget> lookup(int32_t sdl_scancode) const;

    // Returns all loaded profiles (for the UI editor).
    const std::vector<KeymapProfile>& profiles() const { return profiles_; }
    const KeymapProfile* active_profile() const        { return active_; }

private:
    std::string               profile_dir_;
    std::vector<KeymapProfile> profiles_;
    const KeymapProfile*      active_ = nullptr;
};

} // namespace avm::input
