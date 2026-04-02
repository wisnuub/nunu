import { app } from 'electron'
import { join } from 'path'
import { existsSync, readFileSync } from 'fs'
import { get as httpsGet } from 'https'

export interface AndroidRelease {
  tag_name: string
  name: string
  body: string
  published_at: string
  assets: Array<{
    name: string
    browser_download_url: string
    size: number
  }>
}

export interface UpdateCheckResult {
  hasUpdate: boolean
  release: AndroidRelease | null
  installedVersion: string | null
  error?: string
}

function fetchJson<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    httpsGet(
      url,
      {
        headers: {
          'User-Agent': 'nunu-launcher/1.0',
          Accept: 'application/vnd.github+json',
        },
      },
      (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          const loc = res.headers.location
          if (loc) return fetchJson<T>(loc).then(resolve).catch(reject)
        }
        if (res.statusCode !== 200) {
          reject(new Error(`GitHub API returned ${res.statusCode}`))
          return
        }
        let raw = ''
        res.on('data', (chunk: string) => (raw += chunk))
        res.on('end', () => {
          try {
            resolve(JSON.parse(raw) as T)
          } catch (e) {
            reject(e)
          }
        })
        res.on('error', reject)
      }
    ).on('error', reject)
  })
}

export class UpdateService {
  private readonly apiUrl =
    'https://api.github.com/repos/wisnuub/AVM/releases/latest'

  async checkForUpdate(): Promise<UpdateCheckResult> {
    const installedVersion = this.getInstalledVersion()

    try {
      const release = await fetchJson<AndroidRelease>(this.apiUrl)
      const latestTag = release.tag_name.replace(/^v/, '')
      const hasUpdate =
        installedVersion === null || this.isNewer(latestTag, installedVersion)

      return { hasUpdate, release, installedVersion }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err)
      return {
        hasUpdate: false,
        release: null,
        installedVersion,
        error: message,
      }
    }
  }

  private getInstalledVersion(): string | null {
    const versionFile = join(app.getPath('home'), '.nunu', 'android-version.txt')
    if (!existsSync(versionFile)) return null
    try {
      return readFileSync(versionFile, 'utf-8').trim()
    } catch {
      return null
    }
  }

  private isNewer(latest: string, installed: string): boolean {
    const parse = (v: string) => v.split('.').map(Number)
    const l = parse(latest)
    const i = parse(installed)
    for (let idx = 0; idx < Math.max(l.length, i.length); idx++) {
      const lv = l[idx] ?? 0
      const iv = i[idx] ?? 0
      if (lv > iv) return true
      if (lv < iv) return false
    }
    return false
  }
}
