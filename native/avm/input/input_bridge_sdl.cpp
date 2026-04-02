#include "avm/input/input_bridge.h"
#include "avm/input/keymapper.h"
#include <SDL2/SDL.h>
#include <unordered_map>
#include <cmath>
#include <stdexcept>

namespace avm::input {

// SDL2-backed InputBridge implementation.
// Converts SDL mouse, touch, and keyboard events into Android equivalents.
class SdlInputBridge final : public InputBridge {
public:
    SdlInputBridge(Keymapper* keymapper)
        : keymapper_(keymapper) {}

    void set_touch_callback(TouchCallback cb) override { touch_cb_ = std::move(cb); }
    void set_key_callback(KeyCallback cb)     override { key_cb_   = std::move(cb); }
    void set_screen_size(int w, int h)         override { screen_w_ = w; screen_h_ = h; }

    void handle_sdl_event(const void* raw) override {
        const SDL_Event& e = *static_cast<const SDL_Event*>(raw);

        switch (e.type) {
        // ── Mouse → single-finger touch ──────────────────────────────────
        case SDL_MOUSEBUTTONDOWN:
            if (e.button.button == SDL_BUTTON_LEFT) {
                emit_touch(TouchEvent::Type::DOWN, 0,
                           norm_x(e.button.x), norm_y(e.button.y));
                mouse_down_ = true;
            }
            break;
        case SDL_MOUSEBUTTONUP:
            if (e.button.button == SDL_BUTTON_LEFT) {
                emit_touch(TouchEvent::Type::UP, 0,
                           norm_x(e.button.x), norm_y(e.button.y));
                mouse_down_ = false;
            }
            break;
        case SDL_MOUSEMOTION:
            if (mouse_down_)
                emit_touch(TouchEvent::Type::MOVE, 0,
                           norm_x(e.motion.x), norm_y(e.motion.y));
            break;

        // ── Native multitouch (tablet / touch screen) ────────────────────
        case SDL_FINGERDOWN:
            emit_touch(TouchEvent::Type::DOWN,
                       slot_for_finger(e.tfinger.fingerId),
                       e.tfinger.x, e.tfinger.y);
            break;
        case SDL_FINGERUP:
            emit_touch(TouchEvent::Type::UP,
                       slot_for_finger(e.tfinger.fingerId),
                       e.tfinger.x, e.tfinger.y);
            finger_slots_.erase(e.tfinger.fingerId);
            break;
        case SDL_FINGERMOTION:
            emit_touch(TouchEvent::Type::MOVE,
                       slot_for_finger(e.tfinger.fingerId),
                       e.tfinger.x, e.tfinger.y);
            break;

        // ── Keyboard → keymapper tap OR Android key passthrough ──────────
        case SDL_KEYDOWN:
        case SDL_KEYUP: {
            const bool down = (e.type == SDL_KEYDOWN);
            const int sc    = static_cast<int>(e.key.keysym.scancode);

            // Check keymapper first (game-specific tap mappings).
            if (auto tap = keymapper_ ? keymapper_->lookup(sc) : std::nullopt) {
                if (down)
                    emit_touch(TouchEvent::Type::DOWN, kb_slot_, tap->x, tap->y);
                else
                    emit_touch(TouchEvent::Type::UP,   kb_slot_, tap->x, tap->y);
                kb_slot_ = (kb_slot_ % 9) + 1; // rotate slots 1-9 for simultaneous keys
            } else {
                // Fall back to direct Android key injection.
                int32_t akc = sdl_scancode_to_android_keycode(sc);
                if (akc != 0 && key_cb_)
                    key_cb_({ down ? KeyEvent::Action::DOWN : KeyEvent::Action::UP, akc });
            }
            break;
        }
        default: break;
        }
    }

private:
    // ── Helpers ──────────────────────────────────────────────────────────
    float norm_x(int px) const { return screen_w_ > 0 ? px / float(screen_w_) : 0.f; }
    float norm_y(int py) const { return screen_h_ > 0 ? py / float(screen_h_) : 0.f; }

    void emit_touch(TouchEvent::Type t, int32_t slot, float x, float y) {
        if (touch_cb_) touch_cb_({ t, slot, x, y });
    }

    int32_t slot_for_finger(SDL_FingerID fid) {
        auto it = finger_slots_.find(fid);
        if (it != finger_slots_.end()) return it->second;
        int32_t s = next_slot_;
        finger_slots_[fid] = s;
        next_slot_ = (next_slot_ % 9) + 1;
        return s;
    }

    // Minimal SDL_Scancode → Android KeyCode table (extend as needed).
    static int32_t sdl_scancode_to_android_keycode(int sc) {
        // SDL_SCANCODE → AKEYCODE mapping for common game controls.
        // Full table: https://developer.android.com/reference/android/view/KeyEvent
        static const std::unordered_map<int, int32_t> kTable = {
            { SDL_SCANCODE_ESCAPE,    4  }, // AKEYCODE_BACK
            { SDL_SCANCODE_HOME,    122  }, // AKEYCODE_HOME
            { SDL_SCANCODE_MENU,      82 }, // AKEYCODE_MENU
            { SDL_SCANCODE_RETURN,    66 }, // AKEYCODE_ENTER
            { SDL_SCANCODE_BACKSPACE, 67 }, // AKEYCODE_DEL
            { SDL_SCANCODE_UP,       19  }, // AKEYCODE_DPAD_UP
            { SDL_SCANCODE_DOWN,     20  }, // AKEYCODE_DPAD_DOWN
            { SDL_SCANCODE_LEFT,     21  }, // AKEYCODE_DPAD_LEFT
            { SDL_SCANCODE_RIGHT,    22  }, // AKEYCODE_DPAD_RIGHT
            { SDL_SCANCODE_LCTRL,   113  }, // AKEYCODE_CTRL_LEFT
            { SDL_SCANCODE_LSHIFT,   59  }, // AKEYCODE_SHIFT_LEFT
            // Volume
            { SDL_SCANCODE_EQUALS,   24  }, // AKEYCODE_VOLUME_UP
            { SDL_SCANCODE_MINUS,    25  }, // AKEYCODE_VOLUME_DOWN
        };
        auto it = kTable.find(sc);
        return it != kTable.end() ? it->second : 0;
    }

    Keymapper*    keymapper_   = nullptr;
    TouchCallback touch_cb_;
    KeyCallback   key_cb_;
    int           screen_w_   = 1080;
    int           screen_h_   = 1920;
    bool          mouse_down_ = false;
    int32_t       kb_slot_    = 1;   // next slot for keyboard-mapped taps
    int32_t       next_slot_  = 1;   // next slot for native finger tracking
    std::unordered_map<SDL_FingerID, int32_t> finger_slots_;
};

// Factory — used by the emulator core to instantiate the bridge.
std::unique_ptr<InputBridge> make_sdl_input_bridge(Keymapper* keymapper) {
    return std::make_unique<SdlInputBridge>(keymapper);
}

} // namespace avm::input
