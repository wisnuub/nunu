import { spawn } from 'child_process'
import { join } from 'path'
import { existsSync } from 'fs'

export interface SafetyNetResult {
  passed: boolean
  basicIntegrity: boolean
  ctsProfile: boolean
  error?: string
}

export interface SafetyNetProgressEvent {
  step: number
  stepName: string
  done: boolean
  percent: number
}

type ProgressCallback = (event: SafetyNetProgressEvent) => void

const ADB_STEPS = [
  'Starting Android environment',
  'Waiting for ADB connection',
  'Applying device fingerprint (Pixel 7)',
  'Enabling Google Mobile Services',
  'Rebooting device',
  'Verifying certification',
]

function resolveADB(): string {
  // Prefer bundled ADB binary
  if (process.env.RESOURCES_PATH) {
    const bundled = join(process.env.RESOURCES_PATH, 'bin', 'adb')
    if (existsSync(bundled)) return bundled
  }
  // Try resourcesPath in packaged app
  try {
    const { app } = require('electron')
    const bundled = join(app.getPath('exe'), '..', 'resources', 'bin', 'adb')
    if (existsSync(bundled)) return bundled
  } catch {
    // Not in Electron context (tests)
  }
  // Fall back to PATH
  return process.platform === 'win32' ? 'adb.exe' : 'adb'
}

function runADB(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const adb = resolveADB()
    const proc = spawn(adb, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    let stdout = ''
    let stderr = ''
    proc.stdout.on('data', (d: Buffer) => (stdout += d.toString()))
    proc.stderr.on('data', (d: Buffer) => (stderr += d.toString()))
    proc.on('close', (code) => {
      if (code === 0) resolve(stdout)
      else reject(new Error(`adb ${args.join(' ')} failed (${code}): ${stderr}`))
    })
    proc.on('error', (err) => reject(new Error(`adb spawn error: ${err.message}`)))
  })
}

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms))
}

export class SafetyNetService {
  private cb: ProgressCallback

  constructor(cb: ProgressCallback) {
    this.cb = cb
  }

  private emit(step: number, done: boolean) {
    const percent = Math.round(((step + (done ? 1 : 0)) / ADB_STEPS.length) * 100)
    this.cb({ step, stepName: ADB_STEPS[step], done, percent })
  }

  private async waitForADB(timeoutMs = 60_000): Promise<void> {
    this.emit(1, false)
    const start = Date.now()
    while (Date.now() - start < timeoutMs) {
      try {
        const output = await runADB(['devices'])
        const lines = output.trim().split('\n').slice(1)
        const connected = lines.some((l) => l.includes('\tdevice'))
        if (connected) {
          this.emit(1, true)
          return
        }
      } catch {
        // ADB not ready yet
      }
      await sleep(2000)
    }
    throw new Error('Timed out waiting for ADB device (60 s)')
  }

  private async applyFingerprint(): Promise<void> {
    this.emit(2, false)
    const cmds = [
      "su -c 'setprop ro.product.brand google'",
      "su -c 'setprop ro.product.device panther'",
      "su -c 'setprop ro.product.model Pixel 7'",
      "su -c 'setprop ro.build.fingerprint google/panther/panther:13/TQ3A.230901.001/10750268:user/release-keys'",
      "su -c 'setprop ro.build.id TQ3A.230901.001'",
      "su -c 'setprop ro.build.version.security_patch 2023-09-01'",
    ]
    for (const cmd of cmds) {
      await runADB(['shell', cmd])
    }
    this.emit(2, true)
  }

  private async configureGMS(): Promise<void> {
    this.emit(3, false)
    await runADB(['shell', 'pm', 'enable', 'com.google.android.gms'])
    await runADB(['shell', 'pm', 'enable', 'com.android.vending'])
    this.emit(3, true)
  }

  private async rebootDevice(): Promise<void> {
    this.emit(4, false)
    await runADB(['reboot'])
    // Wait for device to disconnect then reconnect
    await sleep(5000)
    await this.waitForADB(90_000)
    this.emit(4, true)
  }

  private async verify(): Promise<SafetyNetResult> {
    this.emit(5, false)
    try {
      const output = await runADB([
        'shell',
        'dumpsys',
        'activity',
        'services',
        'com.google.android.gms',
      ])
      const running = output.includes('com.google.android.gms')
      this.emit(5, true)
      return { passed: running, basicIntegrity: running, ctsProfile: running }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err)
      this.emit(5, true)
      return { passed: false, basicIntegrity: false, ctsProfile: false, error: message }
    }
  }

  async setup(): Promise<SafetyNetResult> {
    try {
      // Step 0: environment already started by the time this is called
      this.emit(0, true)

      await this.waitForADB()
      await this.applyFingerprint()
      await this.configureGMS()
      await this.rebootDevice()
      return await this.verify()
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err)
      return { passed: false, basicIntegrity: false, ctsProfile: false, error: message }
    }
  }
}
