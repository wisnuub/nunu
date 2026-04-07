import { app } from 'electron'
import { existsSync, mkdirSync, rmSync, createWriteStream } from 'fs'
import { join } from 'path'
import { get as httpsGet } from 'https'
import { spawnSync } from 'child_process'

// Only these three are needed: Play Services framework, Play Services core, Play Store
const PRIV_APP_PACKAGES = ['GoogleServicesFramework', 'GmsCore', 'Phonesky']

export type GAppsProgressFn = (pct: number, status: string) => void

// ── ADB helpers ──────────────────────────────────────────────────────────────

function adbRun(
  serial: string,
  args: string[],
  timeoutMs = 30_000,
): { stdout: string; stderr: string; ok: boolean } {
  const r = spawnSync('adb', ['-s', serial, ...args], {
    encoding: 'utf-8',
    timeout: timeoutMs,
  })
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', ok: (r.status ?? 1) === 0 }
}

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms))
}

async function waitForBootCompleted(serial: string, timeoutMs = 180_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    // For TCP serials (e.g. localhost:5554), try to reconnect after reboot
    if (serial.includes(':')) {
      spawnSync('adb', ['connect', serial], { encoding: 'utf-8', timeout: 5_000 })
    }
    const r = adbRun(serial, ['shell', 'getprop', 'sys.boot_completed'], 8_000)
    if (r.stdout.trim() === '1') return true
    await sleep(4_000)
  }
  return false
}

// ── GitHub release fetch ─────────────────────────────────────────────────────

interface GAppsRelease {
  url: string
  name: string
  sizeMb: number
}

interface GHRelease {
  tag_name: string
  assets: Array<{ name: string; browser_download_url: string; size: number }>
}

async function fetchLatestMindTheGapps(): Promise<GAppsRelease | null> {
  // Try recent Android versions in descending order
  const releases = await fetchJson<GHRelease[]>(
    'https://api.github.com/repos/MindTheGapps/MindTheGapps/releases?per_page=20',
  ).catch(() => null)

  if (!releases) return null

  for (const release of releases) {
    const asset = release.assets.find(
      (a) => a.name.includes('arm64') && a.name.endsWith('.zip'),
    )
    if (asset) {
      return {
        url: asset.browser_download_url,
        name: asset.name,
        sizeMb: Math.round(asset.size / 1_048_576),
      }
    }
  }
  return null
}

// ── GAppsService ─────────────────────────────────────────────────────────────

export class GAppsService {
  private readonly serial: string

  constructor(adbSerial: string) {
    this.serial = adbSerial
  }

  async install(onProgress: GAppsProgressFn): Promise<{ success: boolean; error?: string }> {
    const tmpDir = join(app.getPath('temp'), 'nunu-gapps')

    try {
      // ── 1. Root check ────────────────────────────────────────────────────
      onProgress(4, 'Checking root access…')
      const rootR = adbRun(this.serial, ['root'], 12_000)
      const rootOk =
        rootR.ok ||
        rootR.stdout.includes('already running as root') ||
        rootR.stdout.includes('restarting adbd as root')
      if (!rootOk) {
        return {
          success: false,
          error:
            'adb root failed — device appears to be a production (user) build. ' +
            'GApps install requires a userdebug/eng build.',
        }
      }
      await sleep(2_500) // wait for adbd to restart as root

      // ── 2. Disable dm-verity (if not already) ───────────────────────────
      onProgress(10, 'Disabling dm-verity…')
      const verity = adbRun(this.serial, ['disable-verity'], 20_000)
      const verityOutput = verity.stdout + verity.stderr
      const alreadyDisabled = verityOutput.toLowerCase().includes('already disabled')
      const needsReboot =
        !alreadyDisabled &&
        (verityOutput.toLowerCase().includes('reboot') ||
          verityOutput.toLowerCase().includes('disabled on'))

      if (needsReboot) {
        onProgress(16, 'Rebooting to apply verity change…')
        adbRun(this.serial, ['reboot'], 5_000)
        onProgress(20, 'Waiting for Android to reboot…')
        const back = await waitForBootCompleted(this.serial, 180_000)
        if (!back) return { success: false, error: 'Device did not come back after reboot.' }
        onProgress(26, 'Regaining root…')
        adbRun(this.serial, ['root'], 12_000)
        await sleep(2_500)
      }

      // ── 3. Remount system ────────────────────────────────────────────────
      onProgress(30, 'Remounting system partition…')
      const remount = adbRun(this.serial, ['remount'], 20_000)
      const remountOut = remount.stdout + remount.stderr
      if (
        !remountOut.toLowerCase().includes('remount succeeded') &&
        !remountOut.toLowerCase().includes('already mounted')
      ) {
        // Non-fatal — some builds output warnings but still work; continue
        console.warn('[gapps] remount output:', remountOut)
      }
      await sleep(1_000)

      // ── 4. Find release ──────────────────────────────────────────────────
      onProgress(34, 'Finding MindTheGapps ARM64 release…')
      const release = await fetchLatestMindTheGapps()
      if (!release) {
        return { success: false, error: 'Could not find a MindTheGapps ARM64 release on GitHub.' }
      }

      // ── 5. Download ──────────────────────────────────────────────────────
      if (!existsSync(tmpDir)) mkdirSync(tmpDir, { recursive: true })
      const zipPath = join(tmpDir, 'mindthegapps.zip')

      onProgress(38, `Downloading ${release.name} (${release.sizeMb} MB)…`)
      await downloadFile(release.url, zipPath, (frac) => {
        onProgress(38 + Math.round(frac * 26), `Downloading… ${Math.round(frac * 100)}%`)
      })

      // ── 6. Extract only the priv-app packages we need ───────────────────
      onProgress(66, 'Extracting APKs…')
      const extractDir = join(tmpDir, 'extracted')
      if (existsSync(extractDir)) rmSync(extractDir, { recursive: true, force: true })
      mkdirSync(extractDir, { recursive: true })

      // Extract only the three dirs we care about
      for (const pkg of PRIV_APP_PACKAGES) {
        spawnSync(
          'unzip',
          ['-o', zipPath, `system/priv-app/${pkg}/*`, '-d', extractDir],
          { encoding: 'utf-8' },
        )
      }

      // ── 7. Push APKs to /system/priv-app/ ───────────────────────────────
      let pushed = 0
      for (let i = 0; i < PRIV_APP_PACKAGES.length; i++) {
        const pkg = PRIV_APP_PACKAGES[i]
        const apkSrc = join(extractDir, 'system', 'priv-app', pkg, `${pkg}.apk`)
        if (!existsSync(apkSrc)) {
          console.warn(`[gapps] APK not found in zip: ${pkg}`)
          continue
        }
        const pct = 70 + Math.round(((i + 0.5) / PRIV_APP_PACKAGES.length) * 18)
        onProgress(pct, `Pushing ${pkg}…`)
        adbRun(this.serial, ['shell', `mkdir -p /system/priv-app/${pkg}`])
        const pushR = adbRun(this.serial, ['push', apkSrc, `/system/priv-app/${pkg}/${pkg}.apk`], 60_000)
        if (!pushR.ok) {
          return { success: false, error: `Failed to push ${pkg}: ${pushR.stderr || pushR.stdout}` }
        }
        adbRun(this.serial, ['shell', `chmod 644 /system/priv-app/${pkg}/${pkg}.apk`])
        adbRun(this.serial, ['shell', `chown root:root /system/priv-app/${pkg}/${pkg}.apk`])
        pushed++
      }

      if (pushed === 0) {
        return { success: false, error: 'No APKs were found in the downloaded package.' }
      }

      // ── 8. Clean up and reboot ───────────────────────────────────────────
      onProgress(90, 'Cleaning up…')
      try { rmSync(tmpDir, { recursive: true, force: true }) } catch { /* ignore */ }

      onProgress(94, 'Rebooting Android…')
      adbRun(this.serial, ['reboot'], 5_000)

      onProgress(100, `Installed ${pushed}/3 packages. Android is rebooting…`)
      return { success: true }
    } catch (err) {
      try { rmSync(tmpDir, { recursive: true, force: true }) } catch { /* ignore */ }
      return { success: false, error: err instanceof Error ? err.message : String(err) }
    }
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

function fetchJson<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(
        u,
        { headers: { 'User-Agent': 'nunu-launcher/1.0', Accept: 'application/vnd.github+json' } },
        (res) => {
          if (res.statusCode === 301 || res.statusCode === 302) {
            if (res.headers.location) { doGet(res.headers.location); return }
          }
          if (res.statusCode !== 200) {
            reject(new Error(`GitHub API returned ${res.statusCode} for ${u}`))
            return
          }
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

function downloadFile(url: string, dest: string, onProgress: (frac: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(u, { headers: { 'User-Agent': 'nunu-launcher/1.0' } }, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          if (res.headers.location) { doGet(res.headers.location); return }
        }
        if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return }
        const total = parseInt(res.headers['content-length'] ?? '0', 10)
        let received = 0
        const out = createWriteStream(dest)
        res.on('data', (chunk: Buffer) => {
          received += chunk.length
          if (total > 0) onProgress(received / total)
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
