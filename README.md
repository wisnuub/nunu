<p align="center">
  <img src="assets/icon.svg" width="160" alt="nunu icon" />
</p>

# nunu — Android without compromise

Run Android games on your Mac or Windows PC. On Apple Silicon nunu is a native Swift app: Android runs as ARM64 on the M-series cores under Hypervisor.framework, and games draw on the Mac GPU through Metal.

---

## Download

Head to [Releases](https://github.com/wisnuub/nunu/releases) and grab the latest build for your platform:

| Platform | File | Notes |
|---|---|---|
| macOS (Apple Silicon) | `nunu-x.x.x-arm64.dmg` | Open, drag to Applications, right-click → Open on first launch. macOS 15+ |
| Windows (x64) | `nunu Setup x.x.x.exe` | Run the installer; click "More info → Run anyway" if SmartScreen appears |

---

## Features

- **Guided setup** — first launch walks you through downloading the Android engine and configuring everything automatically
- **Device certification** — sets up Google Play compatibility so certified apps work out of the box
- **Game library** — browse, install, and launch popular Android games from one place
- **Google account** — sign in to sync saves and purchases across devices
- **Google Play Store**: on macOS, nunu uses Google's certified Android 14 Google Play image
- **Game controls (macOS)**: BlueStacks-style key mapping: tap keys, WASD D-pad, mouse-look and fire
- **Smart updates** — Android engine updates download as small delta patches rather than full images

---

## Build from source

The macOS app is a Swift package in [`macos/`](macos/), see [macos/README.md](macos/README.md). The rest of this section is the Electron launcher used on Windows.

**Requirements:** Node.js 20+, npm, Git

```bash
git clone https://github.com/wisnuub/nunu
cd nunu
npm install
```

**Development:**
```bash
npm run electron:dev
```

**Package for release:**
```bash
npm run electron:build:mac    # → release/nunu-x.x.x.dmg
npm run electron:build:win    # → release/nunu Setup x.x.x.exe
```

---

## Architecture

```
nunu (this repo)
│
├─ macOS Apple Silicon: macos/ (native Swift app)
│       Google's Android VM engine on Hypervisor.framework, downloaded on first run
│       ARM64 Android on ARM64 cores, GLES/Vulkan forwarded to Metal (gfxstream)
│
└─ Windows x86_64: Electron launcher (electron/, src/)
        nunu-windows — QEMU + WHPX
        Android x86_64, hardware-accelerated
```

| Repo | Role |
|---|---|
| [nunu](https://github.com/wisnuub/nunu) | macOS app (`macos/`) and the Electron launcher for Windows |
| [nunu-windows](https://github.com/wisnuub/nunu-windows) | Windows VM engine — QEMU + WHPX |
| [nunu-apple](https://github.com/wisnuub/nunu-apple) | Retired macOS engine (Cuttlefish + Virtualization.framework, no 3D GPU for Linux guests) |

**First launch** runs the full onboarding flow: Welcome → Install Engine → Sign In → Complete.  
**Every launch after that** goes straight to your game library — no setup screens.

### Update / patch system

nunu-windows publishes an `update-manifest.json` asset in each GitHub release. nunu checks this on startup and in Settings → Android Engine. If you already have a base image installed, it downloads only a delta patch (xdelta3 format) — typically 30–100× smaller than a full image.

For patch support, install xdelta3:
```bash
# macOS
brew install xdelta

# Windows — add xdelta3.exe to PATH
```
If xdelta3 is not available, nunu falls back to a full image download automatically.

### Google Play Store (macOS)

The macOS app installs Google's `google_apis_playstore` Android 14 ARM64 image, which ships with Play Store and Play Services and is Play-certified. No Magisk or GApps patching.

---

## Data location

All runtime data lives under `~/.nunu/` — delete this folder to fully uninstall:

| Path | Purpose |
|---|---|
| `~/.nunu/config.json` | App settings and custom image path |
| `~/.nunu/sdk/` | Android VM engine, platform-tools and system image |
| `~/.nunu/avd/` | Android device files and the quick-boot snapshot |
| `~/.nunu/keymaps/` | Per-game controls (macOS) |
| `~/.nunu/logs/` | `nunu.log` and `engine.log` (macOS) |
| `~/.nunu/engines/`, `~/.nunu/magisk/` | Left over from the old macOS engine, safe to delete |
