#include "avm/input/input_bridge.h"
#include <iostream>

/**
 * InputBridgeAdb — translates host input events into Android touch/key
 * events and injects them via ADB (Android Debug Bridge).
 *
 * How it works:
 *  1. The host window captures keyboard, mouse, and gamepad events.
 *  2. The active keymapper profile maps host inputs to Android inputs.
 *     Example: W key → swipe up from center
 *              Left mouse click → tap at mapped (x, y)
 *              Right analog stick → touchpad drag for camera
 *  3. Translated events are sent as ADB shell input commands:
 *     adb -s emulator-5554 shell input tap 540 960
 *     adb -s emulator-5554 shell input swipe 540 960 540 500 100
 *
 * Future: replace ADB injection with virtio-input for lower latency.
 *
 * TODO:
 *  - Implement ADB socket connection and command protocol
 *  - Add virtio-input backend for sub-millisecond input latency
 *  - Integrate SDL2 / Win32 / X11 for host input capture
 */

namespace avm {

class InputBridgeAdb : public InputBridge {
public:
    bool initialize(int adb_port) override {
        adb_port_ = adb_port;
        std::cout << "[InputBridge] ADB input bridge on port " << adb_port_ << " (stub)\n";
        // TODO: connect to ADB server at 127.0.0.1:adb_port
        return true;
    }

    void shutdown() override {
        std::cout << "[InputBridge] Shutdown.\n";
    }

    bool load_profile(const std::string& profile_path) override {
        std::cout << "[InputBridge] Loading keymapper profile: " << profile_path << " (stub)\n";
        // TODO: parse JSON profile and populate keymapper_
        return true;
    }

    void inject(const InputEvent& event) override {
        (void)event;
        // TODO: translate InputEvent to ADB shell input command and send
    }

    void poll() override {
        // TODO: poll host OS input events (SDL2 / Win32 WM_INPUT / X11)
        //       apply keymapper, call inject() for each mapped event
    }

private:
    int adb_port_ = 5554;
};

} // namespace avm
