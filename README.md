# nunu — Android without compromise

A native macOS launcher for running Android games on Apple Silicon. Built on top of [AVM](https://github.com/wisnuub/AVM), nunu provides a polished installer, game library, Google account integration, and automatic Android engine updates.

---

## Features

- **One-click setup** — downloads and configures the AVM engine and Android image automatically
- **Game library** — install and launch popular Android titles directly from the launcher
- **Google Sign-In** — link your account to sync game saves and purchases
- **Delta updates** — AVM engine updates are downloaded as small patches rather than full images, saving bandwidth
- **Native performance** — runs on Apple Silicon using hardware virtualization (Hypervisor.framework)

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon (M1 / M2 / M3)
- ~5 GB free disk space

## Build

```bash
git clone https://github.com/wisnuub/nemu
cd nemu
swift build -c release
```

Run:

```bash
.build/release/nunu
```

## Architecture

```
nunu (this repo)          AVM (engine backend)
─────────────────         ──────────────────────────
SwiftUI launcher    ←──── C++ hypervisor + GPU + input
UpdateService       ←──── GitHub releases / update-manifest.json
PatchService        ←──── xdelta3 delta patches
InstallationService ←──── ADB + QEMU lifecycle
```

### Update / patch system

AVM publishes an `update-manifest.json` in each GitHub release. nunu fetches this manifest on startup (and on demand in Settings → Android Engine) to determine if a newer Android image is available.

If the user already has a compatible base image installed, nunu downloads only a delta patch (xdelta3 format) — typically 30–100× smaller than a full image download. If xdelta3 is not installed, it falls back to a full image download automatically.

**Install xdelta3 for patch support:**

```bash
brew install xdelta
```

### Manifest format

AVM releases include `update-manifest.json` with this structure:

```json
{
  "schema": 1,
  "android": {
    "latest": "13.0.2",
    "releases": [
      {
        "version": "13.0.2",
        "release_notes": "Security patches, GPU compatibility improvements",
        "full_image": {
          "url": "https://github.com/wisnuub/AVM/releases/download/v13.0.2/android-13-arm64.img.gz",
          "size": 892000000,
          "sha256": "<hex>"
        },
        "patches": [
          {
            "from": "13.0.1",
            "to": "13.0.2",
            "url": "https://github.com/wisnuub/AVM/releases/download/v13.0.2/android-13-arm64-13.0.1-to-13.0.2.xdelta",
            "size": 45678901,
            "sha256": "<hex>"
          }
        ]
      }
    ]
  },
  "avm": {
    "latest": "1.0.0"
  }
}
```

## Google Sign-In setup

Replace the placeholder `clientID` in [GoogleSignInView.swift](Sources/nunu/Views/GoogleSignInView.swift) with your OAuth 2.0 client ID from the Google Cloud Console. Register `nunu://oauth` as an authorized redirect URI.

## Data location

All runtime data is stored in `~/.nunu/`:

| File | Purpose |
|---|---|
| `avm-core` | AVM engine marker |
| `android-<version>-arm64.img` | Android disk image |
| `android-version.txt` | Installed version string |
