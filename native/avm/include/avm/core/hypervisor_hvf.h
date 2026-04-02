#pragma once
// Hypervisor.framework backend — macOS only (both Intel and Apple Silicon).
// On Apple Silicon (arm64) this runs ARM64 Android images at near-native speed.
// On Intel Mac it can run x86_64 Android images.
//
// Requires macOS 11+ and the Hypervisor entitlement:
//   com.apple.security.hypervisor = true  (in your .entitlements file)

#include "platform.h"
#if !AVM_OS_MACOS
#  error "hypervisor_hvf.h is macOS-only"
#endif

#include <cstdint>
#include <string>
#include <vector>
#include <functional>

namespace avm::core {

struct HvfConfig {
    uint64_t    ram_bytes      = 2ULL * 1024 * 1024 * 1024; // 2 GiB default
    int         vcpu_count     = 4;
    std::string kernel_path;    // path to ARM64 or x86_64 kernel image
    std::string initrd_path;    // optional initrd
    std::string disk_image;     // QCOW2 or raw Android system image
    std::string cmdline;        // kernel command line
};

class HvfHypervisor {
public:
    explicit HvfHypervisor(const HvfConfig& cfg);
    ~HvfHypervisor();

    // Create the VM and allocate guest RAM.
    bool create_vm();

    // Create and start all vCPUs on background threads.
    bool start_vcpus();

    // Stop all vCPUs and destroy the VM.
    void stop();

    bool is_running() const { return running_; }

    // Memory-mapped I/O callbacks — register device emulation handlers.
    using MmioReadCb  = std::function<uint64_t(uint64_t addr, int size)>;
    using MmioWriteCb = std::function<void    (uint64_t addr, uint64_t val, int size)>;
    void register_mmio(uint64_t base, uint64_t len,
                       MmioReadCb rd, MmioWriteCb wr);

private:
    void vcpu_thread(int index);
    void handle_exit(int vcpu_idx, void* exit_info);

    HvfConfig   cfg_;
    bool        running_  = false;
    void*       vm_       = nullptr;  // hv_vm_t (opaque to avoid Hypervisor.h in header)
    std::vector<void*> vcpus_;        // hv_vcpu_t per core

    struct MmioRegion {
        uint64_t base, len;
        MmioReadCb  rd;
        MmioWriteCb wr;
    };
    std::vector<MmioRegion> mmio_regions_;
};

} // namespace avm::core
