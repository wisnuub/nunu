#pragma once

// ── Platform capability flags ────────────────────────────────────────────────
// Include this header anywhere you need a compile-time platform check.
// All flags default to 0; the build system defines the appropriate ones.

#if defined(__APPLE__)
#  include <TargetConditionals.h>
#  define AVM_OS_MACOS   1
#  define AVM_OS_WINDOWS 0
#  define AVM_OS_LINUX   0
#  if defined(__aarch64__) || defined(__arm64__)
#    define AVM_ARCH_ARM64  1
#    define AVM_ARCH_X86_64 0
     // Apple Silicon: ARM64 guest images required.
     // Hypervisor.framework provides native vCPU support at near-native speed.
#  else
#    define AVM_ARCH_ARM64  0
#    define AVM_ARCH_X86_64 1
#  endif
#elif defined(_WIN32) || defined(_WIN64)
#  define AVM_OS_MACOS   0
#  define AVM_OS_WINDOWS 1
#  define AVM_OS_LINUX   0
#  define AVM_ARCH_ARM64  0
#  define AVM_ARCH_X86_64 1
#elif defined(__linux__)
#  define AVM_OS_MACOS   0
#  define AVM_OS_WINDOWS 0
#  define AVM_OS_LINUX   1
#  if defined(__aarch64__)
#    define AVM_ARCH_ARM64  1
#    define AVM_ARCH_X86_64 0
#  else
#    define AVM_ARCH_ARM64  0
#    define AVM_ARCH_X86_64 1
#  endif
#endif

// ── Hypervisor backend selection ─────────────────────────────────────────────
// Each platform uses a different virtualization API:
//   Linux x86   → KVM  (/dev/kvm)
//   macOS       → Hypervisor.framework  (Apple Silicon: ARM64 guest)
//   Windows x86 → WHPX (Windows Hypervisor Platform)

#if AVM_OS_LINUX
#  define AVM_HYPERVISOR_KVM   1
#  define AVM_HYPERVISOR_HVF   0
#  define AVM_HYPERVISOR_WHPX  0
#elif AVM_OS_MACOS
#  define AVM_HYPERVISOR_KVM   0
#  define AVM_HYPERVISOR_HVF   1
#  define AVM_HYPERVISOR_WHPX  0
#elif AVM_OS_WINDOWS
#  define AVM_HYPERVISOR_KVM   0
#  define AVM_HYPERVISOR_HVF   0
#  define AVM_HYPERVISOR_WHPX  1
#endif

// ── GPU renderer selection ────────────────────────────────────────────────────
// macOS:   MoltenVK (Vulkan → Metal translation layer)
// Windows: Native Vulkan or OpenGL
// Linux:   Native Vulkan or OpenGL

#if AVM_OS_MACOS
#  define AVM_RENDERER_MOLTENVK 1   // Vulkan API, Metal underneath
#  define AVM_RENDERER_METAL    0   // Direct Metal path (future)
#else
#  define AVM_RENDERER_MOLTENVK 0
#  define AVM_RENDERER_METAL    0
#endif

// ── Shared-memory path helpers ────────────────────────────────────────────────
#if AVM_OS_WINDOWS
#  define AVM_PATH_SEP          "\\\\"
#  define AVM_SOCKET_DIR        "\\\\.\\pipe\\"
#  define AVM_DEFAULT_KEYMAP_DIR "%APPDATA%\\AVM\\keymaps"
#elif AVM_OS_MACOS
#  define AVM_PATH_SEP          "/"
#  define AVM_SOCKET_DIR        "/tmp/"
#  define AVM_DEFAULT_KEYMAP_DIR "~/.avm/keymaps"
#else
#  define AVM_PATH_SEP          "/"
#  define AVM_SOCKET_DIR        "/tmp/"
#  define AVM_DEFAULT_KEYMAP_DIR "~/.avm/keymaps"
#endif

// ── Logging ───────────────────────────────────────────────────────────────────
#include <cstdio>
#define AVM_LOG_INFO(fmt,  ...) fprintf(stdout, "[AVM INFO]  " fmt "\n", ##__VA_ARGS__)
#define AVM_LOG_WARN(fmt,  ...) fprintf(stderr, "[AVM WARN]  " fmt "\n", ##__VA_ARGS__)
#define AVM_LOG_ERROR(fmt, ...) fprintf(stderr, "[AVM ERROR] " fmt "\n", ##__VA_ARGS__)
