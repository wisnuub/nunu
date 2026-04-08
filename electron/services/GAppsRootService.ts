/**
 * GAppsRootService — installs minimal GApps on a userdebug Cuttlefish VM
 * using `adb root` + `adb remount` (no Magisk / initramfs patching needed).
 *
 * Cuttlefish aosp_cf_arm64_only_phone-userdebug ships with adbd running as root
 * by default. We use that to remount /system as rw and push the GApps APKs
 * directly into /system/priv-app/.
 *
 * APKs installed:
 *   - GsfProxy          (GSF stub — required by GMS)
 *   - GoogleServicesFramework (GSF)
 *   - GoogleLoginService
 *   - Phonesky          (Play Store)
 *   - PrebuiltGmsCore   (GMS Core — Play Services)
 *
 * We download a NikGapps "core" or "basic" zip, extract the APKs from it,
 * and push them. NikGapps packages are the most reliably structured for
 * manual extraction.
 */

import { app } from 'electron'
import { existsSync, mkdirSync, rmSync, writeFileSync, createWriteStream } from 'fs'
import { join } from 'path'
import { get as httpsGet } from 'https'
import { spawnSync, spawn } from 'child_process'

export type GAppsProgressFn = (pct: number, status: string) => void

interface GHRelease {
  tag_name: string
  assets: Array<{ name: string; browser_download_url: string; size: number }>
}

function fetchJson<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(u, { headers: { 'User-Agent': 'nunu-launcher/1.0', Accept: 'application/vnd.github+json' } }, (res) => {
        if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) { doGet(res.headers.location); return }
        if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode} for ${u}`)); return }
        let raw = ''
        res.on('data', (c: string) => (raw += c))
        res.on('end', () => { try { resolve(JSON.parse(raw) as T) } catch (e) { reject(e) } })
        res.on('error', reject)
      }).on('error', reject)
    }
    doGet(url)
  })
}

function downloadFile(url: string, dest: string, onProgress?: (frac: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(u, { headers: { 'User-Agent': 'nunu-launcher/1.0' } }, (res) => {
        if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) { doGet(res.headers.location); return }
        if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return }
        const total = parseInt(res.headers['content-length'] ?? '0', 10)
        let received = 0
        const out = createWriteStream(dest)
        res.on('data', (chunk: Buffer) => { received += chunk.length; if (total > 0) onProgress?.(received / total); out.write(chunk) })
        res.on('end', () => out.end(() => resolve()))
        res.on('error', reject)
        out.on('error', reject)
      }).on('error', reject)
    }
    doGet(url)
  })
}

function adbSync(serial: string, args: string[], timeoutMs = 60_000) {
  const r = spawnSync('adb', ['-s', serial, ...args], { encoding: 'utf-8', timeout: timeoutMs })
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', ok: (r.status ?? 1) === 0 }
}

function sleep(ms: number) { return new Promise<void>((r) => setTimeout(r, ms)) }

export class GAppsRootService {
  private readonly workDir: string

  constructor() {
    this.workDir = join(app.getPath('home'), '.nunu', 'gapps')
  }

  get gappsZipPath() { return join(this.workDir, 'NikGapps.zip') }

  async install(
    adbSerial: string,
    onProgress: GAppsProgressFn,
  ): Promise<{ success: boolean; error?: string }> {
    try {
      if (!existsSync(this.workDir)) mkdirSync(this.workDir, { recursive: true })

      // ── 1. Verify adb root access ─────────────────────────────────────
      onProgress(2, 'Checking root access…')
      const rootR = adbSync(adbSerial, ['root'], 15_000)
      if (!rootR.ok && !rootR.stdout.includes('already running as root')) {
        return { success: false, error: `adb root failed: ${rootR.stderr || rootR.stdout}` }
      }
      // Brief pause for adbd to restart as root
      await sleep(2_000)

      // Reconnect after root restart
      adbSync(adbSerial, ['connect', adbSerial.includes(':') ? adbSerial : `${adbSerial}:5555`], 8_000)
      await sleep(1_000)

      // Verify we're actually root
      const whoami = adbSync(adbSerial, ['shell', 'id'], 8_000)
      if (!whoami.stdout.includes('uid=0')) {
        return { success: false, error: `Not running as root after adb root. Response: ${whoami.stdout}` }
      }

      // ── 2. Remount /system as read-write ──────────────────────────────
      onProgress(8, 'Remounting /system…')
      // disable-verity + remount is the reliable sequence for userdebug builds
      adbSync(adbSerial, ['disable-verity'], 15_000)
      await sleep(1_000)
      const remountR = adbSync(adbSerial, ['remount'], 30_000)
      if (!remountR.ok && !remountR.stdout.toLowerCase().includes('remount succeeded')) {
        // Try via shell mount as fallback
        const mountR = adbSync(adbSerial, ['shell', 'mount', '-o', 'rw,remount', '/system'], 15_000)
        if (!mountR.ok) {
          return { success: false, error: `remount failed: ${remountR.stderr || remountR.stdout}` }
        }
      }

      // ── 3. Download NikGapps core zip ─────────────────────────────────
      onProgress(12, 'Finding GApps package…')
      await this.ensureGAppsZip(onProgress)

      // ── 4. Extract APKs from the zip on the Mac ───────────────────────
      onProgress(55, 'Extracting APKs…')
      const apkDir = join(this.workDir, 'apks')
      if (existsSync(apkDir)) rmSync(apkDir, { recursive: true, force: true })
      mkdirSync(apkDir, { recursive: true })

      // NikGapps zip structure: NikGapps/core/<PackageName>/<PackageName>.apk
      // We unzip everything matching *.apk
      const unzipR = spawnSync('unzip', ['-o', this.gappsZipPath, '*.apk', '-d', apkDir], { encoding: 'utf-8' })
      if (unzipR.status !== 0 && !existsSync(apkDir)) {
        return { success: false, error: `Failed to extract APKs: ${unzipR.stderr}` }
      }

      // Find all extracted APKs recursively
      const findR = spawnSync('find', [apkDir, '-name', '*.apk'], { encoding: 'utf-8' })
      const apks = findR.stdout.trim().split('\n').filter(Boolean)
      if (apks.length === 0) {
        return { success: false, error: 'No APKs found in GApps zip' }
      }

      // ── 5. Push APKs to /system/priv-app/ ────────────────────────────
      onProgress(60, `Pushing ${apks.length} APKs to /system/priv-app/…`)
      for (let i = 0; i < apks.length; i++) {
        const apk = apks[i]
        const pkgName = apk.split('/').pop()!.replace('.apk', '')
        onProgress(60 + Math.round((i / apks.length) * 25), `Installing ${pkgName}…`)

        // Create directory for the APK (Android expects /system/priv-app/<Name>/<Name>.apk)
        adbSync(adbSerial, ['shell', 'mkdir', '-p', `/system/priv-app/${pkgName}`], 10_000)
        const pushR = adbSync(adbSerial, ['push', apk, `/system/priv-app/${pkgName}/${pkgName}.apk`], 60_000)
        if (!pushR.ok) {
          return { success: false, error: `Failed to push ${pkgName}: ${pushR.stderr}` }
        }
        // Set correct permissions
        adbSync(adbSerial, ['shell', 'chmod', '644', `/system/priv-app/${pkgName}/${pkgName}.apk`], 5_000)
      }

      // ── 6. Set SELinux context on pushed files ────────────────────────
      onProgress(87, 'Setting file contexts…')
      adbSync(adbSerial, ['shell', 'restorecon', '-R', '/system/priv-app'], 30_000)

      // ── 7. Reboot ─────────────────────────────────────────────────────
      onProgress(95, 'Rebooting Android…')
      adbSync(adbSerial, ['reboot'], 5_000)

      onProgress(100, 'Google Play installed — Android is rebooting…')
      return { success: true }
    } catch (err) {
      return { success: false, error: err instanceof Error ? err.message : String(err) }
    }
  }

  private async ensureGAppsZip(onProgress: GAppsProgressFn): Promise<void> {
    if (existsSync(this.gappsZipPath)) return

    // NikGapps — well-structured minimal GApps, ARM64, Android 15/16
    const api = 'https://api.github.com/repos/nikgapps/nikgapps/releases?per_page=10'
    try {
      const releases = await fetchJson<GHRelease[]>(api)
      for (const rel of releases) {
        const asset = rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return (
            n.includes('arm64') &&
            (n.includes('android-16') || n.includes('android-15') || n.includes('-16-') || n.includes('-15-')) &&
            (n.includes('core') || n.includes('basic')) &&
            n.endsWith('.zip')
          )
        }) ?? rel.assets.find((a) => {
          const n = a.name.toLowerCase()
          return n.includes('arm64') && (n.includes('core') || n.includes('basic')) && n.endsWith('.zip')
        })

        if (asset) {
          onProgress(15, `Downloading ${asset.name} (${Math.round(asset.size / 1_048_576)} MB)…`)
          await downloadFile(asset.browser_download_url, this.gappsZipPath, (f) => {
            onProgress(15 + Math.round(f * 38), `Downloading GApps… ${Math.round(f * 100)}%`)
          })
          return
        }
      }
    } catch { /* fall through to MindTheGapps */ }

    // Fallback: MindTheGapps
    const mtgApi = 'https://api.github.com/repos/MindTheGapps/MindTheGapps/releases?per_page=5'
    const releases = await fetchJson<GHRelease[]>(mtgApi)
    for (const rel of releases) {
      const asset = rel.assets.find((a) => a.name.includes('arm64') && a.name.endsWith('.zip'))
      if (asset) {
        onProgress(15, `Downloading MindTheGapps ${rel.tag_name} (${Math.round(asset.size / 1_048_576)} MB)…`)
        await downloadFile(asset.browser_download_url, this.gappsZipPath, (f) => {
          onProgress(15 + Math.round(f * 38), `Downloading GApps… ${Math.round(f * 100)}%`)
        })
        return
      }
    }

    throw new Error('Could not find a suitable GApps package. Check your internet connection.')
  }
}
