#include "avm/input/gamepad_bridge.h"
#include <SDL2/SDL.h>
#include <array>
#include <unordered_map>
#include <cmath>
#include <algorithm>

namespace avm::input {

// Android keycodes for gamepad buttons (from android/keycodes.h)
static constexpr int32_t kAndroidGamepad[] = {
    96,   // AKEYCODE_BUTTON_A
    97,   // AKEYCODE_BUTTON_B
    99,   // AKEYCODE_BUTTON_X
    100,  // AKEYCODE_BUTTON_Y
    102,  // AKEYCODE_BUTTON_L1
    103,  // AKEYCODE_BUTTON_R1
    104,  // AKEYCODE_BUTTON_L2
    105,  // AKEYCODE_BUTTON_R2
    106,  // AKEYCODE_BUTTON_THUMBL
    107,  // AKEYCODE_BUTTON_THUMBR
    108,  // AKEYCODE_BUTTON_START
    109,  // AKEYCODE_BUTTON_SELECT
    19,   // AKEYCODE_DPAD_UP
    20,   // AKEYCODE_DPAD_DOWN
    21,   // AKEYCODE_DPAD_LEFT
    22,   // AKEYCODE_DPAD_RIGHT
};

class SdlGamepadBridge final : public GamepadBridge {
public:
    SdlGamepadBridge() {
        SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC);
    }
    ~SdlGamepadBridge() override {
        for (auto& s : slots_)
            if (s.controller) SDL_GameControllerClose(s.controller);
    }

    void set_key_callback(KeyCallback cb)     override { key_cb_   = std::move(cb); }
    void set_touch_callback(TouchCallback cb) override { touch_cb_ = std::move(cb); }

    void set_stick_as_touch(bool enable, float cx, float cy, float r) override {
        stick_as_touch_ = enable;
        stick_cx_ = cx; stick_cy_ = cy; stick_radius_ = r;
    }

    int connected_count() const override {
        int n = 0;
        for (auto& s : slots_) if (s.state.connected) ++n;
        return n;
    }

    GamepadState state(int slot) const override {
        if (slot < 0 || slot >= 4) return {};
        return slots_[slot].state;
    }

    std::string device_name(int slot) const override {
        if (slot < 0 || slot >= 4 || !slots_[slot].controller) return "";
        return SDL_GameControllerName(slots_[slot].controller);
    }

    void handle_sdl_event(const void* raw) override {
        const SDL_Event& e = *static_cast<const SDL_Event*>(raw);
        switch (e.type) {

        case SDL_CONTROLLERDEVICEADDED: {
            int idx = first_free_slot();
            if (idx < 0) break;
            SDL_GameController* gc = SDL_GameControllerOpen(e.cdevice.which);
            if (!gc) break;
            slots_[idx].controller = gc;
            slots_[idx].state.connected = true;
            instance_to_slot_[SDL_JoystickInstanceID(
                SDL_GameControllerGetJoystick(gc))] = idx;
            break;
        }
        case SDL_CONTROLLERDEVICEREMOVED: {
            auto it = instance_to_slot_.find(e.cdevice.which);
            if (it == instance_to_slot_.end()) break;
            int idx = it->second;
            SDL_GameControllerClose(slots_[idx].controller);
            slots_[idx] = {};
            instance_to_slot_.erase(it);
            break;
        }

        case SDL_CONTROLLERBUTTONDOWN:
        case SDL_CONTROLLERBUTTONUP: {
            auto it = instance_to_slot_.find(e.cbutton.which);
            if (it == instance_to_slot_.end()) break;
            int idx = it->second;
            bool down = (e.type == SDL_CONTROLLERBUTTONDOWN);
            uint32_t mask = sdl_button_to_mask(e.cbutton.button);
            if (mask == 0) break;

            if (down) slots_[idx].state.buttons |= mask;
            else      slots_[idx].state.buttons &= ~mask;

            int32_t akc = mask_to_android_keycode(mask);
            if (akc && key_cb_)
                key_cb_({ down ? KeyEvent::Action::DOWN : KeyEvent::Action::UP, akc });
            break;
        }

        case SDL_CONTROLLERAXISMOTION: {
            auto it = instance_to_slot_.find(e.caxis.which);
            if (it == instance_to_slot_.end()) break;
            int idx = it->second;
            float v = e.caxis.value / 32767.f;
            v = std::clamp(v, -1.f, 1.f);
            // Dead zone
            if (std::fabs(v) < 0.12f) v = 0.f;

            update_axis(slots_[idx].state.axes, e.caxis.axis, v);

            // Stick-as-touch: map left stick to a sliding finger for
            // games without native gamepad support (most mobile titles).
            if (stick_as_touch_ && touch_cb_ &&
                (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX ||
                 e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY))
            {
                float lx = slots_[idx].state.axes.lx;
                float ly = slots_[idx].state.axes.ly;
                bool  moving = (std::fabs(lx) > 0.05f || std::fabs(ly) > 0.05f);

                if (moving && !stick_finger_down_) {
                    touch_cb_({ TouchEvent::Type::DOWN, kStickSlot,
                                stick_cx_, stick_cy_ });
                    stick_finger_down_ = true;
                }
                if (moving && stick_finger_down_) {
                    touch_cb_({ TouchEvent::Type::MOVE, kStickSlot,
                                stick_cx_ + lx * stick_radius_,
                                stick_cy_ + ly * stick_radius_ });
                } else if (!moving && stick_finger_down_) {
                    touch_cb_({ TouchEvent::Type::UP, kStickSlot,
                                stick_cx_, stick_cy_ });
                    stick_finger_down_ = false;
                }
            }
            break;
        }
        default: break;
        }
    }

private:
    static uint32_t sdl_button_to_mask(uint8_t btn) {
        switch (btn) {
        case SDL_CONTROLLER_BUTTON_A:             return BTN_A;
        case SDL_CONTROLLER_BUTTON_B:             return BTN_B;
        case SDL_CONTROLLER_BUTTON_X:             return BTN_X;
        case SDL_CONTROLLER_BUTTON_Y:             return BTN_Y;
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return BTN_L1;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return BTN_R1;
        case SDL_CONTROLLER_BUTTON_LEFTSTICK:     return BTN_LSTICK;
        case SDL_CONTROLLER_BUTTON_RIGHTSTICK:    return BTN_RSTICK;
        case SDL_CONTROLLER_BUTTON_START:         return BTN_START;
        case SDL_CONTROLLER_BUTTON_BACK:          return BTN_SELECT;
        case SDL_CONTROLLER_BUTTON_DPAD_UP:       return BTN_DPAD_U;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:     return BTN_DPAD_D;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:     return BTN_DPAD_L;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:    return BTN_DPAD_R;
        default: return 0;
        }
    }

    static int32_t mask_to_android_keycode(uint32_t mask) {
        for (int i = 0; i < 16; ++i)
            if (mask == (1u << i)) return kAndroidGamepad[i];
        return 0;
    }

    static void update_axis(AxisState& a, uint8_t axis, float v) {
        switch (axis) {
        case SDL_CONTROLLER_AXIS_LEFTX:        a.lx = v; break;
        case SDL_CONTROLLER_AXIS_LEFTY:        a.ly = v; break;
        case SDL_CONTROLLER_AXIS_RIGHTX:       a.rx = v; break;
        case SDL_CONTROLLER_AXIS_RIGHTY:       a.ry = v; break;
        case SDL_CONTROLLER_AXIS_TRIGGERLEFT:  a.lt = (v + 1.f) * .5f; break;
        case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: a.rt = (v + 1.f) * .5f; break;
        }
    }

    int first_free_slot() const {
        for (int i = 0; i < 4; ++i)
            if (!slots_[i].state.connected) return i;
        return -1;
    }

    struct Slot { SDL_GameController* controller = nullptr; GamepadState state; };
    std::array<Slot, 4>                      slots_;
    std::unordered_map<SDL_JoystickID, int>  instance_to_slot_;

    KeyCallback   key_cb_;
    TouchCallback touch_cb_;

    bool  stick_as_touch_    = false;
    float stick_cx_          = 0.5f;
    float stick_cy_          = 0.5f;
    float stick_radius_      = 0.25f;
    bool  stick_finger_down_ = false;

    static constexpr int32_t kStickSlot = 9;  // reserved multitouch slot
};

std::unique_ptr<GamepadBridge> make_sdl_gamepad_bridge() {
    return std::make_unique<SdlGamepadBridge>();
}

} // namespace avm::input
