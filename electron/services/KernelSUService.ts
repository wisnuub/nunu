/**
 * KernelSUService — installs KernelSU via LKM on a running Cuttlefish VM.
 *
 * Uses the pre-built `android16-6.12_kernelsu.ko` from KernelSU releases.
 * Cuttlefish GKI kernels support loadable modules by default.
 *
 * Install flow:
 *   1. adb root + adb remount
 *   2. Download android16-6.12_kernelsu.ko → /vendor/lib/modules/kernelsu.ko
 *   3. Write /vendor/etc/init/kernelsu.rc  (insmod at early-init)
 *   4. Download KernelSU Manager APK      → /system/priv-app/KernelSUManager/
 *   5. restorecon + reboot
 *
 * After reboot, KernelSU is active and the KernelSU Manager app appears.
 * Root grants are managed from the Manager app.
 *
 * SUSFS: requires a custom kernel (built via nunu-kernel CI).
 * Once a custom vmlinuz_full is downloaded, SUSFS hides root from detection.
 */

import { app } from 'electron'
import { existsSync, mkdirSync, writeFileSync, createWriteStream } from 'fs'
import { join } from 'path'
import { get as httpsGet } from 'https'
import { spawnSync } from 'child_process'

export type KSUProgressFn = (pct: number, status: string) => void

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

export class KernelSUService {
  private readonly workDir: string

  constructor() {
    this.workDir = join(app.getPath('home'), '.nunu', 'kernelsu')
  }

  get koPath()  { return join(this.workDir, 'kernelsu.ko') }
  get apkPath() { return join(this.workDir, 'KernelSUManager.apk') }

  async install(
    adbSerial: string,
    onProgress: KSUProgressFn,
  ): Promise<{ success: boolean; error?: string }> {
    try {
      if (!existsSync(this.workDir)) mkdirSync(this.workDir, { recursive: true })

      // ── 1. Verify userdebug build ─────────────────────────────────────
      onProgress(2, 'Checking build type…')
      const debuggable = adbSync(adbSerial, ['shell', 'getprop', 'ro.debuggable'], 8_000)
      if (debuggable.stdout.trim() !== '1') {
        return { success: false, error: 'adb root requires a userdebug build (ro.debuggable=1).' }
      }

      // ── 2. Get root + remount ─────────────────────────────────────────
      onProgress(5, 'Getting root access…')
      const rootR = adbSync(adbSerial, ['root'], 15_000)
      if (!rootR.ok && !rootR.stdout.includes('already running as root')) {
        return { success: false, error: `adb root failed: ${rootR.stderr || rootR.stdout}` }
      }
      await sleep(2_000)
      adbSync(adbSerial, ['connect', adbSerial.includes(':') ? adbSerial : `${adbSerial}:5555`], 8_000)
      await sleep(1_000)

      const whoami = adbSync(adbSerial, ['shell', 'id'], 8_000)
      if (!whoami.stdout.includes('uid=0')) {
        return { success: false, error: `Not running as root. Response: ${whoami.stdout}` }
      }

      onProgress(10, 'Remounting /vendor and /system…')
      adbSync(adbSerial, ['disable-verity'], 15_000)
      await sleep(1_000)
      adbSync(adbSerial, ['remount'], 30_000)

      // ── 3. Download KernelSU LKM ──────────────────────────────────────
      onProgress(15, 'Fetching KernelSU release info…')
      await this.ensureKernelSUAssets(onProgress)

      // ── 4. Push .ko to /vendor/lib/modules/ ──────────────────────────
      onProgress(70, 'Installing KernelSU kernel module…')
      adbSync(adbSerial, ['shell', 'mkdir', '-p', '/vendor/lib/modules'], 10_000)
      const pushKo = adbSync(adbSerial, ['push', this.koPath, '/vendor/lib/modules/kernelsu.ko'], 60_000)
      if (!pushKo.ok) {
        return { success: false, error: `Failed to push kernelsu.ko: ${pushKo.stderr}` }
      }
      adbSync(adbSerial, ['shell', 'chmod', '644', '/vendor/lib/modules/kernelsu.ko'], 5_000)

      // ── 5. Create init RC to load module at early-init ────────────────
      onProgress(80, 'Writing init RC…')
      // Write RC to a temp file then push
      const rcContent = [
        '# KernelSU — loaded early so it hooks into zygote before app launch',
        'on early-init',
        '    insmod /vendor/lib/modules/kernelsu.ko',
        '',
      ].join('\n')
      const localRcPath = join(this.workDir, 'kernelsu.rc')
      writeFileSync(localRcPath, rcContent)
      adbSync(adbSerial, ['shell', 'mkdir', '-p', '/vendor/etc/init'], 5_000)
      const pushRc = adbSync(adbSerial, ['push', localRcPath, '/vendor/etc/init/kernelsu.rc'], 10_000)
      if (!pushRc.ok) {
        return { success: false, error: `Failed to push kernelsu.rc: ${pushRc.stderr}` }
      }

      // ── 6. Install KernelSU Manager APK ──────────────────────────────
      onProgress(85, 'Installing KernelSU Manager…')
      adbSync(adbSerial, ['shell', 'mkdir', '-p', '/system/priv-app/KernelSUManager'], 5_000)
      const pushApk = adbSync(adbSerial, ['push', this.apkPath, '/system/priv-app/KernelSUManager/KernelSUManager.apk'], 60_000)
      if (!pushApk.ok) {
        return { success: false, error: `Failed to push KernelSU Manager APK: ${pushApk.stderr}` }
      }
      adbSync(adbSerial, ['shell', 'chmod', '644', '/system/priv-app/KernelSUManager/KernelSUManager.apk'], 5_000)

      // ── 7. SELinux contexts + reboot ──────────────────────────────────
      onProgress(92, 'Setting file contexts…')
      adbSync(adbSerial, ['shell', 'restorecon', '-R', '/vendor/lib/modules'], 15_000)
      adbSync(adbSerial, ['shell', 'restorecon', '-R', '/vendor/etc/init'], 10_000)
      adbSync(adbSerial, ['shell', 'restorecon', '-R', '/system/priv-app/KernelSUManager'], 10_000)

      onProgress(98, 'Rebooting…')
      adbSync(adbSerial, ['reboot'], 5_000)

      onProgress(100, 'KernelSU installed — Android is rebooting…')
      return { success: true }
    } catch (err) {
      return { success: false, error: err instanceof Error ? err.message : String(err) }
    }
  }

  // ── Asset download helpers ───────────────────────────────────────────────

  private async ensureKernelSUAssets(onProgress: KSUProgressFn): Promise<void> {
    const needKo  = !existsSync(this.koPath)
    const needApk = !existsSync(this.apkPath)
    if (!needKo && !needApk) return

    const releases = await fetchJson<GHRelease[]>(
      'https://api.github.com/repos/tiann/KernelSU/releases?per_page=5'
    )

    for (const rel of releases) {
      const ko  = rel.assets.find((a) => a.name === 'android16-6.12_kernelsu.ko')
      const apk = rel.assets.find((a) => a.name.endsWith('.apk') && a.name.startsWith('KernelSU'))

      if (ko && apk) {
        if (needKo) {
          onProgress(20, `Downloading KernelSU module (${rel.tag_name})…`)
          await downloadFile(ko.browser_download_url, this.koPath, (f) => {
            onProgress(20 + Math.round(f * 20), `Downloading module… ${Math.round(f * 100)}%`)
          })
        }
        if (needApk) {
          onProgress(45, `Downloading KernelSU Manager (${rel.tag_name})…`)
          await downloadFile(apk.browser_download_url, this.apkPath, (f) => {
            onProgress(45 + Math.round(f * 20), `Downloading manager… ${Math.round(f * 100)}%`)
          })
        }
        return
      }
    }

    throw new Error('Could not find android16-6.12_kernelsu.ko in KernelSU releases. Check your internet connection.')
  }
}
