#include "avm/input/adb_injector.h"
#include <sstream>
#include <cstring>
#include <stdexcept>
#include <algorithm>
#include <cmath>

#ifdef _WIN32
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  pragma comment(lib, "ws2_32.lib")
   using sock_t = SOCKET;
   static constexpr sock_t kInvalidSock = INVALID_SOCKET;
#else
#  include <sys/socket.h>
#  include <netinet/in.h>
#  include <arpa/inet.h>
#  include <unistd.h>
   using sock_t = int;
   static constexpr sock_t kInvalidSock = -1;
#endif

namespace avm::input {

AdbInjector::AdbInjector(const Config& cfg) : cfg_(cfg) {
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
}

AdbInjector::~AdbInjector() {
    disconnect();
#ifdef _WIN32
    WSACleanup();
#endif
}

// ── Connection ─────────────────────────────────────────────────────────────────

bool AdbInjector::connect() {
    sock_t s = ::socket(AF_INET, SOCK_STREAM, 0);
    if (s == kInvalidSock) return false;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(static_cast<uint16_t>(cfg_.port));
    inet_pton(AF_INET, cfg_.host.c_str(), &addr.sin_addr);

    if (::connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
#ifdef _WIN32
        closesocket(s);
#else
        ::close(s);
#endif
        return false;
    }
    sock_      = static_cast<intptr_t>(s);
    connected_ = true;
    return true;
}

void AdbInjector::disconnect() {
    if (!connected_) return;
    sock_t s = static_cast<sock_t>(sock_);
#ifdef _WIN32
    closesocket(s);
#else
    ::close(s);
#endif
    connected_ = false;
    sock_      = -1;
}

// ── ADB protocol helpers ────────────────────────────────────────────────────
// ADB wire protocol: 4-byte hex length prefix + ASCII payload.
std::string AdbInjector::shell(const std::string& cmd) {
    if (!connected_) return {};
    sock_t s = static_cast<sock_t>(sock_);

    // Target specific emulator: host-serial:emulator-<port>
    std::string target = "host:transport:emulator-" + std::to_string(cfg_.serial_port);
    auto send_msg = [&](const std::string& msg) {
        char hdr[5];
        snprintf(hdr, sizeof(hdr), "%04X", static_cast<unsigned>(msg.size()));
        std::string packet = std::string(hdr) + msg;
        ::send(s, packet.c_str(), static_cast<int>(packet.size()), 0);
    };
    auto read_status = [&]() -> bool {
        char buf[4] = {};
        ::recv(s, buf, 4, MSG_WAITALL);
        return strncmp(buf, "OKAY", 4) == 0;
    };

    send_msg(target);
    if (!read_status()) return {};

    std::string shell_cmd = "shell:" + cmd;
    send_msg(shell_cmd);
    if (!read_status()) return {};

    // Read response until connection closes.
    std::string result;
    char buf[512];
    int  n;
    while ((n = ::recv(s, buf, sizeof(buf), 0)) > 0)
        result.append(buf, n);
    return result;
}

// ── Touch injection ─────────────────────────────────────────────────────────────

std::string AdbInjector::touch_cmd(const TouchEvent& e) const {
    int px = static_cast<int>(e.x * cfg_.screen_w);
    int py = static_cast<int>(e.y * cfg_.screen_h);
    std::ostringstream cmd;
    switch (e.type) {
    case TouchEvent::Type::DOWN:
        cmd << "input touchscreen swipe " << px << " " << py
            << " " << px << " " << py << " 1";
        break;
    case TouchEvent::Type::MOVE:
        // For MOVE we re-issue a swipe from the last known pos.
        {
            int ox = static_cast<int>(slots_[e.slot].x * cfg_.screen_w);
            int oy = static_cast<int>(slots_[e.slot].y * cfg_.screen_h);
            cmd << "input touchscreen swipe " << ox << " " << oy
                << " " << px << " " << py << " 16";
        }
        break;
    case TouchEvent::Type::UP:
        cmd << "input touchscreen tap " << px << " " << py;
        break;
    }
    return cmd.str();
}

void AdbInjector::inject_touch(const TouchEvent& e) {
    if (!connected_) return;
    if (e.slot >= 0 && e.slot < 10) {
        slots_[e.slot].x = e.x;
        slots_[e.slot].y = e.y;
        slots_[e.slot].active = (e.type != TouchEvent::Type::UP);
    }
    shell(touch_cmd(e));
}

// ── Key injection ──────────────────────────────────────────────────────────────────

std::string AdbInjector::key_cmd(const KeyEvent& e) const {
    std::ostringstream cmd;
    cmd << "input keyevent";
    if (e.action == KeyEvent::Action::DOWN) cmd << " --longpress";
    cmd << " " << e.android_keycode;
    return cmd.str();
}

void AdbInjector::inject_key(const KeyEvent& e) {
    if (!connected_) return;
    shell(key_cmd(e));
}

// ── Foreground package query ────────────────────────────────────────────────────────
// Returns the package name of the current foreground activity.
// Used by the emulator core to auto-switch keymapper profiles.
std::string AdbInjector::foreground_package() {
    std::string out = shell(
        "dumpsys activity activities | grep mResumedActivity | head -1");
    // Output format: "mResumedActivity: ActivityRecord{... pkg=com.example.app ...}"
    auto pos = out.find("pkg=");
    if (pos == std::string::npos) return {};
    pos += 4;
    auto end = out.find_first_of(" }\n", pos);
    return out.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
}

} // namespace avm::input
