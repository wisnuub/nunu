import { useAppStore } from '../../store/appStore'

export function WelcomeStep() {
  const { setOnboardingStep } = useAppStore()

  const handleGetStarted = () => {
    setOnboardingStep('downloading')
    // Kick off the install in the background
    if (window.nunu?.startInstall) {
      window.nunu.startInstall({ androidVersion: '34' }).catch(() => {/* handled in DownloadStep */})
    }
  }

  return (
    <div className="h-full flex flex-col items-center justify-center px-12 text-center gap-8 pb-10">
      {/* Logo */}
      <div className="flex flex-col items-center gap-4">
        <div
          className="w-20 h-20 rounded-2xl flex items-center justify-center text-4xl mb-2 animate-pulse-glow"
          style={{
            background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)',
          }}
        >
          🤖
        </div>

        <h1
          className="text-8xl font-bold gradient-text"
          style={{ letterSpacing: '-2px' }}
        >
          nunu
        </h1>

        <p className="text-2xl font-medium text-white/80">
          Android without compromise
        </p>

        <p className="text-base text-white/50 max-w-md leading-relaxed">
          Run Android games natively on your Mac or PC. Full performance.
          No compromises.
        </p>
      </div>

      {/* Feature pills */}
      <div className="flex gap-3 flex-wrap justify-center">
        {['Native Performance', 'Android 14', 'Google Play', 'SafetyNet Certified'].map(
          (feat) => (
            <span
              key={feat}
              className="px-4 py-1.5 rounded-full text-sm font-medium text-white/70 border border-white/10 bg-white/5"
            >
              {feat}
            </span>
          )
        )}
      </div>

      {/* CTA */}
      <button
        onClick={handleGetStarted}
        className="px-10 py-4 rounded-[8px] text-white font-semibold text-lg transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none"
        style={{
          background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)',
          boxShadow: '0 8px 32px rgba(91, 110, 245, 0.4)',
        }}
      >
        Get Started
      </button>
    </div>
  )
}
