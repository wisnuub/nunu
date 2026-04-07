import { app, BrowserWindow, ipcMain, shell, nativeImage } from 'electron'
import { join } from 'path'
import { existsSync, readFileSync, writeFileSync, mkdirSync, createWriteStream, renameSync } from 'fs'
import { spawn, spawnSync, ChildProcess } from 'child_process'
import { get as httpsGet } from 'https'
import { get as httpGet } from 'http'
import Store from 'electron-store'
import { InstallationService } from './services/InstallationService'
import { UpdateService } from './services/UpdateService'
import { SafetyNetService } from './services/SafetyNetService'
import { startGoogleSignIn } from './services/GoogleAuthService'
import { NunuAppleEngineService } from './services/NunuAppleEngineService'

// Handle Windows NSIS squirrel events
if (process.platform === 'win32') {
  const squirrelStartup = require('electron-squirrel-startup')
  if (squirrelStartup) app.quit()
}

const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged

const store = new Store<Record<string, unknown>>()

// ── Config helpers (~/.nunu/config.json) ─────────────────────────────────────

const nunuConfigPath = () => join(app.getPath('home'), '.nunu', 'config.json')

function readNunuConfig(): Record<string, unknown> {
  try {
    const p = nunuConfigPath()
    if (existsSync(p)) return JSON.parse(readFileSync(p, 'utf-8')) as Record<string, unknown>
  } catch { /* ignore */ }
  return {}
}

function writeNunuConfig(data: Record<string, unknown>) {
  const dir = join(app.getPath('home'), '.nunu')
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  writeFileSync(nunuConfigPath(), JSON.stringify(data, null, 2))
}

// ── VM process tracker ───────────────────────────────────────────────────────

let vmProcess: ChildProcess | null = null
let runningGameId: string | null = null
let runningGameName: string | null = null
let runningGameConfig: { memoryMb: number; cores: number } | null = null

let mainWindow: BrowserWindow | null = null

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 1024,
    minHeight: 680,
    frame: false,
    transparent: false,
    backgroundColor: '#0D0F14',
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: -100, y: -100 }, // hide native dots, we render our own
    webPreferences: {
      preload: join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,
      sandbox: false,
    },
    show: false,
  })

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show()
  })

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173')
    mainWindow.webContents.openDevTools({ mode: 'detach' })
  } else {
    mainWindow.loadFile(join(__dirname, '../dist/index.html'))
  }

  mainWindow.on('closed', () => {
    mainWindow = null
  })

  // Set macOS dock icon if bundled
  if (process.platform === 'darwin') {
    const iconPath = join(__dirname, '../assets/icon.icns')
    if (existsSync(iconPath)) {
      const icon = nativeImage.createFromPath(iconPath)
      app.dock.setIcon(icon)
    }
  }
}

// ── Window control IPC ──────────────────────────────────────────────────────

ipcMain.handle('app:version', () => app.getVersion())
ipcMain.handle('app:openExternal', (_event, url: string) => shell.openExternal(url))

ipcMain.on('app:minimize', () => mainWindow?.minimize())
ipcMain.on('app:maximize', () => {
  if (mainWindow?.isMaximized()) {
    mainWindow.unmaximize()
  } else {
    mainWindow?.maximize()
  }
})
ipcMain.on('app:close', () => mainWindow?.close())

// ── Store IPC ────────────────────────────────────────────────────────────────

ipcMain.handle('store:get', (_event, key: string) => {
  return store.get(key)
})

ipcMain.handle('store:set', (_event, key: string, value: unknown) => {
  store.set(key, value)
})

// ── Installation IPC ─────────────────────────────────────────────────────────

ipcMain.handle('install:start', async (_event, options: { androidVersion?: string }) => {
  if (!mainWindow) return { success: false, error: 'No window' }

  const send = (percent: number, status: string) =>
    mainWindow?.webContents.send('install:progress', { phase: 'android-image', percent, status })

  const apiVersion = options.androidVersion ?? '34'
  const arch = sysImageArch()
  const sdkRoot = nunuSdkRoot()
  const imageDir = join(sdkRoot, 'system-images', `android-${apiVersion}`, 'google_apis_playstore', arch)

  // Already installed
  if (existsSync(imageDir)) {
    send(100, 'Android environment already installed')
    return { success: true }
  }

  // Check Java is available before downloading anything
  const hasJava = await checkJavaInstalled()
  if (!hasJava) {
    return {
      success: false,
      error: 'Java not found.\n\nThe Android SDK requires Java (JDK 17+) to install.\n\nmacOS: brew install --cask temurin\nWindows: Download from adoptium.net',
    }
  }

  try {
    // ── 1. Download cmdline-tools ─────────────────────────────────────────
    const platformStr = process.platform === 'win32' ? 'win' : process.platform === 'darwin' ? 'mac' : 'linux'
    const cmdlineToolsUrl = `https://dl.google.com/android/repository/commandlinetools-${platformStr}-11076708_latest.zip`
    const zipPath = join(app.getPath('temp'), 'cmdline-tools.zip')

    send(0, 'Downloading Android SDK tools…')
    await downloadFile(cmdlineToolsUrl, zipPath, (pct) =>
      send(Math.round(pct * 0.25), 'Downloading Android SDK tools…')
    )

    // ── 2. Extract cmdline-tools ──────────────────────────────────────────
    send(25, 'Extracting SDK tools…')
    const cmdlineToolsDir = join(sdkRoot, 'cmdline-tools')
    if (!existsSync(cmdlineToolsDir)) mkdirSync(cmdlineToolsDir, { recursive: true })
    await extractZip(zipPath, cmdlineToolsDir)

    // sdkmanager unzips as cmdline-tools/cmdline-tools/ — rename inner dir to 'latest'
    const innerDir = join(cmdlineToolsDir, 'cmdline-tools')
    const latestDir = join(cmdlineToolsDir, 'latest')
    if (existsSync(innerDir) && !existsSync(latestDir)) renameSync(innerDir, latestDir)

    // ── 3. Accept licenses ────────────────────────────────────────────────
    send(28, 'Accepting licenses…')
    const sdkmanagerBin = join(latestDir, 'bin', process.platform === 'win32' ? 'sdkmanager.bat' : 'sdkmanager')
    try {
      await runSdkManager(sdkmanagerBin, sdkRoot, ['--licenses'], 'y\n'.repeat(20))
    } catch { /* non-fatal — may already be accepted */ }

    // ── 4. Install emulator + platform-tools + system image ───────────────
    const packages = [
      'emulator',
      'platform-tools',
      `system-images;android-${apiVersion};google_apis_playstore;${arch}`,
    ]
    send(30, 'Installing Android emulator…')
    let lastPct = 30
    await runSdkManager(sdkmanagerBin, sdkRoot, ['--install', ...packages], 'y\n'.repeat(10), (line) => {
      const m = line.match(/\[\s*(\d+)%\]/)
      if (m) {
        const pct = parseInt(m[1])
        const mapped = 30 + Math.round(pct * 0.7)
        if (mapped > lastPct) {
          lastPct = mapped
          send(mapped, pct < 30
            ? 'Installing Android emulator…'
            : pct < 70
            ? `Downloading Android system image… ${pct}%`
            : `Verifying packages… ${pct}%`)
        }
      }
    })

    send(100, 'Android environment ready')
    return { success: true }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { success: false, error: message }
  }
})

// Game ID → Play Store package mapping (mirrors games.ts)
const GAME_PACKAGES: Record<string, string> = {
  'pubg-mobile':        'com.tencent.ig',
  'genshin-impact':     'com.miHoYo.GenshinImpact',
  'teamfight-tactics':  'com.riotgames.league.teamfighttactics',
  'mobile-legends':     'com.mobile.legends',
  'cod-mobile':         'com.activision.callofduty.shooter',
  'honkai-star-rail':   'com.HoYoverse.hkrpgoversea',
}

ipcMain.handle('install:game', async (_event, gameId: string) => {
  if (!mainWindow) return { success: false, error: 'No window' }

  const packageId = GAME_PACKAGES[gameId]
  if (!packageId) return { success: false, error: `Unknown game: ${gameId}` }

  const send = (percent: number, status: string) =>
    mainWindow?.webContents.send('install:progress', { phase: 'game', percent, status })

  // Boot VM if not already running
  if (!vmProcess) {
    const avmBin = findAvmBinary()
    if (!avmBin) return { success: false, error: 'AVM engine not found. Please reinstall nunu.' }
    const imageDir = findAndroidImageDir()
    if (!imageDir) return {
      success: false,
      error: 'Android image not found.\nRun: sdkmanager "system-images;android-34;google_apis_playstore;arm64-v8a"',
    }

    try {
      send(5, 'Starting Android…')
      mainWindow.webContents.send('vm:status', { status: 'booting' })
      vmProcess = spawn(avmBin, ['--image', imageDir, '--memory', '4096', '--cores', '4'], {
        detached: false, stdio: 'ignore', env: avmSpawnEnv(),
      })
      runningGameId = null
      runningGameName = null
      runningGameConfig = { memoryMb: 4096, cores: 4 }
      vmProcess.on('exit', () => {
        vmProcess = null; runningGameId = null; runningGameName = null; runningGameConfig = null
        mainWindow?.webContents.send('vm:status', { status: 'stopped' })
      })
      vmProcess.on('error', () => {
        vmProcess = null; runningGameId = null; runningGameName = null; runningGameConfig = null
      })
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err)
      return { success: false, error: message }
    }
  }

  send(20, 'Booting Android…')
  const serial = await waitForAndroidBoot(120_000)
  if (!serial) return { success: false, error: 'Android took too long to boot.' }

  mainWindow.webContents.send('vm:status', { status: 'ready' })
  send(70, 'Opening Play Store…')

  // Open Play Store to the game's page
  await runAdb(['-s', serial, 'shell', 'am', 'start',
    '-a', 'android.intent.action.VIEW',
    '-d', `market://details?id=${packageId}`,
  ])

  send(100, 'Play Store opened — install from there')
  return { success: true }
})

// ── Engine IPC (macOS: nunu-apple) ────────────────────────────────────────────

ipcMain.handle('engine:check', () => {
  if (process.platform !== 'darwin') return { installed: false, version: null, binaryPath: '' }
  const svc = new NunuAppleEngineService()
  return svc.check()
})

ipcMain.handle('engine:check-update', async () => {
  if (process.platform !== 'darwin') return { hasUpdate: false, installedVersion: null, latestVersion: null, downloadUrl: null }
  const svc = new NunuAppleEngineService()
  return svc.checkForUpdate()
})

ipcMain.handle('engine:install', async (_event, downloadUrl: string, version: string) => {
  if (!mainWindow || process.platform !== 'darwin') return { success: false, error: 'Not supported' }
  const svc = new NunuAppleEngineService()
  try {
    await svc.install(downloadUrl, version, (pct, status) => {
      mainWindow?.webContents.send('engine:progress', { percent: pct, status })
    })
    return { success: true }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { success: false, error: message }
  }
})

// ── Update IPC ───────────────────────────────────────────────────────────────

ipcMain.handle('update:check', async () => {
  try {
    const svc = new UpdateService()
    return await svc.checkForUpdate()
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { hasUpdate: false, release: null, error: message }
  }
})

// ── SafetyNet IPC ────────────────────────────────────────────────────────────

ipcMain.handle('safetynet:setup', async () => {
  if (!mainWindow) return { passed: false, error: 'No window' }

  const svc = new SafetyNetService((event) => {
    mainWindow?.webContents.send('safetynet:progress', event)
  })

  try {
    return await svc.setup()
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { passed: false, basicIntegrity: false, ctsProfile: false, error: message }
  }
})

// ── Google Sign-In IPC ───────────────────────────────────────────────────────

ipcMain.handle('google:signin', async () => {
  try {
    const result = await startGoogleSignIn()
    return { success: true, ...result }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { success: false, error: message }
  }
})

// ── Play Store art scraping ──────────────────────────────────────────────────

const artCache  = new Map<string, string | null>()
const bannerCache = new Map<string, string | null>()
const htmlCache = new Map<string, string>()

async function fetchPlayStorePage(packageId: string): Promise<string> {
  if (htmlCache.has(packageId)) return htmlCache.get(packageId)!
  const url = `https://play.google.com/store/apps/details?id=${packageId}&hl=en`
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  })
  const html = await res.text()
  htmlCache.set(packageId, html)
  return html
}

ipcMain.handle('game:fetchArt', async (_event, packageId: string) => {
  if (artCache.has(packageId)) return artCache.get(packageId)
  try {
    const html = await fetchPlayStorePage(packageId)
    const match = html.match(/<meta property="og:image" content="([^"]+)"/)
    if (match) {
      const iconUrl = match[1].replace(/=w\d+-h\d+(-rw)?/, '=w512-h512-rw')
      artCache.set(packageId, iconUrl)
      return iconUrl
    }
  } catch { /* ignore */ }
  artCache.set(packageId, null)
  return null
})

ipcMain.handle('game:fetchBanner', async (_event, packageId: string) => {
  if (bannerCache.has(packageId)) return bannerCache.get(packageId)
  try {
    const html = await fetchPlayStorePage(packageId)

    // The icon hash — exclude it from candidates
    const iconMatch = html.match(/<meta property="og:image" content="([^"]+)"/)
    const iconHash = iconMatch ? iconMatch[1].split('/').pop()?.split('=')[0] : null

    // Extract all play-lh URLs with their embedded size hints (=wW-hH)
    // Play Store encodes: icon = square (w==h), feature graphic = landscape (w >> h, typically 1024x500)
    const matches = [...html.matchAll(
      /https:\/\/play-lh\.googleusercontent\.com\/([^"'\s\\]+)/g
    )]

    interface ImageCandidate { base: string; w: number; h: number }
    const candidates: ImageCandidate[] = []
    const seen = new Set<string>()

    for (const m of matches) {
      const full = `https://play-lh.googleusercontent.com/${m[1]}`
      const base = full.split('=')[0]
      if (seen.has(base)) continue
      seen.add(base)

      // Skip the app icon
      if (iconHash && base.includes(iconHash)) continue

      // Parse embedded dimensions if present (e.g. =w2560-h1440-rw)
      const dimMatch = full.match(/=w(\d+)-h(\d+)/)
      if (dimMatch) {
        const w = parseInt(dimMatch[1])
        const h = parseInt(dimMatch[2])
        // Feature graphic is always landscape (w > h) and large (w >= 500)
        if (w > h && w >= 500) {
          candidates.push({ base, w, h })
        }
      }
    }

    // Pick the widest landscape image (most likely to be the feature graphic)
    candidates.sort((a, b) => b.w - a.w)
    const best = candidates[0]

    if (best) {
      const bannerUrl = `${best.base}=w1024-h500-rw`
      bannerCache.set(packageId, bannerUrl)
      return bannerUrl
    }
  } catch { /* ignore */ }
  bannerCache.set(packageId, null)
  return null
})

// ── Config IPC ───────────────────────────────────────────────────────────────

ipcMain.handle('config:get', (_event, key: string) => {
  return readNunuConfig()[key] ?? null
})

ipcMain.handle('config:set', (_event, key: string, value: unknown) => {
  const config = readNunuConfig()
  config[key] = value
  writeNunuConfig(config)
})

// ── Android SDK helpers ──────────────────────────────────────────────────────

function nunuSdkRoot(): string {
  return join(app.getPath('home'), '.nunu', 'sdk')
}

function sysImageArch(): string {
  return (process.platform === 'darwin' && process.arch === 'arm64') ? 'arm64-v8a' : 'x86_64'
}

function downloadFile(url: string, dest: string, onProgress: (pct: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const getFunc = url.startsWith('https') ? httpsGet : httpGet
    const options = {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; nunu/1.0)',
      },
    }
    getFunc(url, options, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        const loc = res.headers.location
        if (loc) return downloadFile(loc, dest, onProgress).then(resolve).catch(reject)
      }
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} for ${url}`))
      const total = parseInt(res.headers['content-length'] ?? '0', 10)
      let received = 0
      const file = createWriteStream(dest)
      res.on('data', (chunk: Buffer) => {
        received += chunk.length
        if (total > 0) onProgress(Math.round((received / total) * 100))
      })
      res.pipe(file)
      file.on('finish', () => { file.close(); resolve() })
      file.on('error', reject)
      res.on('error', reject)
    }).on('error', reject)
  })
}

function extractZip(zipPath: string, destDir: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const args = process.platform === 'win32'
      ? ['powershell', ['-Command', `Expand-Archive -Path "${zipPath}" -DestinationPath "${destDir}" -Force`]]
      : ['unzip', ['-o', zipPath, '-d', destDir]] as [string, string[]]
    const proc = spawn(args[0] as string, args[1] as string[], { stdio: 'ignore' })
    proc.on('close', (code) => code === 0 ? resolve() : reject(new Error(`Extract failed: code ${code}`)))
    proc.on('error', reject)
  })
}

function runSdkManager(
  bin: string,
  sdkRoot: string,
  args: string[],
  stdinData?: string,
  onLine?: (line: string) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    if (process.platform !== 'win32') spawnSync('chmod', ['+x', bin])
    const env = { ...process.env, ANDROID_SDK_ROOT: sdkRoot, ANDROID_HOME: sdkRoot, JAVA_OPTS: '-Dfile.encoding=UTF-8' }
    const proc = spawn(bin, args, { env, stdio: ['pipe', 'pipe', 'pipe'] })
    if (stdinData) { proc.stdin?.write(stdinData); proc.stdin?.end() }
    let buf = ''
    let stderrOutput = ''
    proc.stdout?.on('data', (d: Buffer) => {
      buf += d.toString()
      const lines = buf.split('\n')
      buf = lines.pop() ?? ''
      for (const l of lines) onLine?.(l)
    })
    proc.stderr?.on('data', (d: Buffer) => {
      const text = d.toString()
      stderrOutput += text
      buf += text
      const lines = buf.split('\n')
      buf = lines.pop() ?? ''
      for (const l of lines) onLine?.(l)
    })
    proc.on('close', (code) => {
      if (code === 0 || code === 1) {
        // Exit code 1 from sdkmanager often just means "licenses already accepted" — treat as success
        // but if stderr contains a clear error signal, reject
        if (code === 1 && stderrOutput.toLowerCase().includes('error')) {
          reject(new Error(`sdkmanager failed: ${stderrOutput.slice(0, 300)}`))
        } else {
          resolve()
        }
      } else {
        reject(new Error(`sdkmanager exited ${code}${stderrOutput ? ': ' + stderrOutput.slice(0, 300) : ''}`))
      }
    })
    proc.on('error', (err) => {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        reject(new Error('Java not found. Please install Java (JDK 17+) and try again.'))
      } else {
        reject(err)
      }
    })
  })
}

function checkJavaInstalled(): Promise<boolean> {
  return new Promise((resolve) => {
    const proc = spawn('java', ['-version'], { stdio: 'ignore' })
    proc.on('close', (code) => resolve(code === 0))
    proc.on('error', () => resolve(false))
  })
}

// ── nunu-apple engine helpers (macOS only) ───────────────────────────────────

function findNunuVmBinary(): string | null {
  const candidates: string[] = []

  if (app.isPackaged) {
    candidates.push(join(process.resourcesPath, 'nunu-vm', 'NunuVM'))
  }

  // User-installed engine via Settings → Engine
  candidates.push(join(app.getPath('home'), '.nunu', 'engines', 'nunu-apple', 'NunuVM'))

  // Dev: sibling repo
  const repoRoot = join(__dirname, '..', '..')
  candidates.push(join(repoRoot, 'nunu-apple', 'launcher', '.build', 'release', 'NunuVM'))
  candidates.push(join(repoRoot, '..', 'nunu-apple', 'launcher', '.build', 'release', 'NunuVM'))
  candidates.push(join(repoRoot, '..', 'nunu-apple', 'launcher', '.build', 'debug', 'NunuVM'))

  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  return null
}

// Spawn nunu-vm (macOS) and translate its JSON stdout events into vm:status IPC
function spawnNunuVm(options: {
  kernelPath: string
  diskPaths: string[]
  memoryMb: number
  cores: number
  adbPort?: number
}): ChildProcess {
  const bin = findNunuVmBinary()
  if (!bin) throw new Error('nunu-vm binary not found. Build nunu-apple/launcher first.')

  const args = [
    '--kernel', options.kernelPath,
    '--memory', String(options.memoryMb),
    '--cores',  String(options.cores),
    '--adb-port', String(options.adbPort ?? 5555),
    ...options.diskPaths.flatMap(p => ['--disk', p]),
  ]

  const proc = spawn(bin, args, { detached: false, stdio: ['ignore', 'pipe', 'pipe'] })

  let buf = ''
  proc.stdout?.on('data', (d: Buffer) => {
    buf += d.toString()
    const lines = buf.split('\n')
    buf = lines.pop() ?? ''
    for (const line of lines) {
      try {
        const event = JSON.parse(line) as { event: string; address?: string; message?: string }
        switch (event.event) {
          case 'started':
            mainWindow?.webContents.send('vm:status', { status: 'booting' })
            break
          case 'adb-ready':
            mainWindow?.webContents.send('vm:status', { status: 'ready' })
            mainWindow?.webContents.send('vm:adb-address', { address: event.address })
            break
          case 'stopped':
            mainWindow?.webContents.send('vm:status', { status: 'stopped' })
            break
          case 'error':
            mainWindow?.webContents.send('vm:status', { status: 'error', error: event.message })
            break
        }
      } catch { /* non-JSON line, ignore */ }
    }
  })

  proc.stderr?.on('data', (d: Buffer) => {
    // Forward stderr as diagnostic logs only (not user-facing errors)
    const text = d.toString().trim()
    if (text) console.error('[nunu-vm]', text)
  })

  return proc
}

// ── VM helpers ───────────────────────────────────────────────────────────────

function avmSpawnEnv() {
  const sdk = nunuSdkRoot()
  return {
    ...process.env,
    ...(existsSync(sdk) ? { ANDROID_SDK_ROOT: sdk, ANDROID_HOME: sdk } : {}),
  }
}

function findAvmBinary(): string | null {
  const ext = process.platform === 'win32' ? '.exe' : ''
  const candidates: string[] = []

  // 1. Bundled inside the packaged Electron app (production)
  if (app.isPackaged) {
    candidates.push(join(process.resourcesPath, 'nunu-windows', `nunu-windows${ext}`))
    candidates.push(join(process.resourcesPath, 'avm', `avm${ext}`))  // legacy
  }

  // 2. Dev: nunu-windows build alongside the repo (npm run electron:dev)
  const repoRoot = join(__dirname, '..', '..')
  candidates.push(join(repoRoot, '..', 'nunu-windows', 'build', `nunu-windows${ext}`))
  candidates.push(join(repoRoot, 'native', 'avm', 'build', `avm${ext}`))

  // 3. Legacy manual install locations
  const home = app.getPath('home')
  candidates.push(join(home, '.nunu', 'nunu-windows', `nunu-windows${ext}`))
  candidates.push(join(home, '.nunu', 'avm-core', `avm${ext}`))
  candidates.push(join(home, 'Documents', 'GitHub', 'nunu-windows', 'build', `nunu-windows${ext}`))

  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  return null
}

function findAndroidImageDir(): string | null {
  const home = app.getPath('home')
  const arch = sysImageArch()
  const imageRelPath = `system-images/android-34/google_apis_playstore/${arch}`
  const candidates = [
    // nunu-managed SDK (downloaded by installer)
    join(nunuSdkRoot(), imageRelPath),
    // Homebrew
    join('/opt/homebrew/share/android-commandlinetools', imageRelPath),
    join('/usr/local/share/android-commandlinetools', imageRelPath),
    // Android Studio
    join(home, 'Library/Android/sdk', imageRelPath),
    join(home, 'Android/Sdk', imageRelPath),
    ...(process.env.ANDROID_SDK_ROOT ? [join(process.env.ANDROID_SDK_ROOT, imageRelPath)] : []),
    ...(process.env.ANDROID_HOME ? [join(process.env.ANDROID_HOME, imageRelPath)] : []),
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  return null
}

function runAdb(args: string[]): Promise<string> {
  return new Promise((resolve) => {
    const proc = spawn('adb', args, { stdio: ['ignore', 'pipe', 'ignore'] })
    let out = ''
    proc.stdout.on('data', (d: Buffer) => { out += d.toString() })
    proc.on('close', () => resolve(out))
    proc.on('error', () => resolve(''))
  })
}

async function getEmulatorSerial(): Promise<string | null> {
  const out = await runAdb(['devices'])
  // Prefer emulator-5554 (AVM default), fall back to any running emulator
  if (out.includes('emulator-5554\tdevice')) return 'emulator-5554'
  const match = out.match(/^(emulator-\d+)\s+device$/m)
  return match ? match[1] : null
}

async function waitForAndroidBoot(timeoutMs = 120_000): Promise<string | null> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const serial = await getEmulatorSerial()
    if (serial) {
      const prop = await runAdb(['-s', serial, 'shell', 'getprop', 'sys.boot_completed'])
      if (prop.trim() === '1') return serial
    }
    await new Promise<void>((r) => setTimeout(r, 3000))
  }
  return null
}

async function launchAppOnDevice(serial: string, packageId: string): Promise<void> {
  await runAdb(['-s', serial, 'shell', 'monkey',
    '-p', packageId, '-c', 'android.intent.category.LAUNCHER', '1'])
}

// ── VM launch IPC ────────────────────────────────────────────────────────────

function stopVmProcess() {
  if (vmProcess) {
    vmProcess.removeAllListeners()
    vmProcess.kill()
    vmProcess = null
  }
  runningGameId = null
  runningGameName = null
  runningGameConfig = null
}

ipcMain.handle('vm:stop', () => {
  stopVmProcess()
  mainWindow?.webContents.send('vm:status', { status: 'stopped' })
})

ipcMain.handle('vm:isRunning', () => vmProcess !== null)

ipcMain.handle('vm:checkInstalled', () => {
  return findAndroidImageDir() !== null
})

ipcMain.handle('vm:boot', async (_event, config?: { memoryMb: number; cores: number }) => {
  if (!mainWindow) return { success: false, error: 'No window' }
  if (vmProcess) return { success: true, alreadyRunning: true }

  const avmBin = findAvmBinary()
  if (!avmBin) return { success: false, error: 'AVM engine not found. Please reinstall nunu.' }
  const imageDir = findAndroidImageDir()
  if (!imageDir) return {
    success: false,
    error: 'Android image not found.\nRun: sdkmanager "system-images;android-34;google_apis_playstore;arm64-v8a"',
  }

  const mem = config?.memoryMb ?? 4096
  const cores = config?.cores ?? 4

  try {
    mainWindow.webContents.send('vm:status', { status: 'booting' })
    vmProcess = spawn(avmBin, ['--image', imageDir, '--memory', String(mem), '--cores', String(cores)], {
      detached: false, stdio: 'ignore', env: avmSpawnEnv(),
    })
    runningGameConfig = { memoryMb: mem, cores }
    vmProcess.on('exit', () => {
      vmProcess = null; runningGameId = null; runningGameName = null; runningGameConfig = null
      mainWindow?.webContents.send('vm:status', { status: 'stopped' })
    })
    vmProcess.on('error', (err) => {
      vmProcess = null; runningGameId = null; runningGameName = null; runningGameConfig = null
      mainWindow?.webContents.send('vm:status', { status: 'error', error: err.message })
    })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { success: false, error: message }
  }

  const serial = await waitForAndroidBoot(120_000)
  if (!serial) return { success: false, error: 'Android took too long to boot.' }
  mainWindow.webContents.send('vm:status', { status: 'ready' })
  return { success: true }
})

ipcMain.handle('vm:uninstall', async () => {
  stopVmProcess()
  mainWindow?.webContents.send('vm:status', { status: 'stopped' })

  const home = app.getPath('home')
  const avdDir  = join(home, '.avd', 'avm_nunu.avd')
  const avdIni  = join(home, '.avd', 'avm_nunu.ini')
  const shaderCache = join(home, '.avd', 'shader_cache')

  const { rmSync, existsSync: fsExists } = await import('fs')
  for (const p of [avdDir, avdIni, shaderCache]) {
    try { if (fsExists(p)) rmSync(p, { recursive: true, force: true }) } catch { /* ignore */ }
  }
  return { success: true }
})

ipcMain.handle('vm:launch', async (_event, options: {
  packageId: string
  gameName: string
  config: { memoryMb: number; cores: number }
  forceRestart?: boolean
}) => {
  if (!mainWindow) return { success: false, error: 'No window' }

  const { packageId, gameName, config, forceRestart } = options

  // ── 1. VM already running ────────────────────────────────────────────────
  if (vmProcess) {
    if (!forceRestart) {
      // Same game — just launch the app into the running VM
      if (runningGameId === packageId) {
        const serial = await getEmulatorSerial()
        if (serial) {
          const prop = await runAdb(['-s', serial, 'shell', 'getprop', 'sys.boot_completed'])
          if (prop.trim() === '1') {
            await launchAppOnDevice(serial, packageId)
            return { success: true, alreadyRunning: true }
          }
        }
        return { success: true, alreadyRunning: true }
      }

      // Different game — ask UI to confirm restart
      return {
        success: false,
        needsRestart: true,
        runningGameName: runningGameName ?? 'another game',
      }
    }

    // forceRestart: kill current VM first
    stopVmProcess()
    mainWindow.webContents.send('vm:status', { status: 'stopped' })
    // Brief pause so the emulator process fully exits before relaunching
    await new Promise<void>((r) => setTimeout(r, 1500))
  }

  // ── 2. Find AVM binary ────────────────────────────────────────────────────
  const avmBin = findAvmBinary()
  if (!avmBin) {
    return {
      success: false,
      error: 'AVM engine not found. Please reinstall nunu from github.com/wisnuub/nunu.',
    }
  }

  // ── 3. Find Android system image ─────────────────────────────────────────
  const imageDir = findAndroidImageDir()
  if (!imageDir) {
    return {
      success: false,
      error: 'Android image not found.\nRun: sdkmanager "system-images;android-34;google_apis_playstore;arm64-v8a"',
    }
  }

  // ── 4. Boot the VM ────────────────────────────────────────────────────────
  try {
    mainWindow.webContents.send('vm:status', { status: 'booting' })
    vmProcess = spawn(avmBin, [
      '--image', imageDir,
      '--memory', String(config.memoryMb),
      '--cores', String(config.cores),
    ], {
      detached: false,
      stdio: 'ignore',
      env: avmSpawnEnv(),
    })
    runningGameId = packageId
    runningGameName = gameName
    runningGameConfig = config
    vmProcess.on('exit', () => {
      vmProcess = null
      runningGameId = null
      runningGameName = null
      runningGameConfig = null
      mainWindow?.webContents.send('vm:status', { status: 'stopped' })
    })
    vmProcess.on('error', (err) => {
      vmProcess = null
      runningGameId = null
      runningGameName = null
      runningGameConfig = null
      mainWindow?.webContents.send('vm:status', { status: 'error', error: err.message })
    })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { success: false, error: message }
  }

  // ── 5. Wait for Android to finish booting ────────────────────────────────
  const serial = await waitForAndroidBoot(120_000)
  if (!serial) {
    return {
      success: false,
      error: 'Android took too long to boot. Try again once the emulator window is ready.',
    }
  }

  mainWindow.webContents.send('vm:status', { status: 'ready' })

  // ── 6. Launch the game ────────────────────────────────────────────────────
  await launchAppOnDevice(serial, packageId)

  return { success: true }
})

// ── App lifecycle ─────────────────────────────────────────────────────────────

app.whenReady().then(() => {
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('web-contents-created', (_event, contents) => {
  // Allow webview for Google sign-in OAuth
  contents.on('will-navigate', (_navEvent, url) => {
    const allowed = [
      'http://localhost:5173',
      'https://accounts.google.com',
      'https://oauth2.googleapis.com',
    ]
    const isAllowed = allowed.some((origin) => url.startsWith(origin))
    if (!isAllowed && !isDev) {
      shell.openExternal(url)
    }
  })
})
