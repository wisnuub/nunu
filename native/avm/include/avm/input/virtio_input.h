#pragma once
// VirtioInputTransport: injects evdev-format input events directly into the
// guest kernel via a virtio-input device socket.
// Only available on Linux and macOS (uses Unix domain sockets).
// Guarded by AVM_VIRTIO_DISABLED on Windows.

#include "avm/core/platform.h"
#include "input_bridge.h"

#ifndef AVM_VIRTIO_DISABLED

#include <string>
#include <thread>
#include <queue>
#include <mutex>
#include <atomic>
#include <functional>

namespace avm::input {

// Linux input_event structure (same layout on macOS for our purposes)
struct EvdevEvent {
    uint64_t time_sec;
    uint64_t time_usec;
    uint16_t type;
    uint16_t code;
    int32_t  value;
};

class VirtioInputTransport : public InputBridge {
public:
    struct Config {
        std::string socket_path = AVM_SOCKET_DIR "avm_virtio_input";
        int         queue_depth = 256;
    };

    explicit VirtioInputTransport(const Config& cfg = {});
    ~VirtioInputTransport() override;

    bool connect()    override;
    void disconnect() override;
    bool is_connected() const override { return connected_.load(); }

    bool inject_touch  (const TouchPoint&   ev) override;
    bool inject_key    (const KeyEvent&     ev) override;
    bool inject_pointer(const PointerEvent& ev) override;

private:
    void writer_thread();
    bool enqueue(const EvdevEvent& ev);
    void send_syn();

    Config              cfg_;
    int                 sock_fd_   = -1;
    std::atomic<bool>   connected_ = false;
    std::atomic<bool>   running_   = false;
    std::thread         writer_;
    std::queue<EvdevEvent> queue_;
    std::mutex          queue_mtx_;
};

} // namespace avm::input

#endif // AVM_VIRTIO_DISABLED
