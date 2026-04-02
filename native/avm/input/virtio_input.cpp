#include "avm/input/virtio_input.h"
#include <sstream>
#include <cstring>
#include <stdexcept>

#ifdef _WIN32
#  include <winsock2.h>
#  include <ws2tcpip.h>
   using fd_t = SOCKET;
   static constexpr fd_t kInvalidFd = INVALID_SOCKET;
   inline void close_fd(fd_t f) { closesocket(f); }
#else
#  include <sys/un.h>
#  include <sys/socket.h>
#  include <unistd.h>
   using fd_t = int;
   static constexpr fd_t kInvalidFd = -1;
   inline void close_fd(fd_t f) { ::close(f); }
#endif

namespace avm::input {

VirtioInputTransport::VirtioInputTransport(const Config& cfg) : cfg_(cfg) {}

VirtioInputTransport::~VirtioInputTransport() { close(); }

// ── Open QMP socket ─────────────────────────────────────────────────────────────

bool VirtioInputTransport::open() {
#ifdef _WIN32
    // Windows: QEMU QMP over TCP loopback (QEMU -qmp tcp:127.0.0.1:<port>)
    // For now, return false on Windows — full implementation in next patch.
    return false;
#else
    fd_t fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd == kInvalidFd) return false;

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, cfg_.qmp_socket.c_str(), sizeof(addr.sun_path) - 1);

    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        close_fd(fd);
        return false;
    }
    fd_   = static_cast<intptr_t>(fd);
    open_ = true;

    // Start async write thread.
    running_.store(true);
    flush_thread_ = std::thread(&VirtioInputTransport::flush_thread_fn, this);
    return true;
#endif
}

void VirtioInputTransport::close() {
    if (!open_) return;
    running_.store(false);
    queue_cv_.notify_all();
    if (flush_thread_.joinable()) flush_thread_.join();
    close_fd(static_cast<fd_t>(fd_));
    open_ = false;
    fd_   = -1;
}

// ── Event injection ─────────────────────────────────────────────────────────────────

void VirtioInputTransport::inject_touch(const TouchEvent& e) {
    int px = static_cast<int>(e.x * (cfg_.screen_w - 1));
    int py = static_cast<int>(e.y * (cfg_.screen_h - 1));
    int slot = e.slot < cfg_.max_slots ? e.slot : 0;

    // MT protocol B: slot → tracking_id → x/y → pressure → SYN_REPORT
    enqueue({ EV_ABS, ABS_MT_SLOT, slot });

    if (e.type == TouchEvent::Type::DOWN) {
        slots_[slot].tracking_id = next_tracking_id();
        slots_[slot].active      = true;
        enqueue({ EV_ABS, ABS_MT_TRACKING_ID, slots_[slot].tracking_id });
        enqueue({ EV_KEY, BTN_TOUCH, 1 });
    } else if (e.type == TouchEvent::Type::UP) {
        enqueue({ EV_ABS, ABS_MT_TRACKING_ID, -1 }); // -1 = lift
        enqueue({ EV_KEY, BTN_TOUCH, 0 });
        slots_[slot].active = false;
    }

    if (e.type != TouchEvent::Type::UP) {
        enqueue({ EV_ABS, ABS_MT_POSITION_X, px });
        enqueue({ EV_ABS, ABS_MT_POSITION_Y, py });
        enqueue({ EV_ABS, ABS_MT_PRESSURE,   50 });
    }
    enqueue({ EV_SYN, SYN_REPORT, 0 });
}

void VirtioInputTransport::inject_key(const KeyEvent& e) {
    int32_t val = (e.action == KeyEvent::Action::DOWN) ? 1 : 0;
    enqueue({ EV_KEY, static_cast<uint16_t>(e.android_keycode), val });
    enqueue({ EV_SYN, SYN_REPORT, 0 });
}

// ── Async write queue ────────────────────────────────────────────────────────────────

void VirtioInputTransport::enqueue(InputEvent e) {
    std::lock_guard<std::mutex> lk(queue_mutex_);
    event_queue_.push(e);
    queue_cv_.notify_one();
}

void VirtioInputTransport::flush_thread_fn() {
    while (running_.load()) {
        std::unique_lock<std::mutex> lk(queue_mutex_);
        queue_cv_.wait(lk, [this]{
            return !event_queue_.empty() || !running_.load();
        });
        while (!event_queue_.empty()) {
            InputEvent e = event_queue_.front();
            event_queue_.pop();
            lk.unlock();
            write_event(e);
            lk.lock();
        }
    }
}

void VirtioInputTransport::write_event(const InputEvent& e) {
    // QMP human-monitor-interface: inject-nmi style not suitable;
    // instead we write raw evdev structs to the virtio-input Unix socket
    // which QEMU exposes when built with --enable-virtio-input.
    //
    // Struct layout matches struct input_event from <linux/input.h>:
    //   timeval (8 bytes) | type (2) | code (2) | value (4)  = 16 bytes
    uint8_t buf[16] = {};
    // timeval: zeroed (QEMU ignores it for injected events)
    uint16_t type  = e.type;
    uint16_t code  = e.code;
    int32_t  value = e.value;
    memcpy(buf + 8,  &type,  2);
    memcpy(buf + 10, &code,  2);
    memcpy(buf + 12, &value, 4);
    ::send(static_cast<fd_t>(fd_), reinterpret_cast<const char*>(buf), 16, 0);
}

int32_t VirtioInputTransport::next_tracking_id() {
    // Tracking IDs must be unique and monotonically increasing.
    // Wrap at 65535 to stay within 16-bit range expected by some drivers.
    if (++tid_counter_ > 65535) tid_counter_ = 1;
    return tid_counter_;
}

} // namespace avm::input
