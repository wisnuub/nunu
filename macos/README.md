# nunu for macOS

Native Swift app for Apple Silicon. No Electron. It runs Android 14 with Google Play in a hardware-virtualized ARM64 VM and draws it in nunu's own Metal window.

## How it works

```
nunu.app (Swift, AppKit + Metal)
│
├── Engine.swift          launches / re-attaches / stops the Android VM
├── EngineClient.swift    gRPC: frame stream, multitouch + key input stream
├── FrameRenderer.swift   shared-memory frames -> Metal texture (no copy)
├── FrameView.swift       mouse -> touch, trackpad -> swipe/pinch, keys
├── KeyMap.swift          BlueStacks-style controls: keys, D-pad, mouse-look
├── Home.swift            nunu Home: native game library over Android's launcher
├── AppTabs.swift         title-bar tabs for open apps (switch, close)
├── Guest.swift           debloat, per-boot tuning, foreground-app events
├── Root.swift            KernelSU: fetch kernel + manager, install, device-profile module
├── DeviceProfile.swift   build-fingerprint presets for root hiding
├── SettingsView.swift    Performance / Display / Graphics / Apps / Controls / Root / Advanced
└── SDKInstaller.swift    first-run download from Google's SDK repository
        │
        ▼
Android VM engine (Google's QEMU fork, downloaded to ~/.nunu/sdk on first run)
├── CPU:  Hypervisor.framework, ARM64 guest on ARM64 host, no translation
└── GPU:  gfxstream: guest GLES / Vulkan -> host Metal (MoltenVK for Vulkan)
```

The VM runs with its own window hidden. nunu asks the engine to stream finished
frames into a shared-memory file that nunu also maps as an `MTLBuffer`, so the GPU
samples Android's pixels straight from that memory. Input goes back over one
long-lived gRPC stream, so a tap costs one HTTP/2 frame, not an `adb` process.

Why not Virtualization.framework (the old `nunu-apple` engine): Apple only gives
Linux guests a 2D framebuffer there, so every game frame was drawn on the CPU.

## Measured on an M1 MacBook (8 GB)

| | |
|---|---|
| Guest GPU | `OpenGL ES Translator (Apple M1)`, OpenGL ES 3.0 over Metal; Vulkan 1.3 via MoltenVK |
| Guest CPU | M1 cores directly (guest sees `sha3 sb paca pacg`) |
| Cold boot | 16–34 s |
| Resume from quick-boot snapshot | ~2 s engine restore, ready in ~8 s |
| Display path | 55–60 fps delivered at 1280×720 while scrolling, no dropped frames |

## Build and run

Requirements: macOS 15+, Apple Silicon, Xcode 16+.

```bash
cd macos
swift build && .build/debug/Nunu         # dev run, logs to the terminal
scripts/build-app.sh                     # build/nunu.app
scripts/build-app.sh --dmg               # build/nunu-<version>-arm64.dmg
```

`NUNU_LOG_FPS=1` prints the delivered frame rate once a second. The engine only sends a
frame when the picture changes, so a still screen reads "idle", not a frame rate.

The gRPC client in `Sources/EmulatorAPI` is generated from `proto/emulator_controller.proto`
(shipped with the engine). Regenerate with `scripts/gen-proto.sh`.

## Using it

**nunu Home** covers Android's launcher whenever it's in front: your installed games
(names and icons from their Play Store pages, cached in `~/.nunu/library`), a popular-games
shelf, and shortcuts to the Play Store and settings. Right-click a game for controls,
its store page or uninstall.

Home lists only apps with a launcher icon, split into **My games** and **Others** by their
Play Store category. Downloads show as a progress ring around the game's icon; ✕ cancels
(through Android if allowed, otherwise by pressing Play's own cancel button).

**Sideloading**: drag `.apk`, `.apks` (SAI/bundletool) or `.xapk` (APKPure, OBB data
included) onto the window, use ⌘O / Install APK, or double-click one in Finder.

**Mouse lock** (per game, in the ⌘K editor): set the game's lock key, whether its overlay
shows (controls work either way) and whether the mouse locks when the game opens.
⌃⌥ is the hard release, like VMware/Parallels; Esc goes to the game.

**App tabs** in the title bar work like BlueStacks/MuMu: Home plus one tab per open app.
Click to switch, ✕ or ⌘W closes the app (its task and process), right-click for Close
Others / Close All, ⌃Tab cycles. Android's Recents screen is replaced by the tabs.
Permission prompts and Google sign-in never open their own tab.

**Touch ID as Android's fingerprint**: when an app, a Play Store purchase or the lock
screen asks for a fingerprint, macOS asks for Touch ID and nunu passes the match to
Android's virtual sensor (watching the guest's fingerprint HAL log). Set up once from
Settings > Advanced > Set up fingerprint in Android; Android needs a screen lock first,
then nunu asks for Touch ID once and performs all the enrollment touches. The toolbar's
Touch ID button (⇧⌘T) answers any prompt manually.

**Root (KernelSU)**: Settings > Root. nunu boots a custom KernelSU-Next + SUSFS
kernel through the emulator's `-kernel` flag *only while root is on*, so the toggle
is a clean on/off: turning it off boots the stock kernel with no leftover. SUSFS
hides root from detection (Play Integrity, anti-cheat). The kernel is built in
[nunu-kernel](https://github.com/wisnuub/nunu-kernel) to match the image's
`android14-6.1` kernel; Download kernel + manager fetches it and the KernelSU-Next
manager app, which grants or denies root per app. A **device profile** spoofs the
build fingerprint to a real phone (Pixel 8 Pro, S23 Ultra…) via a `resetprop`
module so the emulator and root stay hidden. Changing the toggle or profile
restarts Android.

**Settings** (⌘,):

| Tab | |
|---|---|
| Performance | Low / Balanced / High profiles, CPU cores, memory, frame rate (30–120), high-priority engine, Android game mode, lighter animations |
| Display | Landscape / portrait, resolution presets up to 2560×1440, DPI, FPS counter |
| Graphics | Metal GPU or software renderer, Vulkan on/off |
| Apps | Disable preinstalled apps: everyday ones first (Gmail, Photos, YouTube, Calendar…), system extras under Show all; the recommended set is applied on first boot |
| Controls | Control hints, mouse-look sensitivity |
| Root | KernelSU toggle, device profile, status (kernel / manager / root active), download and install |
| Advanced | Quick boot, sound, storage size, ADB address, versions, logs, reset Android |

Every boot nunu also turns off background Wi-Fi/BLE scanning, keeps the screen awake,
and launches the engine at user-interactive priority with App Nap off.

| Mac | Android |
|---|---|
| Click / drag | Touch |
| Trackpad scroll, mouse wheel | Finger swipe |
| Pinch | Two-finger pinch |
| Keyboard | Keyboard (⌘ shortcuts stay with macOS) |
| ⌘[ · ⇧⌘H | Back · Home |
| ⌃Tab · ⌘W | Next app tab · Close app |
| ⌘K | Edit game controls |
| ⌘S | Screenshot to ~/Pictures/nunu |

**Game controls** are saved per app in `~/.nunu/keymaps/<package>.json` and switch
automatically when you change app. In the editor (⌘K):

- **Key**: click a spot, press a key. Holding the key holds a finger there.
- **D-pad**: W A S D drive a finger around the game's movement stick.
- **Aim**: ` toggles mouse-look for shooters. The cursor locks, mouse movement drags a finger over the camera area, Esc releases.
- **Fire**: a spot that left-click taps while aiming.

Drag to move, click a control and press a key to rebind, right-click or Delete to remove.

Quitting saves Android's state (quick boot), so the next launch resumes where you left off.

## Data

| Path | |
|---|---|
| `~/.nunu/sdk/` | Engine, platform-tools, Android 14 Google Play image |
| `~/.nunu/avd/nunu.avd/` | Device config, user data, quick-boot snapshot |
| `~/.nunu/root/` | KernelSU kernel, manager APK, device-profile module |
| `~/.nunu/keymaps/` | Per-game controls |
| `~/.nunu/logs/` | `nunu.log`, `engine.log` |

nunu runs its own adb server on port 5137 so it never restarts another SDK's adb.
