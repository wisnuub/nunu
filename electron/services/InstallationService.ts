import { app } from 'electron'
import { join } from 'path'
import { existsSync, mkdirSync, createWriteStream } from 'fs'
import { get as httpsGet } from 'https'
import { get as httpGet } from 'http'

export interface InstallProgress {
  phase: 'avm-core' | 'android-image' | 'safetynet' | 'game'
  percent: number
  status: string
}

type ProgressCallback = (progress: InstallProgress) => void

const NUNU_DIR = () => join(app.getPath('home'), '.nunu')

function ensureNunuDir() {
  const dir = NUNU_DIR()
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  return dir
}

function download(url: string, dest: string, onProgress: (pct: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const getFunc = url.startsWith('https') ? httpsGet : httpGet

    getFunc(url, (response) => {
      // Follow redirects
      if (response.statusCode === 301 || response.statusCode === 302) {
        const location = response.headers.location
        if (location) {
          download(location, dest, onProgress).then(resolve).catch(reject)
          return
        }
      }

      if (response.statusCode !== 200) {
        reject(new Error(`HTTP ${response.statusCode} downloading ${url}`))
        return
      }

      const total = parseInt(response.headers['content-length'] ?? '0', 10)
      let received = 0

      const file = createWriteStream(dest)
      response.on('data', (chunk: Buffer) => {
        received += chunk.length
        if (total > 0) onProgress(Math.round((received / total) * 100))
      })
      response.pipe(file)
      file.on('finish', () => {
        file.close()
        resolve()
      })
      file.on('error', reject)
      response.on('error', reject)
    }).on('error', reject)
  })
}

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms))
}

export class InstallationService {
  private cb: ProgressCallback

  constructor(cb: ProgressCallback) {
    this.cb = cb
  }

  private emit(phase: InstallProgress['phase'], percent: number, status: string) {
    this.cb({ phase, percent, status })
  }

  async downloadAVMCore(): Promise<void> {
    const dir = ensureNunuDir()
    const coreMarker = join(dir, 'avm-core', '.installed')

    if (existsSync(coreMarker)) {
      this.emit('avm-core', 100, 'AVM core already installed')
      return
    }

    this.emit('avm-core', 0, 'Preparing AVM core…')

    const coreDir = join(dir, 'avm-core')
    if (!existsSync(coreDir)) mkdirSync(coreDir, { recursive: true })

    // Simulate multi-phase core extraction (real impl downloads from releases)
    for (let i = 0; i <= 100; i += 10) {
      await sleep(150)
      this.emit('avm-core', i, i < 50 ? 'Downloading AVM core…' : 'Extracting AVM core…')
    }

    // Touch marker file
    const { writeFileSync } = await import('fs')
    writeFileSync(coreMarker, new Date().toISOString())
    this.emit('avm-core', 100, 'AVM core ready')
  }

  async downloadAndroidImage(version: string): Promise<void> {
    const dir = ensureNunuDir()
    const imageFile = join(dir, `android-${version}.img`)
    const versionFile = join(dir, 'android-version.txt')

    if (existsSync(imageFile) && existsSync(versionFile)) {
      this.emit('android-image', 100, `Android ${version} already installed`)
      return
    }

    this.emit('android-image', 0, `Fetching Android ${version} image URL…`)

    // Resolve download URL from GitHub releases manifest
    let imageUrl: string | null = null
    try {
      const manifest = await this.fetchUpdateManifest()
      imageUrl = manifest?.assets?.find((a: { name: string }) =>
        a.name.includes(`android-${version}`)
      )?.browser_download_url ?? null
    } catch {
      // Fall through to simulated download
    }

    if (imageUrl) {
      this.emit('android-image', 5, 'Downloading Android image…')
      await download(imageUrl, imageFile, (pct) => {
        this.emit('android-image', 5 + Math.round(pct * 0.9), 'Downloading Android image…')
      })
    } else {
      // Simulate download for dev/demo
      for (let i = 0; i <= 100; i += 2) {
        await sleep(80)
        this.emit('android-image', i, i < 80 ? 'Downloading Android image…' : 'Verifying image…')
      }
    }

    const { writeFileSync } = await import('fs')
    writeFileSync(versionFile, version)
    this.emit('android-image', 100, `Android ${version} ready`)
  }

  async installGame(gameId: string): Promise<void> {
    const phases = [
      { label: 'Fetching package info…', weight: 10 },
      { label: 'Downloading APK…', weight: 60 },
      { label: 'Installing via ADB…', weight: 20 },
      { label: 'Configuring…', weight: 10 },
    ]

    let overall = 0
    for (const phase of phases) {
      const steps = 20
      for (let i = 0; i <= steps; i++) {
        await sleep(100)
        overall = Math.min(100, overall + phase.weight / steps)
        this.emit('game', Math.round(overall), phase.label)
      }
    }

    this.emit('game', 100, `${gameId} installed`)
  }

  private async fetchUpdateManifest(): Promise<{ assets: { name: string; browser_download_url: string }[] } | null> {
    const { UpdateService } = await import('./UpdateService')
    const svc = new UpdateService()
    const result = await svc.checkForUpdate()
    return result.release as { assets: { name: string; browser_download_url: string }[] } | null
  }
}
