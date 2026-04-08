<p align="center">
  <img src="assets/icon.svg" width="160" alt="nunu icon" />
</p>

# nunu — Android without compromise

Run Android games natively on your Mac or Windows PC. nunu handles everything — downloading the Android engine, configuring device certification, and giving you a game library to install and launch titles directly.

---

## Download

Head to [Releases](https://github.com/wisnuub/nunu/releases) and grab the latest build for your platform:

| Platform | File | Notes |
|---|---|---|
| macOS (Apple Silicon) | `nunu-x.x.x.dmg` | Open, drag to Applications, right-click → Open on first launch |
| Windows (x64) | `nunu Setup x.x.x.exe` | Run the installer; click "More info → Run anyway" if SmartScreen appears |

---

## Features

- **Guided setup** — first launch walks you through downloading the Android engine and configuring everything automatically
- **Device certification** — sets up Google Play compatibility so certified apps work out of the box
- **Game library** — browse, install, and launch popular Android games from one place
- **Google account** — sign in to sync saves and purchases across devices
- **Google Play Store** — optional Magisk-based GApps install brings Play Store to the AOSP image
- **Smart updates** — Android engine updates download as small delta patches rather than full images

---

## Build from source

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
├─ macOS Apple Silicon
│       nunu-apple — Cuttlefish + Virtualization.framework
│       Native ARM64 Android, no translation layer, Metal GPU
│
└─ Windows x86_64
        nunu-windows — QEMU + WHPX
        Android x86_64, hardware-accelerated
```

| Repo | Role |
|---|---|
| [nunu](https://github.com/wisnuub/nunu) | Electron + React launcher — this repo |
| [nunu-apple](https://github.com/wisnuub/nunu-apple) | macOS VM engine — Cuttlefish + Virtualization.framework |
| [nunu-windows](https://github.com/wisnuub/nunu-windows) | Windows VM engine — QEMU + WHPX |

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

Settings → Engine → **Patch initramfs** injects Magisk into the Cuttlefish initramfs on the host before the VM starts. Once the VM is running, **Install GApps** pushes a minimal GApps package (Play Store + Google Account, no Chrome or Gmail) as a Magisk module and reboots. Everything is automatic — `magiskboot` and the Magisk APK are downloaded by nunu.

---

## Data location

All runtime data lives under `~/.nunu/` — delete this folder to fully uninstall:

| Path | Purpose |
|---|---|
| `~/.nunu/config.json` | App settings and custom image path |
| `~/.nunu/engines/nunu-apple/` | macOS engine (NunuVM.app) |
| `~/.nunu/cuttlefish/` | Cuttlefish VM disk images (macOS) |
| `~/.nunu/sdk/` | Android SDK — emulator + platform-tools (Windows) |
| `~/.nunu/avd/` | Android Virtual Device files (Windows) |
| `~/.nunu/magisk/` | magiskboot binary + Magisk APK for GApps patching |
