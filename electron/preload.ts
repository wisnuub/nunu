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

  // Updates
  checkUpdate: () => ipcRenderer.invoke('update:check'),

  // SafetyNet
  setupSafetyNet: () => ipcRenderer.invoke('safetynet:setup'),
  onSafetyNetProgress: (callback: (event: SafetyNetProgressEvent) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, data: SafetyNetProgressEvent) =>
      callback(data)
    ipcRenderer.on('safetynet:progress', handler)
    return () => ipcRenderer.removeListener('safetynet:progress', handler)
  },

  // Persistent store (proxied through main process)
  store: {
    get: (key: string) => ipcRenderer.invoke('store:get', key),
    set: (key: string, value: unknown) => ipcRenderer.invoke('store:set', key, value),
  },
})
