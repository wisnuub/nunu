/**
 * KernelDownloadService — downloads a custom vmlinuz_full from wisnuub/nunu-kernel
 * GitHub releases and stores it at ~/.nunu/kernel/vmlinuz_full.
 *
 * findCuttlefishImages() in main.ts checks this path first and passes it to
 * nunu-apple via --kernel, replacing the stock Google Cuttlefish kernel.
 *
 * The custom kernel includes KernelSU (built-in, not LKM) + SUSFS.
 */

import { app } from 'electron'
import { existsSync, mkdirSync, createWriteStream, readFileSync, writeFileSync } from 'fs'
import { join } from 'path'
import { get as httpsGet } from 'https'

export type KernelDownloadProgressFn = (pct: number, status: string) => void

interface GHRelease {
  tag_name: string
  published_at: string
  assets: Array<{ name: string; browser_download_url: string; size: number }>
}

export interface KernelInfo {
  installed: boolean
  version: string | null     // e.g. "v1.0.0"
  publishedAt: string | null // ISO date string
}

function fetchJson<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(u, {
        headers: { 'User-Agent': 'nunu-launcher/1.0', Accept: 'application/vnd.github+json' },
      }, (res) => {
        if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
          doGet(res.headers.location); return
        }
        if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return }
        let raw = ''
        res.on('data', (c: string) => (raw += c))
        res.on('end', () => { try { resolve(JSON.parse(raw) as T) } catch (e) { reject(e) } })
        res.on('error', reject)
      }).on('error', reject)
    }
    doGet(url)
  })
}

function downloadFile(
  url: string, dest: string,
  onProgress?: (frac: number, receivedBytes: number, totalBytes: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const doGet = (u: string) => {
      httpsGet(u, { headers: { 'User-Agent': 'nunu-launcher/1.0' } }, (res) => {
        if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
          doGet(res.headers.location); return
        }
        if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return }
        const total = parseInt(res.headers['content-length'] ?? '0', 10)
        let received = 0
        const out = createWriteStream(dest)
        res.on('data', (chunk: Buffer) => {
          received += chunk.length
          out.write(chunk)
          if (total > 0) onProgress?.(received / total, received, total)
        })
        res.on('end', () => out.end(() => resolve()))
        res.on('error', (e) => { out.destroy(); reject(e) })
        out.on('error', reject)
      }).on('error', reject)
    }
    doGet(url)
  })
}

export class KernelDownloadService {
  readonly kernelDir: string
  readonly kernelPath: string       // vmlinuz_full — passed to nunu-apple --kernel
  private readonly metaPath: string // stores {version, publishedAt}

  constructor() {
    this.kernelDir  = join(app.getPath('home'), '.nunu', 'kernel')
    this.kernelPath = join(this.kernelDir, 'vmlinuz_full')
    this.metaPath   = join(this.kernelDir, 'release.json')
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  installedInfo(): KernelInfo {
    if (!existsSync(this.kernelPath)) return { installed: false, version: null, publishedAt: null }
    try {
      const meta = JSON.parse(readFileSync(this.metaPath, 'utf-8'))
      return { installed: true, version: meta.version ?? null, publishedAt: meta.publishedAt ?? null }
    } catch {
      return { installed: true, version: null, publishedAt: null }
    }
  }

  async checkUpdate(): Promise<{ hasUpdate: boolean; latestVersion: string; publishedAt: string }> {
    const releases = await fetchJson<GHRelease[]>(
      'https://api.github.com/repos/wisnuub/nunu-kernel/releases?per_page=1'
    )
    if (!releases.length) throw new Error('No releases found in wisnuub/nunu-kernel')
    const latest = releases[0]
    const current = this.installedInfo()
    return {
      hasUpdate: current.version !== latest.tag_name,
      latestVersion: latest.tag_name,
      publishedAt: latest.published_at,
    }
  }

  async download(
    onProgress: KernelDownloadProgressFn,
  ): Promise<{ success: boolean; version?: string; error?: string }> {
    try {
      if (!existsSync(this.kernelDir)) mkdirSync(this.kernelDir, { recursive: true })

      onProgress(2, 'Fetching latest kernel release…')
      const releases = await fetchJson<GHRelease[]>(
        'https://api.github.com/repos/wisnuub/nunu-kernel/releases?per_page=1'
      )
      if (!releases.length) {
        return { success: false, error: 'No releases found in wisnuub/nunu-kernel. Trigger the CI build first.' }
      }

      const rel = releases[0]
      const asset = rel.assets.find((a) => a.name === 'vmlinuz_full')
      if (!asset) {
        return {
          success: false,
          error: `Release ${rel.tag_name} has no vmlinuz_full asset. The CI build may still be in progress.`,
        }
      }

      const sizeMB = (asset.size / 1024 / 1024).toFixed(1)
      onProgress(5, `Downloading kernel ${rel.tag_name} (${sizeMB} MB)…`)

      const tmpPath = this.kernelPath + '.tmp'
      await downloadFile(asset.browser_download_url, tmpPath, (frac, recv, total) => {
        const pct  = 5 + Math.round(frac * 90)
        const recvMB = (recv / 1024 / 1024).toFixed(1)
        const totMB  = (total / 1024 / 1024).toFixed(1)
        onProgress(pct, `Downloading… ${recvMB} / ${totMB} MB`)
      })

      // Atomically replace the old kernel
      const { renameSync } = await import('fs')
      renameSync(tmpPath, this.kernelPath)

      // Save metadata
      writeFileSync(this.metaPath, JSON.stringify({
        version: rel.tag_name,
        publishedAt: rel.published_at,
        assetName: asset.name,
        downloadedAt: new Date().toISOString(),
      }))

      onProgress(100, `Kernel ${rel.tag_name} ready — restart the VM to apply.`)
      return { success: true, version: rel.tag_name }
    } catch (err) {
      return { success: false, error: err instanceof Error ? err.message : String(err) }
    }
  }

  remove(): void {
    const { rmSync } = require('fs')
    rmSync(this.kernelPath, { force: true })
    rmSync(this.metaPath,   { force: true })
  }
}
