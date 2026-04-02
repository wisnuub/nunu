// hypervisor_hvf.mm  — Objective-C++ (required for Hypervisor.framework)
// Compiled only on macOS. Add to CMake via AVM_PLATFORM_MACOS guard.
#include "avm/core/hypervisor_hvf.h"
#include "avm/core/platform.h"

#import <Hypervisor/Hypervisor.h>
#import <Foundation/Foundation.h>
#include <sys/mman.h>
#include <pthread.h>
#include <stdexcept>
#include <thread>

namespace avm::core {

// ── Constructor / Destructor ─────────────────────────────────────────────────

HvfHypervisor::HvfHypervisor(const HvfConfig& cfg) : cfg_(cfg) {}

HvfHypervisor::~HvfHypervisor() { stop(); }

// ── VM creation ──────────────────────────────────────────────────────────────

bool HvfHypervisor::create_vm() {
    hv_return_t ret = hv_vm_create(nullptr);
    if (ret != HV_SUCCESS) {
        AVM_LOG_ERROR("hv_vm_create failed: 0x%x — check Hypervisor entitlement", ret);
        return false;
    }

    // Allocate guest RAM as a large anonymous mapping.
    void* ram = mmap(nullptr, cfg_.ram_bytes,
                     PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (ram == MAP_FAILED) {
        AVM_LOG_ERROR("mmap guest RAM failed");
        return false;
    }

    // Map guest RAM into IPA (Intermediate Physical Address) space starting at 0.
    ret = hv_vm_map(ram, 0x0, cfg_.ram_bytes,
                    HV_MEMORY_READ | HV_MEMORY_WRITE | HV_MEMORY_EXEC);
    if (ret != HV_SUCCESS) {
        AVM_LOG_ERROR("hv_vm_map failed: 0x%x", ret);
        munmap(ram, cfg_.ram_bytes);
        return false;
    }

    vm_ = reinterpret_cast<void*>(static_cast<uintptr_t>(1)); // mark as created
    AVM_LOG_INFO("HVF VM created — %.0f MiB guest RAM",
                 cfg_.ram_bytes / 1048576.0);
    return true;
}

// ── vCPU threads ─────────────────────────────────────────────────────────────

bool HvfHypervisor::start_vcpus() {
    if (!vm_) return false;
    running_ = true;
    for (int i = 0; i < cfg_.vcpu_count; ++i) {
        std::thread([this, i]{ vcpu_thread(i); }).detach();
    }
    AVM_LOG_INFO("HVF: started %d vCPU thread(s)", cfg_.vcpu_count);
    return true;
}

void HvfHypervisor::vcpu_thread(int index) {
    hv_vcpu_t    vcpu;
    hv_vcpu_exit_t* exit_info = nullptr;

    hv_return_t ret = hv_vcpu_create(&vcpu, &exit_info, nullptr);
    if (ret != HV_SUCCESS) {
        AVM_LOG_ERROR("vCPU %d: hv_vcpu_create failed 0x%x", index, ret);
        return;
    }
    vcpus_.push_back(reinterpret_cast<void*>(static_cast<uintptr_t>(vcpu)));

    // ── ARM64 vCPU register setup ─────────────────────────────────────────
    // Set PC to kernel entry point.
    // For a real Android boot, load the kernel from cfg_.kernel_path
    // and map it into guest RAM before starting vCPUs.
    // Here we set PC = 0x80000 which is the conventional ARM64 Linux kernel load addr.
    hv_vcpu_set_reg(vcpu, HV_REG_PC, 0x80000ULL);

    // x0 = physical address of device tree blob (required by ARM64 Linux).
    // In production: load DTB into guest RAM and pass its GPA here.
    hv_vcpu_set_reg(vcpu, HV_REG_X0, 0x0ULL);

    AVM_LOG_INFO("vCPU %d: entering run loop", index);

    while (running_) {
        ret = hv_vcpu_run(vcpu);
        if (ret != HV_SUCCESS) {
            AVM_LOG_WARN("vCPU %d: hv_vcpu_run error 0x%x", index, ret);
            break;
        }
        handle_exit(index, exit_info);
    }

    hv_vcpu_destroy(vcpu);
    AVM_LOG_INFO("vCPU %d: exited", index);
}

void HvfHypervisor::handle_exit(int vcpu_idx, void* raw) {
    hv_vcpu_exit_t* info = static_cast<hv_vcpu_exit_t*>(raw);
    switch (info->reason) {

    case HV_EXIT_REASON_VTIMER_ACTIVATED:
        // Virtual timer interrupt — inject to guest.
        hv_vcpu_set_vtimer_mask(
            static_cast<hv_vcpu_t>(reinterpret_cast<uintptr_t>(vcpus_[vcpu_idx])),
            false);
        break;

    case HV_EXIT_REASON_EXCEPTION: {
        uint32_t syndrome = info->exception.syndrome;
        uint8_t  ec       = (syndrome >> 26) & 0x3f; // Exception Class
        if (ec == 0x24 || ec == 0x25) {
            // Data / instruction abort — likely MMIO access.
            uint64_t ipa = info->exception.physical_address;
            for (auto& region : mmio_regions_) {
                if (ipa >= region.base && ipa < region.base + region.len) {
                    // Determine R/W from ISS bits [0] of syndrome.
                    bool is_write = !((syndrome >> 6) & 1);
                    if (is_write && region.wr)
                        region.wr(ipa, 0 /*TODO: extract write value from Xt*/, 4);
                    else if (!is_write && region.rd)
                        region.rd(ipa, 4);
                    return;
                }
            }
            AVM_LOG_WARN("vCPU %d: unhandled MMIO @ IPA 0x%llx", vcpu_idx, ipa);
        }
        break;
    }

    case HV_EXIT_REASON_CANCELED:
        // Requested stop.
        running_ = false;
        break;

    default:
        AVM_LOG_WARN("vCPU %d: unhandled exit reason %u", vcpu_idx, info->reason);
        break;
    }
}

void HvfHypervisor::stop() {
    running_ = false;
    if (vm_) {
        hv_vm_destroy();
        vm_ = nullptr;
    }
}

void HvfHypervisor::register_mmio(uint64_t base, uint64_t len,
                                    MmioReadCb rd, MmioWriteCb wr) {
    mmio_regions_.push_back({ base, len, std::move(rd), std::move(wr) });
}

} // namespace avm::core
