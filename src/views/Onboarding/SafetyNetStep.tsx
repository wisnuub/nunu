import { useEffect, useState } from 'react'
import { useAppStore } from '../../store/appStore'

const STEPS = [
  'Starting Android environment',
  'Waiting for ADB connection',
  'Applying device fingerprint (Pixel 7)',
  'Enabling Google Mobile Services',
  'Rebooting device',
  'Verifying certification',
]

type StepState = 'pending' | 'running' | 'done' | 'error'

export function SafetyNetStep() {
  const { safetyNetProgress, safetyNetPassed, setSafetyNetProgress, setSafetyNetPassed, setOnboardingStep } =
    useAppStore()

  const [stepStates, setStepStates] = useState<StepState[]>(
    STEPS.map(() => 'pending')
  )
  const [currentStep, setCurrentStep] = useState(-1)
  const [started, setStarted] = useState(false)

  useEffect(() => {
    if (started) return
    setStarted(true)

    // Subscribe to progress events
    let unsub: (() => void) | undefined
    if (window.nunu?.onSafetyNetProgress) {
      unsub = window.nunu.onSafetyNetProgress((event) => {
        setSafetyNetProgress(event.percent, event.stepName)
        setCurrentStep(event.step)
        setStepStates((prev) => {
          const next = [...prev]
          // Mark prior steps done
          for (let i = 0; i < event.step; i++) next[i] = 'done'
          next[event.step] = event.done ? 'done' : 'running'
          return next
        })
      })
    }

    // Trigger setup
    if (window.nunu?.setupSafetyNet) {
      window.nunu
        .setupSafetyNet()
        .then((result) => {
          setSafetyNetPassed(result.passed)
          setStepStates(STEPS.map(() => 'done'))
        })
        .catch(() => {
          setSafetyNetPassed(false)
        })
    } else {
      // Demo simulation for web dev mode
      simulateProgress()
    }

    return () => unsub?.()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const simulateProgress = async () => {
    for (let i = 0; i < STEPS.length; i++) {
      setCurrentStep(i)
      setStepStates((prev) => {
        const next = [...prev]
        next[i] = 'running'
        return next
      })
      setSafetyNetProgress(Math.round(((i + 0.5) / STEPS.length) * 100), STEPS[i])
      await new Promise((r) => setTimeout(r, 1500))
      setStepStates((prev) => {
        const next = [...prev]
        next[i] = 'done'
        return next
      })
    }
    setSafetyNetProgress(100, 'Certification complete')
    setSafetyNetPassed(true)
  }

  const handleContinue = () => setOnboardingStep('signin')

  // Auto-advance when done
  useEffect(() => {
    if (safetyNetPassed === true) {
      const t = setTimeout(() => setOnboardingStep('signin'), 1500)
      return () => clearTimeout(t)
    }
  }, [safetyNetPassed, setOnboardingStep])

  return (
    <div className="h-full flex flex-col px-12 py-10 gap-6 pb-14">
      <div>
        <h2 className="text-2xl font-bold text-white mb-1">Configuring device certification</h2>
        <p className="text-white/50 text-sm leading-relaxed">
          Setting up your Android environment to support Google Play and certified apps.
        </p>
      </div>

      {/* Steps list */}
      <div className="flex-1 flex flex-col gap-3">
        {STEPS.map((step, i) => {
          const state = stepStates[i]
          return (
            <div key={step} className="flex items-center gap-4">
              {/* Icon */}
              <div className="w-7 h-7 flex items-center justify-center shrink-0">
                {state === 'done' ? (
                  <svg className="text-[#16A34A]" width="20" height="20" viewBox="0 0 20 20" fill="none">
                    <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5" fill="none" />
                    <path d="M6 10l3 3 5-5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                ) : state === 'running' ? (
                  <svg className="animate-spin text-[#5B6EF5]" width="20" height="20" viewBox="0 0 20 20" fill="none">
                    <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="2" strokeDasharray="40 14" strokeLinecap="round" />
                  </svg>
                ) : state === 'error' ? (
                  <svg className="text-red-500" width="20" height="20" viewBox="0 0 20 20" fill="none">
                    <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5" />
                    <path d="M7 7l6 6M13 7l-6 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
                  </svg>
                ) : (
                  <div className="w-4 h-4 rounded-full border border-white/20" />
                )}
              </div>

              {/* Label */}
              <span
                className={`text-sm font-medium transition-colors ${
                  state === 'done'
                    ? 'text-white/90'
                    : state === 'running'
                    ? 'text-white'
                    : 'text-white/30'
                }`}
              >
                {step}
              </span>
            </div>
          )
        })}
      </div>

      {/* Overall progress bar */}
      <div className="w-full">
        <div className="w-full h-1.5 bg-white/10 rounded-full overflow-hidden">
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{
              width: `${safetyNetProgress}%`,
              background: 'linear-gradient(90deg, #5B6EF5, #8B5CF6)',
            }}
          />
        </div>
        <div className="flex justify-between mt-1.5 text-xs text-white/30">
          <span>{safetyNetProgress}%</span>
          {safetyNetPassed === null && <span>This may take a minute…</span>}
        </div>
      </div>

      {/* Result banners */}
      {safetyNetPassed === true && (
        <div className="flex items-center gap-3 px-4 py-3 rounded-[8px] bg-[#16A34A]/20 border border-[#16A34A]/30">
          <svg className="text-[#16A34A] shrink-0" width="20" height="20" viewBox="0 0 20 20" fill="none">
            <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5" />
            <path d="M6 10l3 3 5-5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span className="text-[#16A34A] text-sm font-medium">
            Device certified — Google Play is ready
          </span>
        </div>
      )}

      {safetyNetPassed === false && (
        <div className="flex flex-col gap-2 px-4 py-3 rounded-[8px] bg-[#F59E0B]/10 border border-[#F59E0B]/30">
          <div className="flex items-center gap-3">
            <svg className="text-[#F59E0B] shrink-0" width="20" height="20" viewBox="0 0 20 20" fill="none">
              <path d="M10 3L18 17H2L10 3Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
              <path d="M10 9v4M10 14.5v.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            </svg>
            <span className="text-[#F59E0B] text-sm font-medium">
              Certification pending — some apps may require manual setup
            </span>
          </div>
          <button
            onClick={handleContinue}
            className="self-end text-xs text-white/50 hover:text-white/80 underline transition-colors"
          >
            Continue anyway
          </button>
        </div>
      )}
    </div>
  )
}
