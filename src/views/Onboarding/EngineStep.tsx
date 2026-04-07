import { useEffect, useState } from 'react'
import { useAppStore } from '../../store/appStore'

export function EngineStep() {
  const { setOnboardingStep } = useAppStore()

  const [installed, setInstalled] = useState<boolean | null>(null)
  const [version, setVersion] = useState<string | null>(null)
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null)
  const [latestVersion, setLatestVersion] = useState<string | null>(null)
  const [installing, setInstalling] = useState(false)
  const [pct, setPct] = useState(0)
  const [status, setStatus] = useState('')
  const [error, setError] = useState('')
  const [checking, setChecking] = useState(true)

  useEffect(() => {
    window.nunu?.checkEngine?.().then((r) => {
      setInstalled(r.installed)
      setVersion(r.version)
      if (r.installed) {
        setChecking(false)
      } else {
        // Fetch latest release
        window.nunu?.checkEngineUpdate?.().then((u) => {
          setDownloadUrl(u.downloadUrl)
          setLatestVersion(u.latestVersion)
          setChecking(false)
          if (u.error) setError('Could not fetch release. Check your connection.')
        })
      }
    })
  }, [])

  const handleInstall = async () => {
    if (!downloadUrl || !latestVersion) return
    setInstalling(true)
    setError('')
    const unsub = window.nunu?.onEngineProgress?.((evt) => {
      setPct(evt.percent)
      setStatus(evt.status)
      if (evt.percent >= 100) {
        unsub?.()
        setInstalled(true)
        setVersion(latestVersion)
        setInstalling(false)
        setTimeout(() => setOnboardingStep('signin'), 800)
      }
    })
    const result = await window.nunu?.installEngine?.(downloadUrl, latestVersion)
    if (result && !result.success) {
      setError(result.error ?? 'Install failed')
      setInstalling(false)
      unsub?.()
    }
  }

  return (
    <div className="h-full flex flex-col items-center justify-center px-12 gap-8 pb-10">
      <div className="text-center">
        <h2 className="text-3xl font-bold text-white mb-2">Install nunu engine</h2>
        <p className="text-white/50 text-base">
          The nunu-apple engine powers the Android VM on your Mac.
        </p>
      </div>

      <div className="w-full max-w-sm flex flex-col gap-4">
        {/* Status card */}
        <div className="rounded-[12px] bg-[#141720] border border-white/5 px-5 py-4">
          {checking ? (
            <div className="flex items-center gap-3 text-white/50 text-sm">
              <svg className="animate-spin shrink-0" width="16" height="16" viewBox="0 0 20 20" fill="none">
                <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="2" strokeDasharray="40 14" strokeLinecap="round"/>
              </svg>
              Checking…
            </div>
          ) : installed ? (
            <div className="flex items-center gap-3">
              <svg className="text-[#16A34A] shrink-0" width="20" height="20" viewBox="0 0 20 20" fill="none">
                <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5"/>
                <path d="M6 10l3 3 5-5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
              <div>
                <p className="text-white text-sm font-medium">nunu-apple installed</p>
                {version && <p className="text-white/40 text-xs mt-0.5">v{version}</p>}
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-between">
              <div>
                <p className="text-white text-sm font-medium">nunu-apple engine</p>
                <p className="text-white/40 text-xs mt-0.5">
                  {latestVersion ? `v${latestVersion} available` : 'Not installed'}
                </p>
              </div>
              {downloadUrl && latestVersion && !installing && (
                <button
                  onClick={handleInstall}
                  className="px-4 py-1.5 rounded-[6px] text-xs font-semibold text-white shrink-0 focus:outline-none"
                  style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
                >
                  Install
                </button>
              )}
            </div>
          )}
        </div>

        {/* Progress */}
        {installing && (
          <div className="flex flex-col gap-2">
            <div className="flex justify-between text-xs text-white/50">
              <span>{status || 'Installing…'}</span>
              <span>{pct}%</span>
            </div>
            <div className="w-full h-2 bg-white/10 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-300"
                style={{ width: `${pct}%`, background: 'linear-gradient(90deg, #5B6EF5, #8B5CF6)' }}
              />
            </div>
          </div>
        )}

        {error && <p className="text-red-400 text-xs text-center">{error}</p>}
      </div>

      {/* Continue (when already installed) */}
      {installed && !installing && (
        <button
          onClick={() => setOnboardingStep('signin')}
          className="px-10 py-3 rounded-[8px] text-white font-semibold text-base transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none"
          style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
        >
          Continue
        </button>
      )}

      {/* Skip — if no release available yet */}
      {!installed && !installing && !downloadUrl && !checking && (
        <button
          onClick={() => setOnboardingStep('signin')}
          className="text-sm text-white/30 hover:text-white/60 underline transition-colors"
        >
          Skip for now
        </button>
      )}
    </div>
  )
}
