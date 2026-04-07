import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAppStore } from '../../store/appStore'

export function CompleteStep() {
  const { isSignedIn, userEmail, safetyNetPassed, setOnboardingDone } = useAppStore()
  const navigate = useNavigate()
  const [animating, setAnimating] = useState(false)

  useEffect(() => {
    const t = setTimeout(() => setAnimating(true), 100)
    return () => clearTimeout(t)
  }, [])

  const handleLaunch = () => {
    setOnboardingDone(true)
    navigate('/launcher')
  }

  return (
    <div className="h-full flex flex-col items-center justify-center px-12 gap-8 pb-10">
      {/* Animated checkmark ring */}
      <div className="relative w-32 h-32">
        <svg width="128" height="128" viewBox="0 0 128 128" fill="none">
          {/* Outer ring */}
          <circle
            cx="64"
            cy="64"
            r="58"
            stroke="#16A34A"
            strokeWidth="4"
            strokeLinecap="round"
            strokeDasharray={`${2 * Math.PI * 58}`}
            strokeDashoffset={animating ? 0 : 2 * Math.PI * 58}
            style={{
              transition: 'stroke-dashoffset 1s cubic-bezier(0.4, 0, 0.2, 1)',
              transform: 'rotate(-90deg)',
              transformOrigin: '64px 64px',
            }}
          />
          {/* Checkmark */}
          <path
            d="M38 64l18 18 34-34"
            stroke="#16A34A"
            strokeWidth="5"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeDasharray="100"
            strokeDashoffset={animating ? 0 : 100}
            style={{
              transition: 'stroke-dashoffset 0.6s cubic-bezier(0.4, 0, 0.2, 1) 0.8s',
            }}
          />
        </svg>
      </div>

      <div className="text-center">
        <h2 className="text-3xl font-bold text-white mb-2">You're all set!</h2>
        <p className="text-white/50 text-base">
          nunu is ready to launch your Android games.
        </p>
      </div>

      {/* Summary */}
      <div className="w-full max-w-sm flex flex-col gap-3">
        {window.nunu?.platform === 'darwin' ? (
          <SummaryRow
            icon="✅"
            label="nunu-apple engine"
            value="Ready"
            ok
          />
        ) : (
          <>
            <SummaryRow
              icon="✅"
              label="Android runtime"
              value="Android 14"
              ok
            />
            <SummaryRow
              icon={safetyNetPassed ? '🛡️' : '⚠️'}
              label="Device certification"
              value={safetyNetPassed ? 'Certified (Pixel 7)' : 'Pending'}
              ok={safetyNetPassed === true}
              warn={safetyNetPassed === false}
            />
          </>
        )}
        <SummaryRow
          icon={isSignedIn ? '👤' : '⊘'}
          label="Google Account"
          value={isSignedIn && userEmail ? userEmail : 'Skipped'}
          ok={isSignedIn}
        />
      </div>

      {/* Launch button */}
      <button
        onClick={handleLaunch}
        className="px-10 py-4 rounded-[8px] text-white font-semibold text-lg transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none"
        style={{
          background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)',
          boxShadow: '0 8px 32px rgba(91, 110, 245, 0.4)',
        }}
      >
        Launch nunu
      </button>
    </div>
  )
}

function SummaryRow({
  icon,
  label,
  value,
  ok,
  warn,
}: {
  icon: string
  label: string
  value: string
  ok?: boolean
  warn?: boolean
}) {
  return (
    <div className="flex items-center justify-between px-4 py-3 rounded-[8px] bg-white/5 border border-white/5">
      <div className="flex items-center gap-3">
        <span>{icon}</span>
        <span className="text-white/60 text-sm">{label}</span>
      </div>
      <span
        className={`text-sm font-medium ${
          ok ? 'text-[#16A34A]' : warn ? 'text-[#F59E0B]' : 'text-white/40'
        }`}
      >
        {value}
      </span>
    </div>
  )
}
