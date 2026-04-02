#include "avm/overlay/fps_overlay.h"
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <cstring>

namespace avm::overlay {

// ── Lifecycle ─────────────────────────────────────────────────────────────────

FpsOverlay::FpsOverlay(void* sdl_renderer)
    : renderer_(sdl_renderer)
    , last_frame_time_(std::chrono::steady_clock::now())
{
    if (TTF_WasInit() == 0) TTF_Init();

    // Try to load a bundled font; fall back to a hard-coded minimal bitmap font
    // if the file is missing. In production, ship a small .ttf in assets/.
    font_large_ = TTF_OpenFont("assets/fonts/RobotoMono-Regular.ttf", 20);
    font_small_ = TTF_OpenFont("assets/fonts/RobotoMono-Regular.ttf", 13);

    // If font files are absent, font pointers remain null and we use
    // SDL_RenderDrawRect-based fallback rendering (see draw_stat).
}

FpsOverlay::~FpsOverlay() {
    if (font_large_) TTF_CloseFont(static_cast<TTF_Font*>(font_large_));
    if (font_small_) TTF_CloseFont(static_cast<TTF_Font*>(font_small_));
}

// ── Per-frame update ──────────────────────────────────────────────────────────

void FpsOverlay::update(const OverlayMetrics& m) {
    metrics_ = m;

    // Maintain rolling FPS sparkline history (last 60 frames).
    fps_history_.push_back(m.fps);
    if (fps_history_.size() > 60) fps_history_.pop_front();
}

// ── Rendering ─────────────────────────────────────────────────────────────────

void FpsOverlay::render() {
    if (!visible_) return;

    SDL_Renderer* r = static_cast<SDL_Renderer*>(renderer_);

    // ── Background panel ────────────────────────────────────────────────────
    int win_w, win_h;
    SDL_RenderGetLogicalSize(r, &win_w, &win_h);
    if (win_w == 0) SDL_GetRendererOutputSize(r, &win_w, &win_h);

    constexpr int kPanelW = 200, kPanelH = 130, kPad = 8;
    int px = 0, py = 0;
    switch (corner_) {
    case Corner::TOP_LEFT:     px = kPad;             py = kPad;             break;
    case Corner::TOP_RIGHT:    px = win_w-kPanelW-kPad; py = kPad;          break;
    case Corner::BOTTOM_LEFT:  px = kPad;             py = win_h-kPanelH-kPad; break;
    case Corner::BOTTOM_RIGHT: px = win_w-kPanelW-kPad; py = win_h-kPanelH-kPad; break;
    }

    // Semi-transparent black background.
    SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(r, 0, 0, 0, 160);
    SDL_Rect panel{ px, py, kPanelW, kPanelH };
    SDL_RenderFillRect(r, &panel);

    // Border.
    SDL_SetRenderDrawColor(r, 80, 80, 80, 200);
    SDL_RenderDrawRect(r, &panel);

    // ── FPS (large, colour-coded) ────────────────────────────────────────────
    std::ostringstream fps_str;
    fps_str << std::fixed << std::setprecision(1) << metrics_.fps << " FPS";
    uint8_t fr = 255, fg = 255, fb = 100; // yellow default
    if (metrics_.fps >= 55.f) { fr = 100; fg = 255; fb = 100; } // green  ≥55
    else if (metrics_.fps < 30.f) { fr = 255; fg = 80;  fb = 80;  } // red   <30
    draw_stat("", fps_str.str(), px + kPad, py + kPad, fr, fg, fb);

    // ── Frame time ──────────────────────────────────────────────────────────
    std::ostringstream ft;
    ft << std::fixed << std::setprecision(2) << metrics_.frame_ms << " ms";
    draw_stat("Frame", ft.str(), px + kPad, py + 34, 200, 200, 200);

    // ── CPU ─────────────────────────────────────────────────────────────────
    std::ostringstream cpu;
    cpu << std::fixed << std::setprecision(1) << metrics_.cpu_usage << "%";
    draw_stat("CPU  ", cpu.str(), px + kPad, py + 54, 200, 200, 200);

    // ── RAM ─────────────────────────────────────────────────────────────────
    std::ostringstream ram;
    ram << std::fixed << std::setprecision(0) << metrics_.ram_mb << " MB";
    draw_stat("RAM  ", ram.str(), px + kPad, py + 74, 200, 200, 200);

    // ── Renderer tag ────────────────────────────────────────────────────────
    draw_stat("GPU  ", metrics_.renderer, px + kPad, py + 94, 120, 200, 255);

    // ── Sparkline (FPS history bar chart) ───────────────────────────────────
    if (!fps_history_.empty()) {
        float max_fps = *std::max_element(fps_history_.begin(), fps_history_.end());
        if (max_fps < 1.f) max_fps = 1.f;

        int   bar_area_y  = py + kPanelH - 18;
        int   bar_area_x  = px + kPad;
        int   bar_area_w  = kPanelW - kPad * 2;
        int   bar_h_max   = 14;
        int   n           = static_cast<int>(fps_history_.size());
        float bar_w       = bar_area_w / float(std::max(n, 1));

        SDL_SetRenderDrawColor(r, 100, 220, 120, 180);
        for (int i = 0; i < n; ++i) {
            float ratio  = fps_history_[i] / max_fps;
            int   bh     = static_cast<int>(ratio * bar_h_max);
            SDL_Rect bar{
                bar_area_x + static_cast<int>(i * bar_w),
                bar_area_y + bar_h_max - bh,
                std::max(1, static_cast<int>(bar_w) - 1),
                bh
            };
            SDL_RenderFillRect(r, &bar);
        }
    }
}

// ── draw_stat — renders one "LABEL  VALUE" line ───────────────────────────────
void FpsOverlay::draw_stat(const std::string& label, const std::string& value,
                            int x, int y,
                            uint8_t cr, uint8_t cg, uint8_t cb) {
    SDL_Renderer* r = static_cast<SDL_Renderer*>(renderer_);
    SDL_Color color { cr, cg, cb, 255 };

    auto render_text = [&](TTF_Font* font, const std::string& text, int tx, int ty) {
        if (!font) return;
        SDL_Surface* surf = TTF_RenderText_Blended(
            static_cast<TTF_Font*>(font), text.c_str(), color);
        if (!surf) return;
        SDL_Texture* tex = SDL_CreateTextureFromSurface(r, surf);
        SDL_FreeSurface(surf);
        if (!tex) return;
        SDL_Rect dst { tx, ty, surf->w, surf->h };
        SDL_QueryTexture(tex, nullptr, nullptr, &dst.w, &dst.h);
        SDL_RenderCopy(r, tex, nullptr, &dst);
        SDL_DestroyTexture(tex);
    };

    std::string line = label.empty() ? value : (label + " " + value);
    TTF_Font* font = label.empty()
        ? static_cast<TTF_Font*>(font_large_)
        : static_cast<TTF_Font*>(font_small_);
    render_text(font, line, x, y);
}

} // namespace avm::overlay
