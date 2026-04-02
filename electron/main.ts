import { app, BrowserWindow, ipcMain, shell, nativeImage } from 'electron'
import { join } from 'path'
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs'
import { spawn, ChildProcess } from 'child_process'
import Store from 'electron-store'
import { InstallationService } from './services/InstallationService'
import { UpdateService } from './services/UpdateService'
import { SafetyNetService } from './services/SafetyNetService'
import { startGoogleSignIn } from './services/GoogleAuthService'

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

  const service = new InstallationService((progress) => {
    mainWindow?.webContents.send('install:progress', progress)
  })

  try {
    await service.downloadAVMCore()
    await service.downloadAndroidImage(options.androidVersion ?? '13')
    return { success: true }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { success: false, error: message }
  }
})

ipcMain.handle('install:game', async (_event, gameId: string) => {
  if (!mainWindow) return { success: false, error: 'No window' }

  const service = new InstallationService((progress) => {
    mainWindow?.webContents.send('install:progress', progress)
  })

  try {
    await service.installGame(gameId)
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

    // Get the icon URL so we can exclude it
    const iconMatch = html.match(/<meta property="og:image" content="([^"]+)"/)
    const iconHash = iconMatch ? iconMatch[1].split('/').pop()?.split('=')[0] : null

    // Collect all play-lh image URLs from the page
    const allUrls = [...html.matchAll(/https:\/\/play-lh\.googleusercontent\.com\/([^"'\s\\]+)/g)]
      .map(m => `https://play-lh.googleusercontent.com/${m[1].split('=')[0]}`)
      .filter((v, i, arr) => arr.indexOf(v) === i) // deduplicate

    // Pick first URL that isn't the icon — this is the feature graphic / banner
    const bannerBase = allUrls.find(u => !iconHash || !u.includes(iconHash))
    if (bannerBase) {
      const bannerUrl = `${bannerBase}=w1024-h500-rw`
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

// ── VM helpers ───────────────────────────────────────────────────────────────

function findAvmBinary(): string | null {
  const home = app.getPath('home')
  const candidates = [
    join(home, '.nunu', 'avm-core', 'avm'),
    // dev build locations
    join(home, 'Documents', 'GitHub', 'AVM', 'build', 'avm'),
    '/usr/local/bin/avm',
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  return null
}

function findAndroidImageDir(): string | null {
  const home = app.getPath('home')
  const imageRelPath = 'system-images/android-34/google_apis_playstore/arm64-v8a'
  const candidates = [
    join('/opt/homebrew/share/android-commandlinetools', imageRelPath),
    join('/usr/local/share/android-commandlinetools', imageRelPath),
    join(home, 'Library/Android/sdk', imageRelPath),
    join(home, 'Android/Sdk', imageRelPath),
    ...(process.env.ANDROID_SDK_ROOT
      ? [join(process.env.ANDROID_SDK_ROOT, imageRelPath)]
      : []),
    ...(process.env.ANDROID_HOME
      ? [join(process.env.ANDROID_HOME, imageRelPath)]
      : []),
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

ipcMain.handle('vm:launch', async (_event, packageId: string) => {
  if (!mainWindow) return { success: false, error: 'No window' }

  // ── 1. If VM already running, just launch the app ────────────────────────
  if (vmProcess) {
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

  // ── 2. Find AVM binary ────────────────────────────────────────────────────
  const avmBin = findAvmBinary()
  if (!avmBin) {
    return {
      success: false,
      error: 'AVM not found. Expected at ~/.nunu/avm-core/avm — see github.com/wisnuub/AVM.',
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
    vmProcess = spawn(avmBin, ['--image', imageDir], {
      detached: false,
      stdio: 'ignore',
      env: { ...process.env },
    })
    vmProcess.on('exit', () => {
      vmProcess = null
      mainWindow?.webContents.send('vm:status', { status: 'stopped' })
    })
    vmProcess.on('error', (err) => {
      vmProcess = null
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
