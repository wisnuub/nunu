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

      store: {
        get: (key: string) => Promise<unknown>
        set: (key: string, value: unknown) => Promise<void>
      }
    }
  }
}
