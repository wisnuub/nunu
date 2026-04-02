import { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useAppStore } from './store/appStore'
import { OnboardingFlow } from './views/Onboarding/OnboardingFlow'
import { MainLayout } from './views/Launcher/MainLayout'
import { TitleBar } from './components/TitleBar'

export default function App() {
  const { isOnboardingDone, hydrateFromStore } = useAppStore()

  useEffect(() => {
    hydrateFromStore()
  }, [hydrateFromStore])

  // Check for updates on launch (silent)
  useEffect(() => {
    if (!isOnboardingDone) return
    if (typeof window === 'undefined' || !window.nunu) return
    window.nunu.checkUpdate().then((result) => {
      if (result.hasUpdate) {
        useAppStore.getState().setHasUpdate(true, result.release as never)
      }
    }).catch(() => {/* silently ignore */})
  }, [isOnboardingDone])

  return (
    <div className="flex flex-col h-full w-full bg-[#0D0F14] overflow-hidden">
      <TitleBar />
      <div className="flex-1 overflow-hidden">
        <Routes>
          <Route
            path="/"
            element={
              isOnboardingDone ? (
                <Navigate to="/launcher" replace />
              ) : (
                <Navigate to="/onboarding" replace />
              )
            }
          />
          <Route path="/onboarding/*" element={<OnboardingFlow />} />
          <Route path="/launcher/*" element={<MainLayout />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </div>
    </div>
  )
}
