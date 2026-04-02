import { existsSync, createReadStream } from 'fs'
import { spawn, spawnSync } from 'child_process'
import { createHash } from 'crypto'
import { join } from 'path'

export class PatchService {
  private readonly xdeltaCandidates: string[]

  constructor() {
    if (process.platform === 'win32') {
      this.xdeltaCandidates = [
        'xdelta3',
        'C:\\Program Files\\xdelta3\\xdelta3.exe',
        'C:\\Program Files (x86)\\xdelta3\\xdelta3.exe',
      ]
    } else {
      this.xdeltaCandidates = [
        'xdelta3',
        '/opt/homebrew/bin/xdelta3',
        '/usr/local/bin/xdelta3',
        '/usr/bin/xdelta3',
      ]
    }
  }

  isXdelta3Available(): boolean {
    for (const candidate of this.xdeltaCandidates) {
      try {
        const result = spawnSync(candidate, ['-V'], { stdio: 'ignore' })
        if (result.status === 0 || result.error === undefined) {
          // Check if binary exists (for absolute paths)
          if (candidate.includes('/') || candidate.includes('\\')) {
            if (existsSync(candidate)) return true
          } else {
            // It's a PATH lookup; spawnSync success means it's available
            if (!result.error) return true
          }
        }
      } catch {
        // Not available at this path
      }
    }
    return false
  }

  private getXdelta3Path(): string | null {
    for (const candidate of this.xdeltaCandidates) {
      try {
        if (candidate.includes('/') || candidate.includes('\\')) {
          if (existsSync(candidate)) return candidate
        } else {
          const result = spawnSync(candidate, ['-V'], { stdio: 'ignore' })
          if (!result.error) return candidate
        }
      } catch {
        // continue
      }
    }
    return null
  }

  applyPatch(source: string, patch: string, dest: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const xdelta = this.getXdelta3Path()
      if (!xdelta) {
        reject(new Error('xdelta3 not found; falling back to full download'))
        return
      }

      // xdelta3 -d -s <source> <patch> <dest>
      const proc = spawn(xdelta, ['-d', '-f', '-s', source, patch, dest], {
        stdio: ['ignore', 'pipe', 'pipe'],
      })

      let stderr = ''
      proc.stderr?.on('data', (d: Buffer) => (stderr += d.toString()))

      proc.on('close', (code) => {
        if (code === 0) {
          resolve()
        } else {
          reject(new Error(`xdelta3 exited with code ${code}: ${stderr}`))
        }
      })

      proc.on('error', reject)
    })
  }

  verifySHA256(file: string, expected: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
      const hash = createHash('sha256')
      const stream = createReadStream(file)
      stream.on('data', (chunk: Buffer) => hash.update(chunk))
      stream.on('end', () => {
        const digest = hash.digest('hex')
        resolve(digest.toLowerCase() === expected.toLowerCase())
      })
      stream.on('error', reject)
    })
  }
}
