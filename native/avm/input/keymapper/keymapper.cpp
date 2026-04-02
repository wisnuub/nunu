#include "avm/input/keymapper.h"
#include <fstream>
#include <filesystem>
#include <sstream>
#include <algorithm>

// Minimal JSON serialization without a heavy dependency.
// For production, swap with nlohmann/json or rapidjson.
namespace avm::input {

namespace fs = std::filesystem;

// ── Serialization helpers (hand-rolled, dependency-free) ─────────────────────

static std::string serialize_profile(const KeymapProfile& p) {
    std::ostringstream o;
    o << "{\n";
    o << "  \"name\": \"" << p.name << "\",\n";
    o << "  \"package\": \"" << p.package_name << "\",\n";
    o << "  \"mappings\": [\n";
    bool first = true;
    for (auto& [sc, m] : p.mappings) {
        if (!first) o << ",\n";
        first = false;
        o << "    {";
        o << "\"sc\": " << sc << ", ";
        o << "\"label\": \"" << m.label << "\", ";
        o << "\"x\": " << m.target.x << ", ";
        o << "\"y\": " << m.target.y << ", ";
        o << "\"r\": " << m.target.radius;
        o << "}";
    }
    o << "\n  ]\n}";
    return o.str();
}

// Extremely simple tokenizer for our own JSON format — not a general parser.
static KeymapProfile parse_profile(const std::string& json) {
    KeymapProfile p;
    auto extract = [&](const std::string& key) -> std::string {
        auto pos = json.find('"' + key + '"');
        if (pos == std::string::npos) return {};
        auto colon = json.find(':', pos);
        if (colon == std::string::npos) return {};
        auto start = json.find_first_not_of(" \t\n", colon + 1);
        if (json[start] == '"') {
            auto end = json.find('"', start + 1);
            return json.substr(start + 1, end - start - 1);
        }
        // numeric
        auto end = json.find_first_of(",}\n", start);
        return json.substr(start, end - start);
    };

    p.name         = extract("name");
    p.package_name = extract("package");

    // Parse mappings array.
    auto arr_start = json.find('"' + std::string("mappings") + '"');
    if (arr_start == std::string::npos) return p;
    auto bracket = json.find('[', arr_start);
    auto bracket_end = json.find(']', bracket);
    std::string arr = json.substr(bracket, bracket_end - bracket + 1);

    size_t cur = 0;
    while ((cur = arr.find('{', cur)) != std::string::npos) {
        auto end = arr.find('}', cur);
        std::string obj = arr.substr(cur, end - cur + 1);

        KeyMapping m;
        m.sdl_scancode   = std::stoi(extract("sc"));
        m.label          = extract("label");
        m.target.x       = std::stof(extract("x"));
        m.target.y       = std::stof(extract("y"));
        m.target.radius  = std::stof(extract("r"));
        p.mappings[m.sdl_scancode] = m;
        cur = end + 1;
    }
    return p;
}

// ── Keymapper implementation ──────────────────────────────────────────────────

Keymapper::Keymapper(const std::string& profile_dir)
    : profile_dir_(profile_dir) {}

void Keymapper::load_profiles() {
    profiles_.clear();
    if (!fs::exists(profile_dir_)) {
        fs::create_directories(profile_dir_);
        return;
    }
    for (auto& entry : fs::directory_iterator(profile_dir_)) {
        if (entry.path().extension() != ".json") continue;
        std::ifstream f(entry.path());
        std::string content((std::istreambuf_iterator<char>(f)),
                             std::istreambuf_iterator<char>());
        profiles_.push_back(parse_profile(content));
    }
}

void Keymapper::save_profile(const KeymapProfile& profile) {
    fs::create_directories(profile_dir_);
    std::string safe_name = profile.name;
    std::replace(safe_name.begin(), safe_name.end(), ' ', '_');
    std::ofstream f(profile_dir_ + "/" + safe_name + ".json");
    f << serialize_profile(profile);

    // Update in-memory list.
    auto it = std::find_if(profiles_.begin(), profiles_.end(),
        [&](const KeymapProfile& p){ return p.name == profile.name; });
    if (it != profiles_.end()) *it = profile;
    else profiles_.push_back(profile);
}

void Keymapper::activate_for_package(const std::string& package_name) {
    active_ = nullptr;
    for (auto& p : profiles_) {
        if (p.package_name == package_name) {
            active_ = &p;
            return;
        }
    }
}

std::optional<TapTarget> Keymapper::lookup(int32_t sdl_scancode) const {
    if (!active_) return std::nullopt;
    auto it = active_->mappings.find(sdl_scancode);
    if (it == active_->mappings.end()) return std::nullopt;
    return it->second.target;
}

} // namespace avm::input
