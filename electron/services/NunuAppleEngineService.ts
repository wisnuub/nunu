import { app } from 'electron'
import { existsSync, mkdirSync, chmodSync, createWriteStream, readFileSync, writeFileSync } from 'fs'
import { join } from 'path'
import { get as httpsGet } from 'https'
import { renameSync } from 'fs'

export interface EngineRelease {
  tag_name: string
  assets: Array<{
    name: string
    browser_download_url: string
    size: number
  }>
}

export interface EngineCheckResult {
  installed: boolean
  version: string | null
  binaryPath: string
}

export interface EngineUpdateResult {
  hasUpdate: boolean
  installedVersion: string | null
  latestVersion: string | null
  downloadUrl: string | null
  error?: string
}

export class NunuAppleEngineService {
  private readonly engineDir: string
  readonly binaryPath: string
  private readonly versionFile: string
  private readonly apiUrl = 'https://api.github.com/repos/wisnuub/nunu-apple/releases?per_page=1'

  constructor() {
    this.engineDir = join(app.getPath('home'), '.nunu', 'engines', 'nunu-apple')
    // Binary lives inside an app bundle so entitlements + Info.plist are present
    this.binaryPath = join(this.engineDir, 'NunuVM.app', 'Contents', 'MacOS', 'NunuVM')
    this.versionFile = join(this.engineDir, 'version.txt')
  }

  check(): EngineCheckResult {
    const installed = existsSync(this.binaryPath)
    let version: string | null = null
    if (installed && existsSync(this.versionFile)) {
      try {
        version = readFileSync(this.versionFile, 'utf-8').trim()
      } catch { /* ignore */ }
    }
    return { installed, version, binaryPath: this.binaryPath }
  }

  async checkForUpdate(): Promise<EngineUpdateResult> {
    const { installed, version: installedVersion } = this.check()
    try {
      const releases = await fetchJson<EngineRelease[]>(this.apiUrl)
      const release = releases[0]
      if (!release) {
        return { hasUpdate: false, installedVersion, latestVersion: null, downloadUrl: null }
      }

      const latestVersion = release.tag_name.replace(/^v/, '')
      // Not installed counts as "needs install", not as hasUpdate
      const hasUpdate = installed && installedVersion !== null
        ? this.isNewer(latestVersion, installedVersion)
        : false

      const asset = release.assets.find((a) => a.name === 'NunuVM')
      const downloadUrl = asset?.browser_download_url ?? null

      return { hasUpdate, installedVersion, latestVersion, downloadUrl }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err)
      return { hasUpdate: false, installedVersion, latestVersion: null, downloadUrl: null, error: message }
    }
  }

  async install(
    downloadUrl: string,
    version: string,
    onProgress: (pct: number, status: string) => void,
  ): Promise<void> {
    if (!existsSync(this.engineDir)) mkdirSync(this.engineDir, { recursive: true })

    const tmpPath = this.binaryPath + '.tmp'
    onProgress(0, 'Downloading nunu-apple engine…')

    await downloadFile(downloadUrl, tmpPath, (frac) => {
      onProgress(Math.round(frac * 95), `Downloading… ${Math.round(frac * 100)}%`)
    })

    renameSync(tmpPath, this.binaryPath)
    chmodSync(this.binaryPath, 0o755)
    writeFileSync(this.versionFile, version)

    onProgress(100, 'Engine installed')
  }

  private isNewer(latest: string, installed: string): boolean {
    const parse = (v: string) => v.split('.').map(Number)
    const l = parse(latest)
    const i = parse(installed)
    for (let idx = 0; idx < Math.max(l.length, i.length); idx++) {
      if ((l[idx] ?? 0) > (i[idx] ?? 0)) return true
      if ((l[idx] ?? 0) < (i[idx] ?? 0)) return false
    }
    return false
  }
}

function fetchJson<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    httpsGet(
      url,
      { headers: { 'User-Agent': 'nunu-launcher/1.0', Accept: 'application/vnd.github+json' } },
      (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          const loc = res.headers.location
          if (loc) return fetchJson<T>(loc).then(resolve).catch(reject)
        }
        if (res.statusCode !== 200) { reject(new Error(`GitHub API returned ${res.statusCode}`)); return }
        let raw = ''
        res.on('data', (chunk: string) => (raw += chunk))
        res.on('end', () => { try { resolve(JSON.parse(raw) as T) } catch (e) { reject(e) } })
        res.on('error', reject)
      },
    ).on('error', reject)
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
