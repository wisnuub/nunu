#pragma once
#include "avm/input/keymapper.h"
#include <SDL2/SDL.h>
#include <functional>
#include <string>
#include <optional>

namespace avm::overlay {

// KeymapperEditor — an in-window drag-and-drop UI for placing tap targets
// on the live emulator screen.
//
// Usage:
//   1. User presses F4 to enter edit mode.
//   2. Semi-transparent circles appear on screen at each mapped key position.
//   3. User drags circles to reposition; presses a key to assign to slot.
//   4. Presses F4 again (or clicks Save) to persist and exit edit mode.
class KeymapperEditor {
public:
    using SaveCallback = std::function<void(const avm::input::KeymapProfile&)>;

    explicit KeymapperEditor(SDL_Renderer* renderer,
                             avm::input::Keymapper* keymapper);

    // Enter / exit edit mode.
    void set_active(bool active);
    bool is_active() const { return active_; }

    // Feed SDL events while in edit mode.
    // Returns true if the event was consumed (don't pass to InputBridge).
    bool handle_sdl_event(const SDL_Event& e);

    // Render the editor overlay (circles, labels, toolbar).
    void render(int screen_w, int screen_h);

    // Called after the user saves — persists the modified profile.
    void set_save_callback(SaveCallback cb) { save_cb_ = std::move(cb); }

private:
    struct Handle {
        int32_t     sdl_scancode;
        std::string label;
        float       x, y;       // normalized [0..1]
        float       radius;
        bool        hovered  = false;
        bool        dragging = false;
    };

    void  rebuild_handles();
    void  render_handle(const Handle& h, int sw, int sh);
    void  render_toolbar(int sw, int sh);
    void  render_ghost_circle(int cx, int cy, int r,
                               uint8_t cr, uint8_t cg, uint8_t cb, uint8_t a);
    void  render_label(const std::string& text, int x, int y);
    Handle* hit_test(float nx, float ny);
    void  commit_to_profile();

    SDL_Renderer*             renderer_;
    avm::input::Keymapper*    keymapper_;
    SaveCallback              save_cb_;

    bool                      active_       = false;
    std::vector<Handle>       handles_;
    Handle*                   drag_target_  = nullptr;
    int                       drag_off_x_   = 0;
    int                       drag_off_y_   = 0;

    // Key-listen mode: waiting for a keypress to assign to a new handle.
    bool                      listening_for_key_ = false;
    std::optional<Handle>     pending_handle_;

    TTF_Font*                 font_ = nullptr;
};

} // namespace avm::overlay
