#pragma once
#include <string>
#include "android_version.h"

namespace avm {

enum class GpuBackend {
    Vulkan,
    OpenGL,
    Software  // fallback, very slow
};

enum class HypervisorBackend {
    KVM,    // Linux
    HVF,    // macOS Hypervisor.framework
    AEHD,   // Windows (Android Emulator Hypervisor Driver)
    WHPX,   // Windows Hypervisor Platform
    HAXM,   // Intel HAXM (legacy)
    None    // software emulation
};

struct Config {
    // ---- VM resources ----
    std::string system_image_path;
    std::string data_partition_path;
    int         memory_mb   = 4096;
    int         vcpu_cores  = 4;

    // ---- Android version ----
    AndroidVersion  android_version    = AndroidVersion::Auto;
    uint8_t         android_api_level  = 0;  // filled by ImageManager

    // ---- Display ----
    int  display_width  = 1280;
    int  display_height = 720;
    int  target_fps     = 60;
    bool vsync_override = true;

    // ---- GPU ----
    GpuBackend gpu_backend = GpuBackend::Vulkan;

    // ---- Hypervisor ----
    bool              hardware_accel      = true;
    HypervisorBackend hypervisor_backend  = HypervisorBackend::None;

    // ---- Input ----
    std::string keymapper_profile;  // path to .json keymapper profile

    // ---- Boot (kernel-based images) ----
    std::string kernel_path;         // optional: path to kernel image (e.g. kernel-ranchu-64)
    std::string initrd_path;         // optional: path to ramdisk/initrd
    std::string kernel_cmdline;      // optional: kernel command-line arguments
    std::string pflash_code_path;    // optional: UEFI firmware (.fd); auto-detected if empty

    // ---- Networking ----
    bool enable_adb = true;
    int  adb_port   = 5554;
};

} // namespace avm
