import { useAppStore } from '../../store/appStore'
import { WelcomeStep } from './WelcomeStep'
import { DownloadStep } from './DownloadStep'
import { SafetyNetStep } from './SafetyNetStep'
import { SignInStep } from './SignInStep'
import { CompleteStep } from './CompleteStep'

export function OnboardingFlow() {
  const { onboardingStep } = useAppStore()

  return (
    <div className="h-full w-full flex items-center justify-center bg-[#0D0F14] overflow-hidden">
      {/* Background gradient blobs */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div
          className="absolute -top-32 -left-32 w-96 h-96 rounded-full opacity-20 blur-3xl"
          style={{ background: 'radial-gradient(circle, #5B6EF5, transparent)' }}
        />
        <div
          className="absolute -bottom-32 -right-32 w-96 h-96 rounded-full opacity-20 blur-3xl"
          style={{ background: 'radial-gradient(circle, #8B5CF6, transparent)' }}
        />
      </div>

      {/* Card */}
      <div
        className="relative w-[900px] h-[620px] bg-[#141720] rounded-[16px] overflow-hidden shadow-2xl border border-white/5 animate-fade-in-up"
      >
        {/* Step content */}
        <div className="h-full">
          {onboardingStep === 'welcome' && <WelcomeStep />}
          {onboardingStep === 'downloading' && <DownloadStep />}
          {onboardingStep === 'safetynet' && <SafetyNetStep />}
          {onboardingStep === 'signin' && <SignInStep />}
          {onboardingStep === 'complete' && <CompleteStep />}
        </div>

        {/* Step dots */}
        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 flex gap-2">
          {(['welcome', 'downloading', 'safetynet', 'signin', 'complete'] as const).map(
            (step, i) => (
              <div
                key={step}
                className={`rounded-full transition-all duration-300 ${
                  onboardingStep === step
                    ? 'w-6 h-2 bg-gradient-to-r from-[#5B6EF5] to-[#8B5CF6]'
                    : 'w-2 h-2 bg-white/20'
                }`}
              />
            )
          )}
        </div>
      </div>
    </div>
  )
}
