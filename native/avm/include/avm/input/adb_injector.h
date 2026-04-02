#pragma once
#include "input_bridge.h"
#include <string>
#include <memory>

namespace avm::input {

// AdbInjector — dispatches synthesized touch/key events to the Android guest
// via `adb shell input` commands over a local TCP socket (ADB default: 5037).
//
// For each TouchEvent it builds the equivalent:
//   adb shell input touchscreen swipe/tap ...
//   adb shell input keyevent <AKEYCODE>
//
// This is the "safe" transport that works with any Android image.
// For lower latency, prefer VirtioInputTransport (virtio_input.h).
class AdbInjector {
public:
    struct Config {
        std::string host       = "127.0.0.1";
        int         port       = 5037;          // ADB server port
        int         serial_port = 5554;         // emulator serial (5554, 5556, ...)
        int         screen_w   = 1080;
        int         screen_h   = 1920;
        int         timeout_ms = 200;
    };

    explicit AdbInjector(const Config& cfg);
    ~AdbInjector();

    // Returns true if ADB server is reachable.
    bool connect();
    void disconnect();
    bool is_connected() const { return connected_; }

    // Inject a synthesized touch event.
    void inject_touch(const TouchEvent& e);

    // Inject a synthesized key event.
    void inject_key(const KeyEvent& e);

    // Query the foreground app package (used to activate keymaps).
    std::string foreground_package();

private:
    // Send a raw ADB shell command; returns stdout.
    std::string shell(const std::string& cmd);

    // Build evdev-style multitouch command strings.
    std::string touch_cmd(const TouchEvent& e) const;
    std::string key_cmd(const KeyEvent& e)     const;

    Config      cfg_;
    bool        connected_ = false;

    // Platform socket handle (int on Linux/macOS, SOCKET on Windows).
    // Stored as intptr_t for portability without platform includes in header.
    intptr_t    sock_ = -1;

    // Active slot tracking for DOWN/MOVE/UP sequencing.
    struct SlotState { float x = 0, y = 0; bool active = false; };
    SlotState   slots_[10];
};

} // namespace avm::input
