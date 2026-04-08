import { contextBridge, ipcRenderer } from 'electron'

export type InstallProgress = {
  phase: 'avm-core' | 'android-image' | 'safetynet' | 'game'
  percent: number
  status: string
}

export type SafetyNetProgressEvent = {
  step: number
  stepName: string
  done: boolean
  percent: number
}

contextBridge.exposeInMainWorld('nunu', {
  // Window controls
  minimize: () => ipcRenderer.send('app:minimize'),
  maximize: () => ipcRenderer.send('app:maximize'),
  close: () => ipcRenderer.send('app:close'),

  // Platform info
  platform: process.platform as 'darwin' | 'win32' | 'linux',

  // Installation
  startInstall: (options: { androidVersion?: string }) =>
    ipcRenderer.invoke('install:start', options),
  installGame: (gameId: string) => ipcRenderer.invoke('install:game', gameId),
  onInstallProgress: (callback: (progress: InstallProgress) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, data: InstallProgress) => callback(data)
    ipcRenderer.on('install:progress', handler)
    return () => ipcRenderer.removeListener('install:progress', handler)
  },

  // VM controls
  bootVm: (config?: { memoryMb: number; cores: number }) => ipcRenderer.invoke('vm:boot', config),
  stopVm: () => ipcRenderer.invoke('vm:stop'),
  uninstallAndroid: () => ipcRenderer.invoke('vm:uninstall'),
  isVmRunning: () => ipcRenderer.invoke('vm:isRunning') as Promise<boolean>,
  checkAndroidInstalled: () => ipcRenderer.invoke('vm:checkInstalled') as Promise<boolean>,

  // VM launch
  launchGame: (
    packageId: string,
    gameName: string,
    config: { memoryMb: number; cores: number },
    forceRestart?: boolean,
  ) => ipcRenderer.invoke('vm:launch', { packageId, gameName, config, forceRestart }),
  onVmStatus: (callback: (event: { status: string; error?: string }) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, data: { status: string; error?: string }) => callback(data)
    ipcRenderer.on('vm:status', handler)
    return () => ipcRenderer.removeListener('vm:status', handler)
  },
  onAdbAddress: (callback: (event: { address: string }) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, data: { address: string }) => callback(data)
    ipcRenderer.on('vm:adb-address', handler)
    return () => ipcRenderer.removeListener('vm:adb-address', handler)
  },

  // Play Store art
  fetchGameArt: (packageId: string) => ipcRenderer.invoke('game:fetchArt', packageId),
  fetchGameBanner: (packageId: string) => ipcRenderer.invoke('game:fetchBanner', packageId),

  // App info
  getVersion: () => ipcRenderer.invoke('app:version'),
  openExternal: (url: string) => ipcRenderer.invoke('app:openExternal', url),

  // Engine management (macOS: nunu-apple)
  checkEngine: () => ipcRenderer.invoke('engine:check'),
  checkEngineUpdate: () => ipcRenderer.invoke('engine:check-update'),
  installEngine: (downloadUrl: string, version: string) =>
    ipcRenderer.invoke('engine:install', downloadUrl, version),
  onEngineProgress: (callback: (event: { percent: number; status: string }) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, data: { percent: number; status: string }) =>
      callback(data)
    ipcRenderer.on('engine:progress', handler)
    return () => ipcRenderer.removeListener('engine:progress', handler)
  },

  // Updates
  checkUpdate: () => ipcRenderer.invoke('update:check'),

  // Google Sign-In
  signInWithGoogle: () => ipcRenderer.invoke('google:signin'),
  openGoogleOnAndroid: () => ipcRenderer.invoke('vm:openGoogleSetup'),

  // SafetyNet
  setupSafetyNet: () => ipcRenderer.invoke('safetynet:setup'),
  onSafetyNetProgress: (callback: (event: SafetyNetProgressEvent) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, data: SafetyNetProgressEvent) =>
      callback(data)
    ipcRenderer.on('safetynet:progress', handler)
    return () => ipcRenderer.removeListener('safetynet:progress', handler)
  },

  // Android customisation
  removeLockscreen: () => ipcRenderer.invoke('android:remove-lockscreen'),
  pushBootAnimation: (zipPath: string) => ipcRenderer.invoke('android:push-bootanimation', zipPath),
  pickBootAnimation: () => ipcRenderer.invoke('android:pick-bootanimation'),

  // GApps (Magisk-based: patch initramfs then provision via ADB)
  patchInitrdForGApps: () => ipcRenderer.invoke('gapps:patch-initrd'),
  installGApps: () => ipcRenderer.invoke('gapps:install'),
  onGAppsProgress: (callback: (event: { percent: number; status: string }) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, data: { percent: number; status: string }) =>
      callback(data)
    ipcRenderer.on('gapps:progress', handler)
    return () => ipcRenderer.removeListener('gapps:progress', handler)
  },

  // Config (~/.nunu/config.json)
  getConfig: (key: string) => ipcRenderer.invoke('config:get', key),
  setConfig: (key: string, value: unknown) => ipcRenderer.invoke('config:set', key, value),

  // Persistent store (proxied through main process)
  store: {
    get: (key: string) => ipcRenderer.invoke('store:get', key),
    set: (key: string, value: unknown) => ipcRenderer.invoke('store:set', key, value),
  },
})
