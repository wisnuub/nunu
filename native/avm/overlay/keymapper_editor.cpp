#include "avm/overlay/keymapper_editor.h"
#include <SDL2/SDL_ttf.h>
#include <cmath>
#include <algorithm>
#include <sstream>

namespace avm::overlay {

KeymapperEditor::KeymapperEditor(SDL_Renderer* renderer,
                                  avm::input::Keymapper* keymapper)
    : renderer_(renderer), keymapper_(keymapper)
{
    if (TTF_WasInit() == 0) TTF_Init();
    font_ = TTF_OpenFont("assets/fonts/RobotoMono-Regular.ttf", 14);
}

void KeymapperEditor::set_active(bool active) {
    active_ = active;
    if (active) rebuild_handles();
}

// Rebuild handle list from the active profile.
void KeymapperEditor::rebuild_handles() {
    handles_.clear();
    drag_target_ = nullptr;
    const auto* profile = keymapper_->active_profile();
    if (!profile) return;
    for (auto& [sc, mapping] : profile->mappings) {
        Handle h;
        h.sdl_scancode = sc;
        h.label        = mapping.label;
        h.x            = mapping.target.x;
        h.y            = mapping.target.y;
        h.radius       = mapping.target.radius;
        handles_.push_back(h);
    }
}

// ── Event handling ────────────────────────────────────────────────────────────────

bool KeymapperEditor::handle_sdl_event(const SDL_Event& e) {
    if (!active_) return false;

    int win_w = 1, win_h = 1;
    SDL_GetRendererOutputSize(renderer_, &win_w, &win_h);

    switch (e.type) {

    case SDL_KEYDOWN:
        // F4 — toggle editor off & save.
        if (e.key.keysym.scancode == SDL_SCANCODE_F4) {
            commit_to_profile();
            set_active(false);
            return true;
        }
        // Escape — cancel listen mode.
        if (e.key.keysym.scancode == SDL_SCANCODE_ESCAPE && listening_for_key_) {
            listening_for_key_ = false;
            pending_handle_.reset();
            return true;
        }
        // If listening for a key assignment, capture it.
        if (listening_for_key_ && pending_handle_) {
            pending_handle_->sdl_scancode = static_cast<int32_t>(e.key.keysym.scancode);
            // Label from SDL key name, trimmed to 6 chars.
            std::string name = SDL_GetKeyName(e.key.keysym.sym);
            if (name.size() > 6) name = name.substr(0, 6);
            pending_handle_->label = name;
            handles_.push_back(*pending_handle_);
            pending_handle_.reset();
            listening_for_key_ = false;
            return true;
        }
        // Delete key under cursor.
        if (e.key.keysym.scancode == SDL_SCANCODE_DELETE && drag_target_) {
            handles_.erase(std::remove_if(handles_.begin(), handles_.end(),
                [this](const Handle& h){ return &h == drag_target_; }),
                handles_.end());
            drag_target_ = nullptr;
            return true;
        }
        return false;

    case SDL_MOUSEBUTTONDOWN:
        if (e.button.button == SDL_BUTTON_LEFT) {
            float nx = e.button.x / float(win_w);
            float ny = e.button.y / float(win_h);
            drag_target_ = hit_test(nx, ny);
            if (drag_target_) {
                drag_target_->dragging = true;
                return true;
            }
            // Click on empty space — start adding new handle.
            pending_handle_ = Handle{};
            pending_handle_->x = nx;
            pending_handle_->y = ny;
            pending_handle_->radius = 0.04f;
            listening_for_key_ = true;
            return true;
        }
        if (e.button.button == SDL_BUTTON_RIGHT) {
            // Right-click — delete handle under cursor.
            float nx = e.button.x / float(win_w);
            float ny = e.button.y / float(win_h);
            Handle* h = hit_test(nx, ny);
            if (h) {
                handles_.erase(std::remove_if(handles_.begin(), handles_.end(),
                    [h](const Handle& x){ return &x == h; }), handles_.end());
                drag_target_ = nullptr;
                return true;
            }
        }
        return false;

    case SDL_MOUSEBUTTONUP:
        if (drag_target_) {
            drag_target_->dragging = false;
            drag_target_ = nullptr;
        }
        return false;

    case SDL_MOUSEMOTION:
        if (drag_target_ && drag_target_->dragging) {
            drag_target_->x = e.motion.x / float(win_w);
            drag_target_->y = e.motion.y / float(win_h);
            drag_target_->x = std::clamp(drag_target_->x, 0.f, 1.f);
            drag_target_->y = std::clamp(drag_target_->y, 0.f, 1.f);
            return true;
        }
        // Update hover state.
        {
            float nx = e.motion.x / float(win_w);
            float ny = e.motion.y / float(win_h);
            for (auto& h : handles_)
                h.hovered = (hit_test(nx, ny) == &h);
        }
        return false;

    // Scroll wheel — resize radius of hovered handle.
    case SDL_MOUSEWHEEL:
        for (auto& h : handles_) {
            if (h.hovered) {
                h.radius = std::clamp(h.radius + e.wheel.y * 0.005f, 0.01f, 0.15f);
                return true;
            }
        }
        return false;

    default: return false;
    }
}

// ── Rendering ──────────────────────────────────────────────────────────────────
void KeymapperEditor::render(int sw, int sh) {
    if (!active_) return;

    // Dim background to signal edit mode.
    SDL_SetRenderDrawBlendMode(renderer_, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(renderer_, 0, 0, 0, 90);
    SDL_Rect full{ 0, 0, sw, sh };
    SDL_RenderFillRect(renderer_, &full);

    // Draw all handles.
    for (const auto& h : handles_)
        render_handle(h, sw, sh);

    // Draw pending (not yet key-assigned) handle as a dotted ghost.
    if (pending_handle_) {
        int cx = static_cast<int>(pending_handle_->x * sw);
        int cy = static_cast<int>(pending_handle_->y * sh);
        int r  = static_cast<int>(pending_handle_->radius * sw);
        render_ghost_circle(cx, cy, r, 255, 255, 0, 160);
        render_label("Press a key...", cx - 40, cy + r + 4);
    }

    render_toolbar(sw, sh);
}

void KeymapperEditor::render_handle(const Handle& h, int sw, int sh) {
    int cx = static_cast<int>(h.x * sw);
    int cy = static_cast<int>(h.y * sh);
    int r  = static_cast<int>(h.radius * sw);

    uint8_t cr = 80, cg = 200, cb = 255, ca = h.hovered ? 220 : 160;
    if (h.dragging) { cr = 255; cg = 200; cb = 80; }

    render_ghost_circle(cx, cy, r, cr, cg, cb, ca);

    // Key label centered in circle.
    render_label(h.label, cx - static_cast<int>(h.label.size() * 4), cy - 7);
}

// Approximate circle with line segments (no SDL_gfx dependency).
void KeymapperEditor::render_ghost_circle(int cx, int cy, int r,
                                           uint8_t cr, uint8_t cg,
                                           uint8_t cb, uint8_t ca) {
    SDL_SetRenderDrawBlendMode(renderer_, SDL_BLENDMODE_BLEND);

    // Filled circle via horizontal scanlines.
    SDL_SetRenderDrawColor(renderer_, cr, cg, cb, ca / 3);
    for (int dy = -r; dy <= r; ++dy) {
        int dx = static_cast<int>(std::sqrt(float(r * r - dy * dy)));
        SDL_RenderDrawLine(renderer_, cx - dx, cy + dy, cx + dx, cy + dy);
    }

    // Outline.
    SDL_SetRenderDrawColor(renderer_, cr, cg, cb, ca);
    constexpr int kSeg = 64;
    for (int i = 0; i < kSeg; ++i) {
        float a0 = i       * 2.f * 3.14159f / kSeg;
        float a1 = (i + 1) * 2.f * 3.14159f / kSeg;
        SDL_RenderDrawLine(renderer_,
            cx + static_cast<int>(std::cos(a0) * r),
            cy + static_cast<int>(std::sin(a0) * r),
            cx + static_cast<int>(std::cos(a1) * r),
            cy + static_cast<int>(std::sin(a1) * r));
    }
}

void KeymapperEditor::render_label(const std::string& text, int x, int y) {
    if (!font_) return;
    SDL_Color white{ 255, 255, 255, 255 };
    SDL_Surface* surf = TTF_RenderText_Blended(
        static_cast<TTF_Font*>(font_), text.c_str(), white);
    if (!surf) return;
    SDL_Texture* tex = SDL_CreateTextureFromSurface(renderer_, surf);
    SDL_Rect dst{ x, y, surf->w, surf->h };
    SDL_FreeSurface(surf);
    if (!tex) return;
    SDL_QueryTexture(tex, nullptr, nullptr, &dst.w, &dst.h);
    SDL_RenderCopy(renderer_, tex, nullptr, &dst);
    SDL_DestroyTexture(tex);
}

void KeymapperEditor::render_toolbar(int sw, int sh) {
    // Bottom bar: [EDIT MODE] [Left-click: add] [Drag: move] [Right-click / Del: remove] [Scroll: resize] [F4: save]
    SDL_SetRenderDrawBlendMode(renderer_, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(renderer_, 20, 20, 20, 200);
    SDL_Rect bar{ 0, sh - 28, sw, 28 };
    SDL_RenderFillRect(renderer_, &bar);

    static const char* hint =
        "KEYMAP EDIT │ Left-click: add  │ Drag: move  "
        "│ Right-click/Del: remove  │ Scroll: resize  │ F4: save & exit";
    render_label(hint, 8, sh - 22);
}

// ── Hit test & commit ────────────────────────────────────────────────────────────────

KeymapperEditor::Handle* KeymapperEditor::hit_test(float nx, float ny) {
    int sw, sh;
    SDL_GetRendererOutputSize(renderer_, &sw, &sh);
    int px = static_cast<int>(nx * sw);
    int py = static_cast<int>(ny * sh);

    for (auto& h : handles_) {
        int cx = static_cast<int>(h.x * sw);
        int cy = static_cast<int>(h.y * sh);
        int r  = static_cast<int>(h.radius * sw);
        int dx = px - cx, dy = py - cy;
        if (dx * dx + dy * dy <= r * r) return &h;
    }
    return nullptr;
}

void KeymapperEditor::commit_to_profile() {
    const auto* active = keymapper_->active_profile();
    if (!active) return;

    avm::input::KeymapProfile updated = *active;
    updated.mappings.clear();
    for (const auto& h : handles_) {
        avm::input::KeyMapping m;
        m.sdl_scancode   = h.sdl_scancode;
        m.label          = h.label;
        m.target.x       = h.x;
        m.target.y       = h.y;
        m.target.radius  = h.radius;
        updated.mappings[h.sdl_scancode] = m;
    }
    if (save_cb_) save_cb_(updated);
    keymapper_->save_profile(updated);
}

} // namespace avm::overlay
