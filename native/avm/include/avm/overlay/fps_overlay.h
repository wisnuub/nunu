#pragma once
#include <cstdint>
#include <string>
#include <deque>
#include <chrono>

namespace avm::overlay {

struct OverlayMetrics {
    float fps          = 0.f;
    float frame_ms     = 0.f;  // last frame time in ms
    float cpu_usage    = 0.f;  // 0-100%
    float ram_mb       = 0.f;  // guest RAM used in MiB
    std::string gpu_name;      // e.g. "RTX 4060"
    std::string renderer;      // "Vulkan" / "OpenGL" / "Software"
};

// FpsOverlay — renders an in-window HUD using SDL2_ttf / Dear ImGui lite.
// Drawn *after* the frame present so it never delays the GPU pipeline.
class FpsOverlay {
public:
    enum class Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT };

    explicit FpsOverlay(void* sdl_renderer); // SDL_Renderer*
    ~FpsOverlay();

    // Call once per frame with latest metrics.
    void update(const OverlayMetrics& metrics);

    // Render the overlay onto the SDL surface.
    void render();

    // Toggle visibility (bound to F3 by default).
    void set_visible(bool v) { visible_ = v; }
    bool visible()     const { return visible_; }

    void set_corner(Corner c) { corner_ = c; }

private:
    void  draw_stat(const std::string& label, const std::string& value,
                    int x, int y, uint8_t r, uint8_t g, uint8_t b);

    void* renderer_   = nullptr; // SDL_Renderer*
    void* font_large_ = nullptr; // TTF_Font* (24pt)
    void* font_small_ = nullptr; // TTF_Font* (14pt)

    bool         visible_ = true;
    Corner       corner_  = Corner::TOP_LEFT;
    OverlayMetrics metrics_;

    // Rolling FPS history for a sparkline (last 60 samples).
    std::deque<float> fps_history_;
    std::chrono::steady_clock::time_point last_frame_time_;
};

} // namespace avm::overlay
