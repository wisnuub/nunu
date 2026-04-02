# AVM — Android Virtual Machine

> The performance emulator core powering **[nunu](https://github.com/wisnuub/nemu)** — near-native Android gaming on Mac, Linux, and Windows via hardware virtualization.

[![License: MIT](https://img.shields.io/badge/License-MIT-teal.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#prerequisites)
[![Phase](https://img.shields.io/badge/phase-6-blue)](#roadmap)

---

## What is AVM?

AVM is the emulator backend that **nunu** uses to run Android games at near-native speed. When you press **Play** in nunu, AVM:

1. Detects the best available hypervisor on your machine (HVF on macOS, KVM on Linux, WHPX on Windows)
2. Auto-detects the Android SDK emulator binary and creates an AVD pointing at your system image
3. Boots Android 14 with hardware-accelerated GPU (gfxstream + Metal/Vulkan/OpenGL)
4. Bridges ADB so nunu can install games, forward input, and monitor the session

You can also run AVM standalone from the CLI for advanced use cases.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          nunu Launcher                          │
│   Game Library · Google Auth · Install · Play button           │
└───────────────────────────┬─────────────────────────────────────┘
                            │  vm:launch IPC
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                       AVM (this repo)                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            Android SDK Emulator (auto-detected)         │   │
│  │   CPU: HVF (macOS) · KVM (Linux) · WHPX (Windows)      │   │
│  │   GPU: gfxstream → Metal / Vulkan / OpenGL              │   │
│  │   ADB bridge · goldfish devices · Google Play support   │   │
│  └─────────────────────────────────────────────────────────┘   │
│         ↑ primary path         ↓ fallback (no SDK)              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Standard QEMU                          │   │
│  │   HVF / KVM / WHPX · virtio-gpu · MoltenVK             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Android 14 Guest (ARM64)                   │   │
│  │   Google Play Store · GApps · virtio-input / net / gpu  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Installing with nunu (Recommended)

nunu handles everything automatically. Install nunu and AVM is set up as part of the process.

### macOS (Apple Silicon)

**Step 1 — Install dependencies**

```bash
brew install android-commandlinetools qemu sdl2 sdl2_ttf molten-vk ninja cmake
```

**Step 2 — Install the Android 14 system image with Google Play**

```bash
# Accept licenses
yes | sdkmanager --licenses

# Install platform tools + system image
sdkmanager "platform-tools" \
           "system-images;android-34;google_apis_playstore;arm64-v8a"
```

**Step 3 — Build AVM**

```bash
git clone https://github.com/wisnuub/AVM.git && cd AVM
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(sysctl -n hw.logicalcpu)

# Required for Hypervisor.framework access
codesign --entitlements avm.entitlements --force -s - ./build/avm
```

**Step 4 — Point nunu at your AVM binary**

Copy the binary to the nunu resources directory:

```bash
mkdir -p ~/.nunu/avm-core
cp ./build/avm ~/.nunu/avm-core/avm
```

nunu will detect it automatically on next launch.

---

### Linux (Ubuntu / Debian)

```bash
# KVM + build tools
sudo apt install qemu-system-aarch64 libsdl2-dev libsdl2-ttf-dev \
                 cmake ninja-build adb

# Android SDK
sudo apt install android-sdk  # or download commandlinetools manually

# Install system image
sdkmanager "platform-tools" \
           "system-images;android-34;google_apis_playstore;arm64-v8a"

# Build
git clone https://github.com/wisnuub/AVM.git && cd AVM
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Deploy to nunu
mkdir -p ~/.nunu/avm-core && cp ./build/avm ~/.nunu/avm-core/avm
```

---

### Windows

```powershell
# Install dependencies via winget / choco / vcpkg
winget install Google.AndroidStudio   # includes SDK + emulator
choco install cmake ninja

# Build (Visual Studio 2022 required)
git clone https://github.com/wisnuub/AVM.git; cd AVM
cmake -B build -G "Ninja" -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Deploy
New-Item -ItemType Directory -Force "$env:USERPROFILE\.nunu\avm-core"
Copy-Item .\build\avm.exe "$env:USERPROFILE\.nunu\avm-core\avm.exe"
```

> **Windows Hypervisor Platform** must be enabled in Windows Features for hardware acceleration.

---

## Standalone CLI Usage

You can run AVM directly without nunu for testing or automation:

```bash
# Boot Android 14 with Google Play (SDK emulator auto-detected)
./build/avm --image ~/Library/Android/sdk/system-images/android-34/google_apis_playstore/arm64-v8a

# Or with Homebrew android-commandlinetools
./build/avm --image /opt/homebrew/share/android-commandlinetools/system-images/android-34/google_apis_playstore/arm64-v8a

# Specify memory and CPU count
./build/avm --image <path> --memory 8192 --cores 6

# Use a per-game profile
./build/avm --image <path> --profile genshin
```

### All flags

```
  Image & Version
    --image <path>        Path to Android system image (.img or SDK image dir)
    --android <ver>       Target Android version: 12, 13, 14, tiramisu, API33…
    --list-versions       Print supported Android versions and exit

  Resources
    --memory <mb>         RAM in MB (default: 4096)
    --cores <n>           vCPU count (default: 4)

  Rendering
    --gpu vulkan|gl       Host GPU renderer (default: vulkan)
    --fps <n>             Target FPS cap, 0 = unlimited (default: 60)
    --fps-unlock          Alias for --fps 0

  Profiles
    --profile <name|path> Load a game/app profile from ~/.config/avm/profiles/
    --list-profiles       List saved profiles and exit

  Advanced
    --no-accel            Disable HW virtualization (slow, for testing)
    --kernel <path>       Custom kernel image
    --initrd <path>       Custom ramdisk/initrd
    --cmdline <args>      Kernel command-line arguments
    --help                Show this message
```

---

## Per-Game Profiles

Profiles live in `~/.config/avm/profiles/` (Linux/macOS) or `%APPDATA%\AVM\profiles\` (Windows).

```json
{
  "name": "genshin",
  "android": 14,
  "memory_mb": 8192,
  "cores": 6,
  "target_fps": 60,
  "gpu_backend": "vulkan",
  "description": "Genshin Impact — high-res, 60fps"
}
```

nunu generates these automatically when you configure a game. You can also hand-edit them.

---

## How AVM Integrates with nunu

When nunu calls `vm:launch`, it invokes:

```
~/.nunu/avm-core/avm --image <sdk-image-dir>
```

AVM then:

| Step | What happens |
|---|---|
| 1 | Finds the Android SDK emulator at common install paths |
| 2 | Creates `~/.avd/avm_nunu.avd/config.ini` pointing at the image |
| 3 | Sets `ANDROID_SDK_ROOT` + `ANDROID_AVD_HOME` in the child process |
| 4 | Launches `emulator -avd avm_nunu -no-boot-anim -no-audio` |
| 5 | gfxstream initializes Vulkan/Metal — Android window appears |
| 6 | ADB waits for `sys.boot_completed=1`, then nunu installs the game |

If no SDK emulator is found, AVM falls back to standard QEMU (headless, slower, no Google Play).

---

## Android Version Support

| Version | API | Min RAM | Google Play |
|---|---|---|---|
| Android 14 | 34 | 4 GB | `google_apis_playstore` image |
| Android 13 | 33 | 3 GB | `google_apis_playstore` image |
| Android 12 | 32 | 2 GB | `google_apis_playstore` image |

> Apple Silicon requires **ARM64** (`arm64-v8a`) images. x86_64 images will not run with hardware acceleration on M-series Macs.

---

## Building from Source

```bash
# macOS — full build
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DAVM_ENABLE_HVF=ON \
    -DAVM_ENABLE_MOLTENVK=ON
cmake --build build -j$(sysctl -n hw.logicalcpu)
codesign --entitlements avm.entitlements --force -s - ./build/avm

# Linux
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DAVM_ENABLE_KVM=ON
cmake --build build -j$(nproc)

# Windows (MSVC + Ninja)
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DAVM_ENABLE_WHPX=ON
cmake --build build
```

---

## Roadmap

- [x] Phase 1 — QEMU base + HVF/KVM/WHPX virtualization
- [x] Phase 2 — SDL2 window + virtio-input (keyboard, mouse, gamepad)
- [x] Phase 3 — GPU forwarding (MoltenVK/gfxstream host side)
- [x] Phase 4 — Overlay HUD, keymapper, ADB bridge
- [x] Phase 5 — Per-game profiles, FPS limiter, Android version selector
- [x] Phase 6 — GApps (Play Store), SafetyNet spoof, image-pull CLI
- [x] Phase 7 — Android SDK emulator integration, nunu launcher wiring, AVD auto-setup
- [ ] Phase 8 — Windows/Linux nunu installers, auto-update, gfxstream guest driver

---

## License

MIT — see [LICENSE](LICENSE).
