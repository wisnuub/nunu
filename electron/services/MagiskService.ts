/**
 * MagiskService — patches a Cuttlefish initramfs with Magisk on the host Mac,
 * then provisions GApps as a Magisk module on first boot via ADB.
 *
 * Flow:
 *   1. Download magiskboot (macOS ARM64 build) + Magisk APK from GitHub
 *   2. magiskboot unpack initramfs_fixed.img
 *   3. magiskboot cpio ramdisk.cpio  (inject magiskinit)
 *   4. magiskboot repack initramfs_fixed.img → initramfs_magisk.img
 *   5. Write marker so findCuttlefishImages() picks up the patched file
 *   6. After adb-ready fires: push Magisk APK + LiteGApps zip, install module, reboot
 */

import { app } from 'electron'
import { existsSync, mkdirSync, rmSync, renameSync, writeFileSync, readFileSync, copyFileSync } from 'fs'
import { join, dirname } from 'path'
import { get as httpsGet } from 'https'
import { spawnSync } from 'child_process'

// ── Constants ────────────────────────────────────────────────────────────────

const MAGISK_API = 'https://api.github.com/repos/topjohnwu/Magisk/releases?per_page=5'
// macOS ARM64 standalone magiskboot — PinNaCode/magiskboot_build "last-ci" tag
const MAGISKBOOT_MACOS_API =
  'https://api.github.com/repos/PinNaCode/magiskboot_build/releases/tags/last-ci'

export type MagiskProgressFn = (pct: number, status: string) => void

// ── Helpers ──────────────────────────────────────────────────────────────────

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms))
}

function adb(serial: string, args: string[], timeoutMs = 30_000) {
  const r = spawnSync('adb', ['-s', serial, ...args], { encoding: 'utf-8', timeout: timeoutMs })
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', ok: (r.status ?? 1) === 0 }
}

async function waitForBoot(serial: string, timeoutMs = 180_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (serial.includes(':')) {
      spawnSync('adb', ['connect', serial], { encoding: 'utf-8', timeout: 5_000 })
    }
    const r = adb(serial, ['shell', 'getprop', 'sys.boot_completed'], 8_000)
    if (r.stdout.trim() === '1') return true
    await sleep(4_000)
  }
  return false
}

interface GHRelease {
  tag_name: string
  assets: Array<{ name: string; browser_download_url: string; size: number }>
}

function fetchJson<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(
        u,
        { headers: { 'User-Agent': 'nunu-launcher/1.0', Accept: 'application/vnd.github+json' } },
        (res) => {
          if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
            doGet(res.headers.location)
            return
          }
          if (res.statusCode !== 200) { reject(new Error(`GitHub API ${res.statusCode} for ${u}`)); return }
          let raw = ''
          res.on('data', (c: string) => (raw += c))
          res.on('end', () => { try { resolve(JSON.parse(raw) as T) } catch (e) { reject(e) } })
          res.on('error', reject)
        },
      ).on('error', reject)
    }
    doGet(url)
  })
}

function downloadFile(url: string, dest: string, onProgress?: (frac: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(u, { headers: { 'User-Agent': 'nunu-launcher/1.0' } }, (res) => {
        if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
          doGet(res.headers.location)
          return
        }
        if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return }
        const total = parseInt(res.headers['content-length'] ?? '0', 10)
        let received = 0
        const { createWriteStream } = require('fs') as typeof import('fs')
        const out = createWriteStream(dest)
        res.on('data', (chunk: Buffer) => {
          received += chunk.length
          if (total > 0) onProgress?.(received / total)
          out.write(chunk)
        })
        res.on('end', () => out.end(() => resolve()))
        res.on('error', reject)
        out.on('error', reject)
      }).on('error', reject)
    }
    doGet(url)
  })
}

// ── MagiskService ────────────────────────────────────────────────────────────

export class MagiskService {
  private readonly workDir: string

  constructor() {
    this.workDir = join(app.getPath('home'), '.nunu', 'magisk')
  }

  get magiskbootPath() { return join(this.workDir, 'magiskboot') }
  get magiskApkPath()  { return join(this.workDir, 'Magisk.apk') }
  get gappsZipPath()   { return join(this.workDir, 'LiteGApps.zip') }

  // Safe wrapper — always returns a string error even on spawn failure
  private runMagiskboot(
    args: string[],
    cwd?: string,
  ): { stdout: string; stderr: string; ok: boolean; spawnError?: string } {
    const r = spawnSync(this.magiskbootPath, args, {
      encoding: 'utf-8',
      cwd,
      timeout: 300_000,
    })
    return {
      stdout:      r.stdout  ?? '',
      stderr:      r.stderr  ?? '',
      ok:          (r.status ?? 1) === 0,
      spawnError:  r.error?.message,
    }
  }

  // Returns true if the binary exists AND actually executes on this machine
  private magiskbootWorks(): boolean {
    if (!existsSync(this.magiskbootPath)) return false
    const r = spawnSync(this.magiskbootPath, [], { encoding: 'utf-8', timeout: 5_000 })
    // status is null only when the OS could not exec the binary at all
    return r.status !== null
  }

  // Returns path to the patched initramfs if it exists, else null
  patchedInitrdFor(originalInitrd: string): string {
    return originalInitrd.replace(/\.img$/, '_magisk.img')
  }

  isPatchedInitrdPresent(originalInitrd: string): boolean {
    return existsSync(this.patchedInitrdFor(originalInitrd))
  }

  // ── Phase 1: Patch initramfs on the host Mac ─────────────────────────────

  async patchInitrd(
    originalInitrd: string,
    onProgress: MagiskProgressFn,
  ): Promise<{ success: boolean; patchedPath?: string; error?: string }> {
    if (!existsSync(this.workDir)) mkdirSync(this.workDir, { recursive: true })
    const tmpDir = join(this.workDir, 'tmp_unpack')

    try {
      // ── 1. Get magiskboot ──────────────────────────────────────────────
      onProgress(2, 'Getting magiskboot for macOS…')
      await this.ensureMagiskboot(onProgress)

      // ── 2. Get Magisk APK (contains magiskinit) ────────────────────────
      onProgress(22, 'Downloading Magisk…')
      await this.ensureMagiskApk(onProgress)

      // ── 3. Unpack initramfs ────────────────────────────────────────────
      onProgress(40, 'Unpacking initramfs…')
      if (existsSync(tmpDir)) rmSync(tmpDir, { recursive: true, force: true })
      mkdirSync(tmpDir, { recursive: true })

      // Copy initramfs into workdir so magiskboot can work alongside it
      const workInitrd = join(tmpDir, 'initramfs.img')
      copyFileSync(originalInitrd, workInitrd)

      const unpack = this.runMagiskboot(['unpack', workInitrd], tmpDir)
      if (!unpack.ok) {
        const detail = unpack.spawnError ?? (unpack.stderr || unpack.stdout || 'no output')
        throw new Error(`magiskboot unpack failed: ${detail}`)
      }

      // ── 4. Extract magiskinit from the Magisk APK ──────────────────────
      onProgress(55, 'Extracting magiskinit…')
      const extractR = spawnSync(
        'unzip',
        ['-o', this.magiskApkPath, 'lib/arm64-v8a/libmagiskinit.so', '-d', tmpDir],
        { encoding: 'utf-8' },
      )
      if (extractR.status !== 0) {
        throw new Error(`Failed to extract magiskinit: ${extractR.stderr}`)
      }
      const magiskinitSrc = join(tmpDir, 'lib', 'arm64-v8a', 'libmagiskinit.so')
      const magiskinitDst = join(tmpDir, 'magiskinit')
      copyFileSync(magiskinitSrc, magiskinitDst)
      spawnSync('chmod', ['+x', magiskinitDst])

      // ── 5. Inject magiskinit into ramdisk ─────────────────────────────
      onProgress(65, 'Patching ramdisk…')
      // Replace /init with magiskinit — each token must be a separate argument
      const addR = this.runMagiskboot(
        ['cpio', 'ramdisk.cpio', 'add', '750', 'init', 'magiskinit'],
        tmpDir,
      )
      if (!addR.ok) {
        const detail = addR.spawnError ?? (addR.stderr || addR.stdout || 'no output')
        throw new Error(`magiskboot cpio patch failed: ${detail}`)
      }

      // ── 6. Repack initramfs ───────────────────────────────────────────
      onProgress(78, 'Repacking initramfs…')
      const patchedPath = this.patchedInitrdFor(originalInitrd)
      const repack = this.runMagiskboot(['repack', workInitrd, patchedPath], tmpDir)
      if (!repack.ok) {
        const detail = repack.spawnError ?? (repack.stderr || repack.stdout || 'no output')
        throw new Error(`magiskboot repack failed: ${detail}`)
      }

      // ── 7. Cleanup ────────────────────────────────────────────────────
      rmSync(tmpDir, { recursive: true, force: true })

      onProgress(100, 'initramfs patched with Magisk')
      return { success: true, patchedPath }
    } catch (err) {
      try { rmSync(tmpDir, { recursive: true, force: true }) } catch { /* ignore */ }
      return { success: false, error: err instanceof Error ? err.message : String(err) }
    }
  }

  // ── Phase 2: Post-boot provisioning via ADB ──────────────────────────────

  async provisionGApps(
    adbSerial: string,
    onProgress: MagiskProgressFn,
  ): Promise<{ success: boolean; error?: string }> {
    try {
      // ── 1. Wait for Magisk daemon to be ready ─────────────────────────
      onProgress(5, 'Waiting for Magisk daemon…')
      const magiskReady = await this.waitForMagisk(adbSerial, 120_000)
      if (!magiskReady) {
        return { success: false, error: 'Magisk daemon did not start. Check that the initramfs was patched correctly.' }
      }

      // ── 2. Push Magisk APK so the app can be installed ────────────────
      onProgress(15, 'Installing Magisk app…')
      const installR = adb(adbSerial, ['install', '-r', this.magiskApkPath], 60_000)
      if (!installR.ok) {
        return { success: false, error: `Failed to install Magisk APK: ${installR.stderr}` }
      }

      // ── 3. Fetch LiteGApps ARM64 for Android 15/16 ────────────────────
      onProgress(25, 'Finding LiteGApps release…')
      await this.ensureLiteGApps(onProgress)

      // ── 4. Push GApps zip to sdcard ───────────────────────────────────
      onProgress(60, 'Pushing GApps to device…')
      const pushR = adb(adbSerial, ['push', this.gappsZipPath, '/sdcard/LiteGApps.zip'], 120_000)
      if (!pushR.ok) {
        return { success: false, error: `Failed to push GApps zip: ${pushR.stderr}` }
      }

      // ── 5. Install as Magisk module ───────────────────────────────────
      onProgress(75, 'Installing GApps module…')
      const modR = adb(
        adbSerial,
        ['shell', 'su', '-c', 'magisk --install-module /sdcard/LiteGApps.zip'],
        120_000,
      )
      if (!modR.ok) {
        return { success: false, error: `Failed to install module: ${modR.stderr || modR.stdout}` }
      }

      // ── 6. Reboot ─────────────────────────────────────────────────────
      onProgress(90, 'Rebooting Android…')
      adb(adbSerial, ['reboot'], 5_000)

      onProgress(100, 'Google Play installed. Android is rebooting…')
      return { success: true }
    } catch (err) {
      return { success: false, error: err instanceof Error ? err.message : String(err) }
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  private async ensureMagiskboot(onProgress: MagiskProgressFn): Promise<void> {
    // If binary exists and actually runs, we're done
    if (this.magiskbootWorks()) return

    // Binary exists but doesn't run (wrong arch, corrupted) — remove it
    if (existsSync(this.magiskbootPath)) {
      rmSync(this.magiskbootPath)
    }

    // 1. Check PATH first (user may have installed manually)
    const which = spawnSync('which', ['magiskboot'], { encoding: 'utf-8' })
    if (which.status === 0 && which.stdout.trim()) {
      copyFileSync(which.stdout.trim(), this.magiskbootPath)
      spawnSync('chmod', ['+x', this.magiskbootPath])
      if (this.magiskbootWorks()) return
      rmSync(this.magiskbootPath)
    }

    // 2. Try PinNaCode/magiskboot_build "last-ci" — specific tag, returns single release object
    let downloadErr = ''
    try {
      const rel = await fetchJson<GHRelease>(MAGISKBOOT_MACOS_API)
      // Pick macOS ARM64 asset — progressively broader fallbacks
      const asset =
        rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return (
            (n.includes('darwin') || n.includes('macos') || n.includes('osx') || n.includes('apple')) &&
            (n.includes('arm64') || n.includes('aarch64'))
          )
        }) ??
        rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return n.includes('darwin') || n.includes('macos') || n.includes('osx') || n.includes('apple')
        }) ??
        // Last resort: any asset that isn't a checksum / Windows / x86_64
        rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return !n.endsWith('.sha256') && !n.endsWith('.md5') &&
                 !n.includes('x86_64') && !n.includes('windows') && !n.includes('win')
        })

      if (asset) {
        onProgress(4, `Downloading magiskboot (${asset.name})…`)
        const isZip = asset.name.endsWith('.zip')
        const downloadDest = isZip
          ? join(this.workDir, asset.name)
          : this.magiskbootPath
        await downloadFile(asset.browser_download_url, downloadDest, (f) => {
          onProgress(4 + Math.round(f * 14), `Downloading magiskboot… ${Math.round(f * 100)}%`)
        })
        if (isZip) {
          // Extract the binary from the zip — the binary inside is named 'magiskboot'
          const r = spawnSync('unzip', ['-o', downloadDest, 'magiskboot', '-d', this.workDir], {
            encoding: 'utf-8',
          })
          rmSync(downloadDest)
          if (r.status !== 0) {
            downloadErr = `unzip failed: ${r.stderr || r.stdout}`
          }
        }
        spawnSync('chmod', ['+x', this.magiskbootPath])
        if (this.magiskbootWorks()) return
        downloadErr = downloadErr || `Downloaded ${asset.name} but it does not execute — wrong architecture?`
        if (existsSync(this.magiskbootPath)) rmSync(this.magiskbootPath)
      } else {
        downloadErr = `No suitable asset in release ${rel.tag_name}. Available: ${rel.assets.map(a => a.name).join(', ')}`
      }
    } catch (e) {
      downloadErr = e instanceof Error ? e.message : String(e)
    }

    throw new Error(
      `magiskboot for macOS not available automatically. ${downloadErr ? `(${downloadErr}) ` : ''}` +
      'Please install it manually:\n' +
      '  1. Download from https://github.com/PinNaCode/magiskboot_build/releases/tag/last-ci\n' +
      '  2. chmod +x magiskboot\n' +
      '  3. Move to ~/.nunu/magisk/magiskboot',
    )
  }

  private async ensureMagiskApk(onProgress: MagiskProgressFn): Promise<void> {
    if (existsSync(this.magiskApkPath)) return

    const releases = await fetchJson<GHRelease[]>(MAGISK_API)
    // Pick first stable (non-beta, non-canary) release
    const rel = releases.find(
      (r) => !r.tag_name.toLowerCase().includes('beta') && !r.tag_name.toLowerCase().includes('canary'),
    ) ?? releases[0]
    if (!rel) throw new Error('No Magisk releases found on GitHub')

    const asset = rel.assets.find((a) => a.name.endsWith('.apk') && !a.name.includes('stub'))
    if (!asset) throw new Error(`No Magisk APK in release ${rel.tag_name}`)

    onProgress(24, `Downloading Magisk ${rel.tag_name} (${Math.round(asset.size / 1_048_576)} MB)…`)
    await downloadFile(asset.browser_download_url, this.magiskApkPath, (f) => {
      onProgress(24 + Math.round(f * 14), `Downloading Magisk… ${Math.round(f * 100)}%`)
    })
  }

  private async ensureLiteGApps(onProgress: MagiskProgressFn): Promise<void> {
    if (existsSync(this.gappsZipPath)) return

    // LiteGApps: minimal GApps with just Play Store + Play Services
    // Hosted on GitHub: litegapps/litegapps
    const api = 'https://api.github.com/repos/litegapps/litegapps/releases?per_page=10'
    let downloaded = false

    try {
      const releases = await fetchJson<GHRelease[]>(api)
      for (const rel of releases) {
        // Find ARM64 + Android 15 or 16 nano/micro build
        const asset = rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return (
            n.includes('arm64') &&
            (n.includes('15') || n.includes('16')) &&
            (n.includes('nano') || n.includes('micro') || n.includes('pico'))
          )
        }) ?? rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return n.includes('arm64') && (n.includes('nano') || n.includes('micro') || n.includes('pico'))
        })
        if (asset) {
          onProgress(28, `Downloading ${asset.name} (${Math.round(asset.size / 1_048_576)} MB)…`)
          await downloadFile(asset.browser_download_url, this.gappsZipPath, (f) => {
            onProgress(28 + Math.round(f * 30), `Downloading GApps… ${Math.round(f * 100)}%`)
          })
          downloaded = true
          break
        }
      }
    } catch { /* fall through */ }

    if (!downloaded) {
      // Fallback: MindTheGapps as a zip that Magisk can flash
      const mtgApi = 'https://api.github.com/repos/MindTheGapps/MindTheGapps/releases?per_page=5'
      const releases = await fetchJson<GHRelease[]>(mtgApi)
      for (const rel of releases) {
        const asset = rel.assets.find((a) => a.name.includes('arm64') && a.name.endsWith('.zip'))
        if (asset) {
          onProgress(28, `Downloading MindTheGapps ${rel.tag_name} (${Math.round(asset.size / 1_048_576)} MB)…`)
          await downloadFile(asset.browser_download_url, this.gappsZipPath, (f) => {
            onProgress(28 + Math.round(f * 30), `Downloading GApps… ${Math.round(f * 100)}%`)
          })
          downloaded = true
          break
        }
      }
    }

    if (!downloaded) {
      throw new Error('Could not find a suitable GApps package. Check your internet connection.')
    }
  }

  private async waitForMagisk(serial: string, timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
      const r = adb(serial, ['shell', 'su', '-c', 'magisk -V'], 8_000)
      if (r.ok && r.stdout.trim().length > 0) return true
      await sleep(5_000)
    }
    return false
  }
}
