#include "avm/core/vm_manager.h"
#include "avm/core/config.h"
#include "avm/core/platform.h"

#include <iostream>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <chrono>
#include <thread>
#include <cstring>
#include <array>

#if AVM_OS_WINDOWS
#  include <windows.h>
#  include <winsock2.h>
#  pragma comment(lib, "ws2_32.lib")
#else
#  include <unistd.h>
#  include <sys/wait.h>
#  include <sys/socket.h>
#  include <sys/stat.h>
#  include <netinet/in.h>
#  include <arpa/inet.h>
#  include <signal.h>
#endif

namespace avm {

// ============================================================
//  Construction / Destruction
// ============================================================

VmManager::VmManager(const Config& config)
    : config_(config) {}

VmManager::~VmManager() {
    if (is_running()) stop();
    qmp_disconnect();
}

// ============================================================
//  Public API
// ============================================================

bool VmManager::initialize() {
    std::cout << "[VmManager] Initializing...\n";

    if (!validate_image()) {
        std::cerr << "[VmManager] Image validation failed.\n";
        return false;
    }

    if (config_.hardware_accel) {
        if (!detect_hypervisor()) {
            std::cerr << "[VmManager] WARNING: No hardware hypervisor found.\n"
                      << "            Falling back to software emulation (very slow).\n";
            config_.hardware_accel = false;
            active_hypervisor_ = HypervisorBackend::None;
        }
    }

    std::cout << "[VmManager] Initialization complete.\n";
    return true;
}

int VmManager::run() {
    // ── Try Android SDK emulator first ──────────────────────────────────────
#if !AVM_OS_WINDOWS
    {
        std::string sdk_emu = find_android_emulator();
        if (!sdk_emu.empty()) {
            std::string sdk_root = get_sdk_root(sdk_emu);

            // Determine the image directory
            std::string image_dir = config_.system_image_path;
#if !AVM_OS_WINDOWS
            {
                struct stat st;
                if (stat(image_dir.c_str(), &st) == 0 && !S_ISDIR(st.st_mode)) {
                    // Strip filename — use parent directory
                    auto slash = image_dir.rfind('/');
                    if (slash != std::string::npos)
                        image_dir = image_dir.substr(0, slash);
                }
            }
#endif

            // AVD home: prefer ~/.avd
            std::string avd_home;
            const char* home_env = getenv("HOME");
            if (home_env) avd_home = std::string(home_env) + "/.avd";
            else avd_home = "/tmp/avm_avd";

            const std::string avd_name = "avm_nunu";

            std::cout << "[VmManager] Android SDK emulator found: " << sdk_emu << "\n";
            std::cout << "[VmManager] SDK root: " << sdk_root << "\n";
            std::cout << "[VmManager] Image dir: " << image_dir << "\n";

            if (!setup_sdk_avd(sdk_root, image_dir, avd_home, avd_name)) {
                std::cerr << "[VmManager] AVD setup failed — falling back to QEMU.\n";
            } else {
                auto args = build_sdk_emulator_args(avd_name);

                std::cout << "[VmManager] Launching Android emulator:\n  " << sdk_emu;
                for (auto& a : args) std::cout << " " << a;
                std::cout << "\n\n";

                std::vector<std::pair<std::string,std::string>> env_vars = {
                    {"ANDROID_SDK_ROOT",   sdk_root},
                    {"ANDROID_HOME",       sdk_root},
                    {"ANDROID_AVD_HOME",   avd_home},
                };

                if (!launch_with_env(sdk_emu, args, env_vars)) {
                    std::cerr << "[VmManager] Failed to launch Android emulator.\n";
                    return 1;
                }

                running_ = true;
                std::cout << "[VmManager] Android emulator started.\n";

                if (config_.enable_adb) {
                    std::cout << "[VmManager] Waiting for ADB (port " << config_.adb_port << ")...\n";
                    if (wait_for_adb(120))
                        std::cout << "[VmManager] ADB ready.\n";
                    else
                        std::cerr << "[VmManager] ADB timeout (VM may still be booting).\n";
                }

                std::cout << "[VmManager] VM running. Ctrl+C to stop.\n";
                wait_for_exit();
                running_ = false;
                std::cout << "[VmManager] Android emulator exited.\n";
                return 0;
            }
        } else {
            std::cout << "[VmManager] Android SDK emulator not found — using QEMU.\n";
        }
    }
#endif

    // ── Fall back to standard QEMU ───────────────────────────────────────────
    std::string qemu_bin = find_qemu_binary();
    if (qemu_bin.empty()) {
        std::cerr << "[VmManager] QEMU not found. Install it:\n"
#if AVM_OS_MACOS
                  << "            brew install qemu\n"
                  << "  Note: On Apple Silicon, use qemu-system-aarch64 (ARM64 guest).\n"
#elif AVM_OS_WINDOWS
                  << "            https://www.qemu.org/download/#windows\n"
#else
                  << "            sudo apt install qemu-system-x86 (x86)\n"
                  << "            sudo apt install qemu-system-arm  (ARM64)\n"
#endif
                  ;
        return 1;
    }
    std::cout << "[VmManager] Using QEMU: " << qemu_bin << "\n";

    auto args = build_qemu_args();

    std::cout << "[VmManager] Command line:\n  " << qemu_bin;
    for (auto& a : args) std::cout << " " << a;
    std::cout << "\n\n";

    if (!launch_qemu(qemu_bin, args)) {
        std::cerr << "[VmManager] Failed to launch QEMU.\n";
        return 1;
    }

    running_ = true;
    std::cout << "[VmManager] QEMU started.\n";
    std::this_thread::sleep_for(std::chrono::seconds(2));

    if (qmp_connect()) {
        std::cout << "[VmManager] QMP connected on port " << qmp_port_ << ".\n";
        qmp_execute("{\"execute\":\"qmp_capabilities\"}");
    } else {
        std::cerr << "[VmManager] QMP connection failed (non-fatal).\n";
    }

    if (config_.enable_adb) {
        std::cout << "[VmManager] Waiting for ADB (port " << config_.adb_port << ")...\n";
        if (wait_for_adb(60))
            std::cout << "[VmManager] ADB ready.\n";
        else
            std::cerr << "[VmManager] ADB timeout (VM may still be booting).\n";
    }

    std::cout << "[VmManager] VM running. Ctrl+C to stop.\n";
    wait_for_exit();
    running_ = false;
    std::cout << "[VmManager] QEMU exited.\n";
    return 0;
}

void VmManager::stop() {
    if (!is_running()) return;
    if (qmp_sock_ >= 0) {
        qmp_execute("{\"execute\":\"quit\"}");
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    kill_process();
    running_ = false;
}

bool VmManager::snapshot(const std::string& name) {
    if (!is_running() || qmp_sock_ < 0) return false;
    std::string cmd = "{\"execute\":\"savevm\",\"arguments\":{\"name\":\"" + name + "\"}}";
    return qmp_execute(cmd);
}

bool VmManager::restore_snapshot(const std::string& name) {
    if (!is_running() || qmp_sock_ < 0) return false;
    std::string cmd = "{\"execute\":\"loadvm\",\"arguments\":{\"name\":\"" + name + "\"}}";
    return qmp_execute(cmd);
}

bool VmManager::is_running() const {
#if AVM_OS_WINDOWS
    if (qemu_process_ == INVALID_HANDLE_VALUE) return false;
    DWORD exit_code;
    GetExitCodeProcess(qemu_process_, &exit_code);
    return exit_code == STILL_ACTIVE;
#else
    if (qemu_pid_ <= 0) return false;
    return (waitpid(qemu_pid_, nullptr, WNOHANG) == 0);
#endif
}

// ============================================================
//  Image Validation
// ============================================================

bool VmManager::validate_image() {
    if (config_.system_image_path.empty()) {
        std::cerr << "[VmManager] No system image (--image).\n";
        return false;
    }
#if !AVM_OS_WINDOWS
    struct stat st;
    if (stat(config_.system_image_path.c_str(), &st) != 0) {
        std::cerr << "[VmManager] Image not found: " << config_.system_image_path << "\n";
        return false;
    }
    if (S_ISDIR(st.st_mode)) {
        // Directory mode — Android SDK image directory (contains system.img, kernel-ranchu, etc.)
        std::cout << "[VmManager] Image dir OK: " << config_.system_image_path << "\n";
        return true;
    }
    std::cout << "[VmManager] Image file OK: " << config_.system_image_path
              << " (" << (st.st_size / 1024 / 1024) << " MB)\n";
    return true;
#else
    std::ifstream f(config_.system_image_path);
    if (!f.good()) {
        std::cerr << "[VmManager] Image not found: " << config_.system_image_path << "\n";
        return false;
    }
    f.seekg(0, std::ios::end);
    auto size = f.tellg();
    if (size <= 0) {
        std::cerr << "[VmManager] Image appears empty.\n";
        return false;
    }
    std::cout << "[VmManager] Image OK: " << config_.system_image_path
              << " (" << (size / 1024 / 1024) << " MB)\n";
    return true;
#endif
}

// ============================================================
//  Hypervisor Detection
// ============================================================

bool VmManager::detect_hypervisor() {
#if AVM_OS_WINDOWS
    // Try AEHD first
    HANDLE aehd = CreateFileA("\\\\.\\aehd",
                               GENERIC_READ | GENERIC_WRITE, 0,
                               nullptr, OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL, nullptr);
    if (aehd != INVALID_HANDLE_VALUE) {
        CloseHandle(aehd);
        active_hypervisor_ = HypervisorBackend::AEHD;
        std::cout << "[VmManager] Hypervisor: AEHD\n";
        return true;
    }
    HMODULE whvdll = LoadLibraryA("WinHvPlatform.dll");
    if (whvdll) {
        FreeLibrary(whvdll);
        active_hypervisor_ = HypervisorBackend::WHPX;
        std::cout << "[VmManager] Hypervisor: WHPX\n";
        return true;
    }
    std::cerr << "[VmManager] No hypervisor on Windows.\n"
              << "  Enable 'Windows Hypervisor Platform' in Windows Features.\n";
    return false;

#elif AVM_OS_MACOS
    // Hypervisor.framework is always present on macOS 11+.
    // The binary must be signed with com.apple.security.hypervisor entitlement
    // (see avm.entitlements and docs/building.md).
    active_hypervisor_ = HypervisorBackend::HVF;
    std::cout << "[VmManager] Hypervisor: Apple Hypervisor.framework";
#  if AVM_ARCH_ARM64
    std::cout << " (Apple Silicon — ARM64 guest required)";
#  else
    std::cout << " (Intel Mac — x86_64 guest)";
#  endif
    std::cout << "\n";
    return true;

#else // Linux
    std::ifstream kvm("/dev/kvm");
    if (kvm.good()) {
        active_hypervisor_ = HypervisorBackend::KVM;
        std::cout << "[VmManager] Hypervisor: KVM\n";
        return true;
    }
    std::cerr << "[VmManager] /dev/kvm not accessible.\n"
              << "  sudo modprobe kvm_intel  (or kvm_amd)\n"
              << "  sudo usermod -aG kvm $USER\n";
    return false;
#endif
}

// ============================================================
//  QEMU Binary Resolution
// ============================================================

std::string VmManager::find_qemu_binary() {
    // On Apple Silicon we need the ARM64 QEMU binary.
    // On all other platforms we use the x86_64 binary.
#if AVM_OS_MACOS && AVM_ARCH_ARM64
    const std::vector<std::string> candidates = {
        "qemu-system-aarch64",
        "/opt/homebrew/bin/qemu-system-aarch64",
        "/usr/local/bin/qemu-system-aarch64",
    };
#elif AVM_OS_WINDOWS
    const std::vector<std::string> candidates = {
        "qemu-system-x86_64.exe",
        "C:\\Program Files\\qemu\\qemu-system-x86_64.exe",
        "C:\\qemu\\qemu-system-x86_64.exe",
    };
#else
    const std::vector<std::string> candidates = {
        "qemu-system-x86_64",
        "/usr/bin/qemu-system-x86_64",
        "/usr/local/bin/qemu-system-x86_64",
        "/opt/homebrew/bin/qemu-system-x86_64",
        "/opt/local/bin/qemu-system-x86_64",
    };
#endif

    for (auto& path : candidates) {
#if AVM_OS_WINDOWS
        if (GetFileAttributesA(path.c_str()) != INVALID_FILE_ATTRIBUTES)
            return path;
#else
        struct stat st;
        if (stat(path.c_str(), &st) == 0 && (st.st_mode & S_IXUSR))
            return path;
#endif
    }
    return {};
}

// ============================================================
//  QEMU Argument Builder
// ============================================================

std::vector<std::string> VmManager::build_qemu_args() {
    std::vector<std::string> args;

    // --- Acceleration ---
    if (config_.hardware_accel) {
#if AVM_OS_WINDOWS
        if (active_hypervisor_ == HypervisorBackend::AEHD) {
            args.push_back("-accel"); args.push_back("aehd");
        } else {
            args.push_back("-accel"); args.push_back("whpx");
        }
#elif AVM_OS_MACOS
        args.push_back("-accel"); args.push_back("hvf");
        args.push_back("-cpu");   args.push_back("host");
#else
        args.push_back("-accel"); args.push_back("kvm");
        args.push_back("-cpu");   args.push_back("host");
#endif
    } else {
        args.push_back("-accel"); args.push_back("tcg");
        args.push_back("-cpu");   args.push_back("max");
    }

    // --- Machine type ---
    // Apple Silicon uses virt (ARM64); x86 uses q35
#if AVM_OS_MACOS && AVM_ARCH_ARM64
    args.push_back("-machine"); args.push_back("virt,highmem=off");
#else
    args.push_back("-machine"); args.push_back("q35");
#endif

    // --- Memory ---
    args.push_back("-m");
    args.push_back(std::to_string(config_.memory_mb) + "M");

    // --- vCPUs ---
    args.push_back("-smp");
    args.push_back(std::to_string(config_.vcpu_cores));

    // --- System image ---
    args.push_back("-drive");
    args.push_back("file=" + config_.system_image_path +
                   ",format=raw,if=virtio,readonly=on");

    // --- Data partition ---
    if (!config_.data_partition_path.empty()) {
        args.push_back("-drive");
        args.push_back("file=" + config_.data_partition_path +
                       ",format=raw,if=virtio");
    }

    // --- UEFI firmware (ARM64 virt machine requires this) ---
#if AVM_OS_MACOS && AVM_ARCH_ARM64
    {
        std::string pflash = config_.pflash_code_path;
        if (pflash.empty()) {
            // Auto-detect Homebrew QEMU firmware location
            const char* candidates[] = {
                "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
                "/usr/local/share/qemu/edk2-aarch64-code.fd",
                "/usr/share/qemu/edk2-aarch64-code.fd",
            };
            for (auto* p : candidates) {
                struct stat st;
                if (stat(p, &st) == 0) { pflash = p; break; }
            }
        }
        if (!pflash.empty()) {
            args.push_back("-bios"); args.push_back(pflash);
        }
    }
#endif

    // --- Kernel / initrd (used with Android goldfish/ranchu images) ---
    if (!config_.kernel_path.empty()) {
        args.push_back("-kernel"); args.push_back(config_.kernel_path);
    }
    if (!config_.initrd_path.empty()) {
        args.push_back("-initrd"); args.push_back(config_.initrd_path);
    }
    if (!config_.kernel_cmdline.empty()) {
        args.push_back("-append"); args.push_back(config_.kernel_cmdline);
    }

    // --- GPU / Display ---
    // Homebrew QEMU on macOS ships with Cocoa display (not SDL).
    // SDL is available on Windows/Linux builds.
#if AVM_OS_MACOS
    args.push_back("-device");  args.push_back("virtio-gpu-pci");
    args.push_back("-display"); args.push_back("cocoa,show-cursor=on");
#elif AVM_OS_WINDOWS
    args.push_back("-device");  args.push_back("virtio-gpu-gl-pci");
    args.push_back("-display"); args.push_back("sdl,gl=on");
#else
    if (config_.gpu_backend != GpuBackend::Software) {
        args.push_back("-device");  args.push_back("virtio-gpu-gl-pci");
        args.push_back("-display"); args.push_back("sdl,gl=on");
    } else {
        args.push_back("-device");  args.push_back("virtio-vga");
        args.push_back("-display"); args.push_back("sdl");
    }
#endif

    // --- Input ---
    args.push_back("-device"); args.push_back("virtio-mouse-pci");
    args.push_back("-device"); args.push_back("virtio-keyboard-pci");
    args.push_back("-device"); args.push_back("virtio-tablet-pci");
    args.push_back("-usb");

    // --- Network + ADB forward ---
    args.push_back("-netdev");
    args.push_back("user,id=net0,hostfwd=tcp::" +
                   std::to_string(config_.adb_port) + "-:5555");
    args.push_back("-device"); args.push_back("virtio-net-pci,netdev=net0");

    // --- QMP ---
    args.push_back("-qmp");
    args.push_back("tcp:127.0.0.1:" + std::to_string(qmp_port_) +
                   ",server=on,wait=off");

    // --- Serial ---
    args.push_back("-serial");  args.push_back("stdio");
    args.push_back("-monitor"); args.push_back("none");

    return args;
}

// ============================================================
//  Process Launch
// ============================================================

bool VmManager::launch_qemu(const std::string& qemu_bin,
                             const std::vector<std::string>& args) {
#if AVM_OS_WINDOWS
    std::ostringstream cmd;
    cmd << "\"" << qemu_bin << "\"";
    for (auto& a : args)
        cmd << (a.find(' ') != std::string::npos ? " \"" + a + "\"" : " " + a);
    std::string cmd_str = cmd.str();
    STARTUPINFOA si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    if (!CreateProcessA(nullptr, cmd_str.data(), nullptr, nullptr,
                        FALSE, 0, nullptr, nullptr, &si, &pi)) {
        std::cerr << "[VmManager] CreateProcess failed: " << GetLastError() << "\n";
        return false;
    }
    qemu_process_ = pi.hProcess;
    qemu_thread_  = pi.hThread;
    return true;
#else
    pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "[VmManager] fork() failed: " << strerror(errno) << "\n";
        return false;
    }
    if (pid == 0) {
        std::vector<const char*> argv;
        argv.push_back(qemu_bin.c_str());
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execvp(qemu_bin.c_str(), const_cast<char* const*>(argv.data()));
        std::cerr << "[VmManager] execvp failed: " << strerror(errno) << "\n";
        _exit(1);
    }
    qemu_pid_ = pid;
    std::cout << "[VmManager] QEMU PID: " << qemu_pid_ << "\n";
    return true;
#endif
}

void VmManager::wait_for_exit() {
#if AVM_OS_WINDOWS
    if (qemu_process_ != INVALID_HANDLE_VALUE)
        WaitForSingleObject(qemu_process_, INFINITE);
#else
    if (qemu_pid_ > 0) { int s; waitpid(qemu_pid_, &s, 0); }
#endif
}

void VmManager::kill_process() {
#if AVM_OS_WINDOWS
    if (qemu_process_ != INVALID_HANDLE_VALUE) {
        TerminateProcess(qemu_process_, 0);
        CloseHandle(qemu_process_); CloseHandle(qemu_thread_);
        qemu_process_ = qemu_thread_ = INVALID_HANDLE_VALUE;
    }
#else
    if (qemu_pid_ > 0) {
        kill(qemu_pid_, SIGTERM);
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        if (is_running()) kill(qemu_pid_, SIGKILL);
        waitpid(qemu_pid_, nullptr, 0);
        qemu_pid_ = -1;
    }
#endif
}

// ============================================================
//  QMP
// ============================================================

bool VmManager::qmp_connect() {
#if AVM_OS_WINDOWS
    WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa);
    qmp_sock_ = (int)socket(AF_INET, SOCK_STREAM, 0);
#else
    qmp_sock_ = socket(AF_INET, SOCK_STREAM, 0);
#endif
    if (qmp_sock_ < 0) return false;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(qmp_port_);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    for (int i = 0; i < 5; ++i) {
        if (connect(qmp_sock_, (sockaddr*)&addr, sizeof(addr)) == 0) {
            qmp_recv(); // consume greeting
            return true;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
#if AVM_OS_WINDOWS
    closesocket(qmp_sock_);
#else
    close(qmp_sock_);
#endif
    qmp_sock_ = -1;
    return false;
}

void VmManager::qmp_disconnect() {
    if (qmp_sock_ < 0) return;
#if AVM_OS_WINDOWS
    closesocket(qmp_sock_); WSACleanup();
#else
    close(qmp_sock_);
#endif
    qmp_sock_ = -1;
}

bool VmManager::qmp_send(const std::string& cmd) {
    if (qmp_sock_ < 0) return false;
    std::string msg = cmd + "\n";
    return send(qmp_sock_, msg.c_str(), (int)msg.size(), 0) > 0;
}

std::string VmManager::qmp_recv() {
    if (qmp_sock_ < 0) return {};
    std::array<char,4096> buf{};
    int n = recv(qmp_sock_, buf.data(), (int)buf.size()-1, 0);
    if (n <= 0) return {};
    buf[n] = '\0';
    return { buf.data(), (size_t)n };
}

bool VmManager::qmp_execute(const std::string& cmd_json) {
    if (!qmp_send(cmd_json)) return false;
    std::string resp = qmp_recv();
    bool ok = resp.find("\"return\"") != std::string::npos;
    if (!ok) std::cerr << "[QMP] " << resp << "\n";
    return ok;
}

// ============================================================
//  ADB
// ============================================================

bool VmManager::wait_for_adb(int timeout_seconds) {
    system(("adb connect 127.0.0.1:" + std::to_string(config_.adb_port)).c_str());
    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::seconds(timeout_seconds);
    while (std::chrono::steady_clock::now() < deadline) {
        std::string out;
        if (adb_shell("getprop sys.boot_completed", out)) {
            out.erase(0, out.find_first_not_of(" \t\n\r"));
            out.erase(out.find_last_not_of(" \t\n\r") + 1);
            if (out == "1") return true;
        }
        std::cout << "[ADB] Waiting for Android to boot...\n";
        std::this_thread::sleep_for(std::chrono::seconds(3));
    }
    return false;
}

bool VmManager::adb_shell(const std::string& cmd, std::string& output) {
    std::string full = "adb -s 127.0.0.1:" + std::to_string(config_.adb_port) +
                       " shell " + cmd + " 2>/dev/null";
#if AVM_OS_WINDOWS
    FILE* pipe = _popen(full.c_str(), "r");
#else
    FILE* pipe = popen(full.c_str(), "r");
#endif
    if (!pipe) return false;
    std::array<char,256> buf{};
    output.clear();
    while (fgets(buf.data(), (int)buf.size(), pipe)) output += buf.data();
#if AVM_OS_WINDOWS
    _pclose(pipe);
#else
    pclose(pipe);
#endif
    return true;
}

// ============================================================
//  Android SDK Emulator
// ============================================================

#if !AVM_OS_WINDOWS
std::string VmManager::find_android_emulator() {
    std::vector<std::string> candidates;

    // Check env vars first
    const char* sdk_env = getenv("ANDROID_SDK_ROOT");
    if (!sdk_env) sdk_env = getenv("ANDROID_HOME");
    if (sdk_env)
        candidates.push_back(std::string(sdk_env) + "/emulator/emulator");

    // Check home dir (macOS standard location)
    const char* home = getenv("HOME");
    if (home) {
        candidates.push_back(std::string(home) + "/Library/Android/sdk/emulator/emulator");
        candidates.push_back(std::string(home) + "/Android/Sdk/emulator/emulator");
    }

    // Homebrew android-commandlinetools location
    candidates.push_back("/opt/homebrew/share/android-commandlinetools/emulator/emulator");
    candidates.push_back("/usr/local/share/android-commandlinetools/emulator/emulator");

    for (auto& p : candidates) {
        struct stat st;
        if (stat(p.c_str(), &st) == 0 && (st.st_mode & S_IXUSR))
            return p;
    }
    return {};
}

std::string VmManager::get_sdk_root(const std::string& emulator_path) {
    // emulator_path is like /foo/bar/sdk/emulator/emulator
    // SDK root is two levels up
    auto slash1 = emulator_path.rfind('/');
    if (slash1 == std::string::npos) return {};
    auto slash2 = emulator_path.rfind('/', slash1 - 1);
    if (slash2 == std::string::npos) return emulator_path.substr(0, slash1);
    return emulator_path.substr(0, slash2);
}

static void write_file(const std::string& path, const std::string& content) {
    std::ofstream f(path);
    f << content;
}

static void mkdir_p(const std::string& path) {
    // Create directory and parents (simple recursive approach)
    for (size_t i = 1; i <= path.size(); ++i) {
        if (i == path.size() || path[i] == '/') {
            std::string sub = path.substr(0, i);
            mkdir(sub.c_str(), 0755);
        }
    }
}

bool VmManager::setup_sdk_avd(const std::string& sdk_root,
                               const std::string& image_dir,
                               const std::string& avd_home,
                               const std::string& avd_name) {
    // Compute image.sysdir.1 — path relative to sdk_root
    std::string rel_image_dir = image_dir;
    if (image_dir.find(sdk_root) == 0) {
        rel_image_dir = image_dir.substr(sdk_root.size());
        // Strip leading slash
        if (!rel_image_dir.empty() && rel_image_dir[0] == '/')
            rel_image_dir = rel_image_dir.substr(1);
        // Ensure trailing slash
        if (!rel_image_dir.empty() && rel_image_dir.back() != '/')
            rel_image_dir += '/';
    }

    // Paths
    std::string avd_dir    = avd_home + "/" + avd_name + ".avd";
    std::string ini_path   = avd_home + "/" + avd_name + ".ini";
    std::string cfg_path   = avd_dir + "/config.ini";

    mkdir_p(avd_home);
    mkdir_p(avd_dir);

    // Write top-level .ini
    std::ostringstream ini;
    ini << "avd.ini.encoding=UTF-8\n"
        << "path=" << avd_dir << "\n"
        << "path.rel=avd/" << avd_name << ".avd\n"
        << "target=android-34\n";
    write_file(ini_path, ini.str());

    // Write config.ini
    // Landscape 1920×1080 @ 240 dpi — games expect landscape + readable DPI
    std::ostringstream cfg;
    cfg << "AvdId=" << avd_name << "\n"
        << "PlayStore.enabled=true\n"
        << "abi.type=arm64-v8a\n"
        << "avd.ini.encoding=UTF-8\n"
        << "hw.cpu.arch=arm64\n"
        << "hw.device.name=pixel_6\n"
        << "hw.gpu.enabled=yes\n"
        << "hw.gpu.mode=auto\n"
        << "hw.lcd.width=1920\n"
        << "hw.lcd.height=1080\n"
        << "hw.lcd.density=240\n"
        << "hw.initialOrientation=landscape\n"
        << "hw.cpu.ncore=" << config_.vcpu_cores << "\n"
        << "hw.ramSize=" << config_.memory_mb << "\n"
        << "image.sysdir.1=" << rel_image_dir << "\n"
        << "showDeviceFrame=no\n"
        << "skin.dynamic=yes\n"
        << "skin.name=1920x1080\n"
        << "skin.path=_no_skin\n"
        << "tag.display=Google Play\n"
        << "tag.id=google_apis_playstore\n";
    write_file(cfg_path, cfg.str());

    std::cout << "[VmManager] AVD written to: " << avd_home << "\n";
    std::cout << "[VmManager] image.sysdir.1=" << rel_image_dir << "\n";
    return true;
}

std::vector<std::string> VmManager::build_sdk_emulator_args(const std::string& avd_name) {
    std::vector<std::string> args;
    args.push_back("-avd");         args.push_back(avd_name);
    args.push_back("-no-boot-anim");
    args.push_back("-no-audio");
    args.push_back("-no-metrics");

    // Use host GPU (Metal on macOS, ANGLE on Windows) instead of software lavapipe.
    // Without this the emulator defaults to lavapipe which is CPU-bound and causes freezes.
    args.push_back("-gpu");         args.push_back("host");

    // Persist the shader cache across sessions so shaders don't recompile every boot.
    // The cache lives in the AVD home next to the AVD data directory.
    const char* home = getenv("HOME");
    if (home) {
        std::string cache_dir = std::string(home) + "/.avd/shader_cache";
        args.push_back("-feature-flags");
        args.push_back("GLESDynamicVersion,EncryptUserData=off,Vulkan,VulkanNullOptionalDeviceExtensions,VulkanIgnoredHandles");
        args.push_back("-cache");
        args.push_back(cache_dir);
    }

    // -port sets the console port; ADB connects on port+1 (serial = emulator-5554, ADB = 5555)
    args.push_back("-port");        args.push_back("5554");
    return args;
}

bool VmManager::launch_with_env(const std::string& bin,
                                 const std::vector<std::string>& args,
                                 const std::vector<std::pair<std::string,std::string>>& env_vars) {
    pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "[VmManager] fork() failed: " << strerror(errno) << "\n";
        return false;
    }
    if (pid == 0) {
        // Child: set env vars then exec
        for (auto& [k, v] : env_vars)
            setenv(k.c_str(), v.c_str(), 1);

        std::vector<const char*> argv;
        argv.push_back(bin.c_str());
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execvp(bin.c_str(), const_cast<char* const*>(argv.data()));
        std::cerr << "[VmManager] execvp failed: " << strerror(errno) << "\n";
        _exit(1);
    }
    qemu_pid_ = pid;
    std::cout << "[VmManager] Emulator PID: " << pid << "\n";
    return true;
}
#else
// Windows stubs — SDK emulator path is Unix-only for now
std::string VmManager::find_android_emulator() { return {}; }
std::string VmManager::get_sdk_root(const std::string&) { return {}; }
bool VmManager::setup_sdk_avd(const std::string&, const std::string&,
                               const std::string&, const std::string&) { return false; }
std::vector<std::string> VmManager::build_sdk_emulator_args(const std::string&) { return {}; }
bool VmManager::launch_with_env(const std::string&, const std::vector<std::string>&,
                                 const std::vector<std::pair<std::string,std::string>>&) { return false; }
#endif

} // namespace avm
