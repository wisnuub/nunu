#pragma once
#include "config.h"
#include <memory>
#include <string>
#include <vector>
#include <functional>

#ifdef _WIN32
  #include <windows.h>
#else
  #include <sys/types.h>
#endif

namespace avm {

/**
 * VmManager — top-level VM lifecycle controller.
 *
 * Responsibilities:
 *  - Detect and initialize the best available hypervisor backend
 *  - Launch and configure QEMU with the provided Config
 *  - Manage QEMU lifecycle via QMP (QEMU Machine Protocol) socket
 *  - Wire up GPU forwarding (gfxstream) and input bridge
 *  - Manage start / stop / snapshot / restore lifecycle
 */
class VmManager {
public:
    explicit VmManager(const Config& config);
    ~VmManager();

    /**
     * initialize()
     *  - Validates the system image exists
     *  - Detects the best available hypervisor
     *  - Resolves the qemu-system-x86_64 binary path
     * @return true on success
     */
    bool initialize();

    /**
     * run() — launches QEMU and blocks until the VM exits.
     * Polls ADB readiness and prints status.
     * @return QEMU exit code
     */
    int run();

    /** Gracefully stop the VM via QMP 'quit' command. */
    void stop();

    /** Save a snapshot via QMP 'savevm'. */
    bool snapshot(const std::string& name);

    /** Restore a snapshot via QMP 'loadvm'. */
    bool restore_snapshot(const std::string& name);

    /** Returns true if the QEMU process is currently running. */
    bool is_running() const;

private:
    // --- Initialization helpers ---
    bool validate_image();
    bool detect_hypervisor();
    std::string find_qemu_binary();

    // --- QEMU launch ---
    std::vector<std::string> build_qemu_args();
    bool launch_qemu(const std::string& qemu_bin,
                     const std::vector<std::string>& args);

    // --- Android SDK emulator ---
    std::string find_android_emulator();
    std::string get_sdk_root(const std::string& emulator_path);
    bool setup_sdk_avd(const std::string& sdk_root,
                       const std::string& image_dir,
                       const std::string& avd_home,
                       const std::string& avd_name);
    std::vector<std::string> build_sdk_emulator_args(const std::string& avd_name);
    bool launch_with_env(const std::string& bin,
                         const std::vector<std::string>& args,
                         const std::vector<std::pair<std::string,std::string>>& env_vars);

    // --- QMP (QEMU Machine Protocol) ---
    bool     qmp_connect();
    void     qmp_disconnect();
    bool     qmp_send(const std::string& cmd);
    std::string qmp_recv();
    bool     qmp_execute(const std::string& cmd_json);

    // --- ADB ---
    bool wait_for_adb(int timeout_seconds = 60);
    bool adb_shell(const std::string& cmd, std::string& output);

    // --- Process management ---
    void wait_for_exit();
    void kill_process();

    Config config_;
    HypervisorBackend active_hypervisor_ = HypervisorBackend::None;

    // QMP socket
    int qmp_port_ = 4444;
    int qmp_sock_ = -1;

#ifdef _WIN32
    HANDLE qemu_process_ = INVALID_HANDLE_VALUE;
    HANDLE qemu_thread_  = INVALID_HANDLE_VALUE;
#else
    pid_t qemu_pid_ = -1;
#endif

    bool running_ = false;
};

} // namespace avm
