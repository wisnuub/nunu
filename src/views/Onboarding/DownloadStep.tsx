import { useEffect } from 'react'
import { useAppStore } from '../../store/appStore'

const RADIUS = 70
const CIRCUMFERENCE = 2 * Math.PI * RADIUS

export function DownloadStep() {
  const {
    downloadProgress,
    downloadStatus,
    setDownloadProgress,
    setOnboardingStep,
  } = useAppStore()

  useEffect(() => {
    if (typeof window === 'undefined' || !window.nunu?.onInstallProgress) return

    const unsub = window.nunu.onInstallProgress((progress) => {
      if (progress.phase === 'avm-core' || progress.phase === 'android-image') {
        const combinedPhase = progress.phase === 'avm-core' ? 0 : 1
        const base = combinedPhase * 50
        const pct = base + Math.round(progress.percent * 0.5)
        setDownloadProgress(pct, progress.status)

        if (progress.phase === 'android-image' && progress.percent >= 100) {
          setTimeout(() => setOnboardingStep('safetynet'), 800)
        }
      }
    })

    return unsub
  }, [setDownloadProgress, setOnboardingStep])

  const strokeDashoffset = CIRCUMFERENCE - (downloadProgress / 100) * CIRCUMFERENCE

  return (
    <div className="h-full flex flex-col items-center justify-center px-12 gap-8 pb-10">
      <div className="text-center mb-2">
        <h2 className="text-3xl font-bold text-white mb-2">Setting up Android</h2>
        <p className="text-white/50 text-base">
          Downloading the Android runtime environment. This takes a few minutes.
        </p>
      </div>

      {/* Circular progress ring */}
      <div className="relative">
        <svg width="180" height="180" className="progress-ring" style={{ transform: 'rotate(-90deg)' }}>
          {/* Track */}
          <circle
            cx="90"
            cy="90"
            r={RADIUS}
            fill="none"
            stroke="#1e2130"
            strokeWidth="10"
          />
          {/* Progress */}
          <circle
            cx="90"
            cy="90"
            r={RADIUS}
            fill="none"
            stroke="url(#progressGrad)"
            strokeWidth="10"
            strokeLinecap="round"
            strokeDasharray={CIRCUMFERENCE}
            strokeDashoffset={strokeDashoffset}
          />
          <defs>
            <linearGradient id="progressGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#5B6EF5" />
              <stop offset="100%" stopColor="#8B5CF6" />
            </linearGradient>
          </defs>
        </svg>
        {/* Percent label in center */}
        <div
          className="absolute inset-0 flex flex-col items-center justify-center"
          style={{ transform: 'rotate(0deg)' }}
        >
          <span className="text-4xl font-bold text-white">{downloadProgress}%</span>
          <span className="text-xs text-white/40 mt-1">complete</span>
        </div>
      </div>

      {/* Status text */}
      <div className="text-center">
        <p className="text-white/70 text-sm font-medium">
          {downloadStatus || 'Initializing…'}
        </p>
      </div>

      {/* Linear progress bar */}
      <div className="w-full max-w-sm">
        <div className="w-full h-2 bg-white/10 rounded-full overflow-hidden">
          <div
            className="h-full rounded-full transition-all duration-300"
            style={{
              width: `${downloadProgress}%`,
              background: 'linear-gradient(90deg, #5B6EF5, #8B5CF6)',
            }}
          />
        </div>
        <div className="flex justify-between mt-2 text-xs text-white/30">
          <span>AVM Core</span>
          <span>Android Image</span>
        </div>
      </div>

      <p className="text-xs text-white/30 text-center max-w-xs">
        You can minimize this window. Setup continues in the background.
      </p>
    </div>
  )
}
