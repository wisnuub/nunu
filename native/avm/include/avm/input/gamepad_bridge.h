#pragma once
#include "input_bridge.h"
#include <cstdint>
#include <string>
#include <array>

namespace avm::input {

// Maps an SDL2 game controller to Android gamepad keycodes / axis events.
// Supports up to 4 simultaneous controllers (slots 0-3).
struct AxisState {
    float lx = 0.f, ly = 0.f;  // left stick  [-1..1]
    float rx = 0.f, ry = 0.f;  // right stick [-1..1]
    float lt = 0.f, rt = 0.f;  // triggers    [0..1]
};

struct GamepadState {
    uint32_t  buttons = 0;   // bitmask, use GamepadButton enum
    AxisState axes;
    bool      connected = false;
};

enum GamepadButton : uint32_t {
    BTN_A        = 1 <<  0,  // AKEYCODE_BUTTON_A
    BTN_B        = 1 <<  1,  // AKEYCODE_BUTTON_B
    BTN_X        = 1 <<  2,  // AKEYCODE_BUTTON_X
    BTN_Y        = 1 <<  3,  // AKEYCODE_BUTTON_Y
    BTN_L1       = 1 <<  4,  // AKEYCODE_BUTTON_L1
    BTN_R1       = 1 <<  5,  // AKEYCODE_BUTTON_R1
    BTN_L2       = 1 <<  6,  // AKEYCODE_BUTTON_L2  (also axis)
    BTN_R2       = 1 <<  7,  // AKEYCODE_BUTTON_R2  (also axis)
    BTN_LSTICK   = 1 <<  8,  // AKEYCODE_BUTTON_THUMBL
    BTN_RSTICK   = 1 <<  9,  // AKEYCODE_BUTTON_THUMBR
    BTN_START    = 1 << 10,  // AKEYCODE_BUTTON_START
    BTN_SELECT   = 1 << 11,  // AKEYCODE_BUTTON_SELECT
    BTN_DPAD_U   = 1 << 12,  // AKEYCODE_DPAD_UP
    BTN_DPAD_D   = 1 << 13,  // AKEYCODE_DPAD_DOWN
    BTN_DPAD_L   = 1 << 14,  // AKEYCODE_DPAD_LEFT
    BTN_DPAD_R   = 1 << 15,  // AKEYCODE_DPAD_RIGHT
};

class GamepadBridge {
public:
    virtual ~GamepadBridge() = default;

    virtual void set_key_callback(KeyCallback cb)   = 0;
    virtual void set_touch_callback(TouchCallback cb) = 0;  // for stick-as-touch mode
    virtual void handle_sdl_event(const void* sdl_event) = 0;

    virtual int            connected_count()                   const = 0;
    virtual GamepadState   state(int slot)                     const = 0;
    virtual std::string    device_name(int slot)               const = 0;

    // "Stick-as-touch" mode: left stick moves a virtual finger for games
    // that don't support gamepads natively (e.g. most mobile titles).
    virtual void set_stick_as_touch(bool enable, float center_x = 0.5f,
                                    float center_y = 0.5f,
                                    float radius   = 0.25f) = 0;
};

std::unique_ptr<GamepadBridge> make_sdl_gamepad_bridge();

} // namespace avm::input
