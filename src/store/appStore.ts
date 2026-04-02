import { create } from 'zustand'

export interface AndroidRelease {
  tag_name: string
  name: string
  body: string
  published_at: string
  assets: Array<{
    name: string
    browser_download_url: string
    size: number
  }>
}

type OnboardingStep = 'welcome' | 'downloading' | 'safetynet' | 'signin' | 'complete'

export interface AppStore {
  // Onboarding
  isOnboardingDone: boolean
  onboardingStep: OnboardingStep
  downloadProgress: number
  downloadStatus: string
  safetyNetProgress: number
  safetyNetStatus: string
  safetyNetPassed: boolean | null

  // User
  isSignedIn: boolean
  userEmail: string | null

  // Games
  installedGames: string[]
  installProgress: Record<string, number>

  // Updates
  hasUpdate: boolean
  pendingUpdate: AndroidRelease | null
  isUpdating: boolean
  updateProgress: number
  updateStatus: string

  // Active view in launcher
  activeView: 'home' | 'my-games' | 'discover' | 'settings'

  // Actions
  setOnboardingDone: (val: boolean) => void
  setOnboardingStep: (step: OnboardingStep) => void
  setDownloadProgress: (progress: number, status: string) => void
  setSafetyNetProgress: (progress: number, status: string) => void
  setSafetyNetPassed: (passed: boolean) => void
  setInstallProgress: (gameId: string, p: number) => void
  signIn: (email: string) => void
  signOut: () => void
  addInstalledGame: (id: string) => void
  removeInstalledGame: (id: string) => void
  setHasUpdate: (val: boolean, release?: AndroidRelease) => void
  setActiveView: (view: AppStore['activeView']) => void
  hydrateFromStore: () => Promise<void>
}

// Helpers to read/write electron-store via IPC
const storeGet = async <T>(key: string, fallback: T): Promise<T> => {
  if (typeof window !== 'undefined' && window.nunu?.store) {
    const val = await window.nunu.store.get(key)
    return val !== undefined && val !== null ? (val as T) : fallback
  }
  return fallback
}

const storeSet = (key: string, value: unknown) => {
  if (typeof window !== 'undefined' && window.nunu?.store) {
    window.nunu.store.set(key, value)
  }
}

export const useAppStore = create<AppStore>((set, get) => ({
  // Onboarding
  isOnboardingDone: false,
  onboardingStep: 'welcome',
  downloadProgress: 0,
  downloadStatus: '',
  safetyNetProgress: 0,
  safetyNetStatus: '',
  safetyNetPassed: null,

  // User
  isSignedIn: false,
  userEmail: null,

  // Games
  installedGames: [],
  installProgress: {},

  // Updates
  hasUpdate: false,
  pendingUpdate: null,
  isUpdating: false,
  updateProgress: 0,
  updateStatus: '',

  // Active view
  activeView: 'home',

  // Actions
  setOnboardingDone: (val) => {
    set({ isOnboardingDone: val })
    storeSet('isOnboardingDone', val)
  },

  setOnboardingStep: (step) => set({ onboardingStep: step }),

  setDownloadProgress: (progress, status) =>
    set({ downloadProgress: progress, downloadStatus: status }),

  setSafetyNetProgress: (progress, status) =>
    set({ safetyNetProgress: progress, safetyNetStatus: status }),

  setSafetyNetPassed: (passed) => set({ safetyNetPassed: passed }),

  setInstallProgress: (gameId, p) =>
    set((s) => ({ installProgress: { ...s.installProgress, [gameId]: p } })),

  signIn: (email) => {
    set({ isSignedIn: true, userEmail: email })
    storeSet('isSignedIn', true)
    storeSet('userEmail', email)
  },

  signOut: () => {
    set({ isSignedIn: false, userEmail: null })
    storeSet('isSignedIn', false)
    storeSet('userEmail', null)
  },

  addInstalledGame: (id) => {
    const games = [...get().installedGames]
    if (!games.includes(id)) games.push(id)
    set({ installedGames: games })
    storeSet('installedGames', games)
  },

  removeInstalledGame: (id) => {
    const games = get().installedGames.filter((g) => g !== id)
    set({ installedGames: games })
    storeSet('installedGames', games)
  },

  setHasUpdate: (val, release) =>
    set({ hasUpdate: val, pendingUpdate: release ?? null }),

  setActiveView: (view) => set({ activeView: view }),

  hydrateFromStore: async () => {
    const [isOnboardingDone, installedGames, isSignedIn, userEmail] = await Promise.all([
      storeGet<boolean>('isOnboardingDone', false),
      storeGet<string[]>('installedGames', []),
      storeGet<boolean>('isSignedIn', false),
      storeGet<string | null>('userEmail', null),
    ])
    set({ isOnboardingDone, installedGames, isSignedIn, userEmail })
  },
}))
