#pragma once
// input_bridge.h — abstract interface for all host→guest input transport paths.
//
// Two concrete implementations exist:
//   - InputBridgeSdl   : SDL2 keyboard/mouse events → ADB sendevent
//   - InputBridgeAdb   : raw ADB shell sendevent commands over TCP
//
// VmManager holds a unique_ptr<InputBridge> and calls inject_*() from its
// SDL event loop.

#include <cstdint>
#include <string>

namespace avm::input {

// --- Touch event (Multi-Touch Protocol B) ---
struct TouchPoint {
    int     slot;       // tracking slot 0–9
    int     x, y;       // screen coordinates in guest pixels
    bool    down;       // true = finger down, false = lift
};

// --- Mouse / pointer event ---
struct PointerEvent {
    int     x, y;
    bool    left_down;
    bool    right_down;
};

// --- Key event ---
struct KeyEvent {
    int     keycode;    // SDL_Keycode or Android keycode
    bool    down;
};

// --- Abstract bridge ---
class InputBridge {
public:
    virtual ~InputBridge() = default;

    // Connect to the guest (ADB port, virtio socket, etc.)
    virtual bool connect() = 0;
    virtual void disconnect() = 0;
    virtual bool is_connected() const = 0;

    // Inject events into the guest
    virtual bool inject_touch (const TouchPoint&   ev) = 0;
    virtual bool inject_key   (const KeyEvent&     ev) = 0;
    virtual bool inject_pointer(const PointerEvent& ev) = 0;

    // Optional: set display resolution for coordinate scaling
    virtual void set_display_size(int w, int h) { display_w_ = w; display_h_ = h; }

protected:
    int display_w_ = 1080;
    int display_h_ = 1920;
};

} // namespace avm::input
