import { app, BrowserWindow, ipcMain, shell, nativeImage } from 'electron'
import { join } from 'path'
import { existsSync } from 'fs'
import Store from 'electron-store'
import { InstallationService } from './services/InstallationService'
import { UpdateService } from './services/UpdateService'
import { SafetyNetService } from './services/SafetyNetService'

// Handle Windows NSIS squirrel events
if (process.platform === 'win32') {
  const squirrelStartup = require('electron-squirrel-startup')
  if (squirrelStartup) app.quit()
}

const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged

const store = new Store<Record<string, unknown>>()

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
