export {}

declare global {
  interface Window {
    nunu: {
      minimize: () => void
      maximize: () => void
      close: () => void
      platform: 'darwin' | 'win32' | 'linux'

      startInstall: (options: { androidVersion?: string }) => Promise<{ success: boolean; error?: string }>
      installGame: (gameId: string) => Promise<{ success: boolean; error?: string }>
      onInstallProgress: (
        callback: (progress: { phase: string; percent: number; status: string }) => void
      ) => () => void

      bootVm: (config?: { memoryMb: number; cores: number }) => Promise<{ success: boolean; alreadyRunning?: boolean; error?: string }>
      stopVm: () => Promise<void>
      uninstallAndroid: () => Promise<{ success: boolean }>
      isVmRunning: () => Promise<boolean>
      checkAndroidInstalled: () => Promise<boolean>
      launchGame: (
        packageId: string,
        gameName: string,
        config: { memoryMb: number; cores: number },
        forceRestart?: boolean,
      ) => Promise<{ success: boolean; alreadyRunning?: boolean; needsRestart?: boolean; runningGameName?: string; error?: string }>
      onVmStatus: (callback: (event: { status: string; error?: string }) => void) => () => void
      fetchGameArt: (packageId: string) => Promise<string | null>
      fetchGameBanner: (packageId: string) => Promise<string | null>

      signInWithGoogle: () => Promise<{
        success: boolean
        email?: string
        name?: string
        picture?: string
        error?: string
      }>

      getVersion: () => Promise<string>
      openExternal: (url: string) => Promise<void>

      checkUpdate: () => Promise<{
        hasUpdate: boolean
        release: unknown
        installedVersion: string | null
        error?: string
      }>

      setupSafetyNet: () => Promise<{
        passed: boolean
        basicIntegrity: boolean
        ctsProfile: boolean
        error?: string
      }>
      onSafetyNetProgress: (
        callback: (event: {
          step: number
          stepName: string
          done: boolean
          percent: number
        }) => void
      ) => () => void

      getConfig: (key: string) => Promise<unknown>
      setConfig: (key: string, value: unknown) => Promise<void>

      store: {
        get: (key: string) => Promise<unknown>
        set: (key: string, value: unknown) => Promise<void>
      }
    }
  }
}
