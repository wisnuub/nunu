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

  // Play Store art
  fetchGameArt: (packageId: string) => ipcRenderer.invoke('game:fetchArt', packageId),
  fetchGameBanner: (packageId: string) => ipcRenderer.invoke('game:fetchBanner', packageId),

  // App info
  getVersion: () => ipcRenderer.invoke('app:version'),
  openExternal: (url: string) => ipcRenderer.invoke('app:openExternal', url),

  // Updates
  checkUpdate: () => ipcRenderer.invoke('update:check'),

  // Google Sign-In
  signInWithGoogle: () => ipcRenderer.invoke('google:signin'),

  // SafetyNet
  setupSafetyNet: () => ipcRenderer.invoke('safetynet:setup'),
  onSafetyNetProgress: (callback: (event: SafetyNetProgressEvent) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, data: SafetyNetProgressEvent) =>
      callback(data)
    ipcRenderer.on('safetynet:progress', handler)
    return () => ipcRenderer.removeListener('safetynet:progress', handler)
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
