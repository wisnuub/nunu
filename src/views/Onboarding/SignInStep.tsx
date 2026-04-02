import { useState } from 'react'
import { useAppStore } from '../../store/appStore'

type State = 'idle' | 'waiting' | 'success' | 'no-client' | 'error'

export function SignInStep() {
  const { setOnboardingStep, signIn } = useAppStore()
  const [state, setState] = useState<State>('idle')
  const [email, setEmail] = useState('')
  const [errorMsg, setErrorMsg] = useState('')

  const handleSignIn = async () => {
    setState('waiting')
    try {
      const result = await window.nunu?.signInWithGoogle()
      if (!result) { setState('error'); setErrorMsg('Sign-in unavailable'); return }

      if (!result.success) {
        if (result.error === 'NO_CLIENT_ID') {
          setState('no-client')
        } else {
          setState('error')
          setErrorMsg(result.error ?? 'Unknown error')
        }
        return
      }

      setEmail(result.email ?? '')
      setState('success')
      signIn(result.email ?? '')
      setTimeout(() => setOnboardingStep('complete'), 1200)
    } catch (err) {
      setState('error')
      setErrorMsg(err instanceof Error ? err.message : 'Unknown error')
    }
  }

  const handleSkip = () => setOnboardingStep('complete')

  return (
    <div className="h-full flex flex-col items-center justify-center px-12 gap-6 pb-10">
      {/* Header */}
      <div className="text-center">
        <div className="w-16 h-16 rounded-2xl mx-auto mb-5 flex items-center justify-center"
          style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}>
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" fill="white" opacity="0.9"/>
            <path d="M12 7a2 2 0 100 4 2 2 0 000-4zM12 13c-2.67 0-8 1.34-8 4v1h16v-1c0-2.66-5.33-4-8-4z" fill="#5B6EF5"/>
          </svg>
        </div>
        <h2 className="text-2xl font-bold text-white mb-2">Connect your Google Account</h2>
        <p className="text-white/50 text-sm leading-relaxed max-w-xs mx-auto">
          Sign in to sync your games and purchases across devices. Your browser will open to complete sign-in securely.
        </p>
      </div>

      {/* State-dependent content */}
      {state === 'success' && (
        <div className="flex items-center gap-3 px-5 py-3 rounded-xl bg-[#16A34A]/20 border border-[#16A34A]/30 w-full max-w-sm">
          <svg className="text-[#16A34A] shrink-0" width="20" height="20" viewBox="0 0 20 20" fill="none">
            <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5"/>
            <path d="M6 10l3 3 5-5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span className="text-[#16A34A] text-sm font-medium">Signed in as {email}</span>
        </div>
      )}

      {state === 'no-client' && (
        <div className="w-full max-w-sm rounded-xl border border-[#F59E0B]/30 bg-[#F59E0B]/10 p-4 text-sm space-y-3">
          <div className="flex items-center gap-2 text-[#F59E0B] font-medium">
            <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
              <path d="M10 3L18 17H2L10 3Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round"/>
              <path d="M10 9v4M10 14.5v.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
            </svg>
            Google client ID not configured
          </div>
          <p className="text-white/50 leading-relaxed">
            Create an OAuth 2.0 client in{' '}
            <span className="text-white/70">Google Cloud Console</span>{' '}
            (type: <span className="font-mono text-white/70">Desktop app</span>), then add it to:
          </p>
          <pre className="bg-black/30 rounded-lg px-3 py-2 font-mono text-xs text-white/60 overflow-x-auto">
{`~/.nunu/config.json
{
  "googleClientId": "YOUR_ID.apps.googleusercontent.com"
}`}
          </pre>
          <p className="text-white/40 text-xs">Restart nunu after saving the file.</p>
        </div>
      )}

      {state === 'error' && (
        <div className="flex items-center gap-3 px-5 py-3 rounded-xl bg-red-500/10 border border-red-500/30 w-full max-w-sm">
          <svg className="text-red-400 shrink-0" width="18" height="18" viewBox="0 0 20 20" fill="none">
            <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5"/>
            <path d="M7 7l6 6M13 7l-6 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
          </svg>
          <span className="text-red-400 text-sm">{errorMsg}</span>
        </div>
      )}

      {/* Sign in button */}
      {state !== 'success' && state !== 'no-client' && (
        <button
          onClick={handleSignIn}
          disabled={state === 'waiting'}
          className="flex items-center justify-center gap-3 w-full max-w-sm py-3 rounded-xl text-white font-medium text-sm transition-opacity disabled:opacity-60"
          style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
        >
          {state === 'waiting' ? (
            <>
              <svg className="animate-spin" width="16" height="16" viewBox="0 0 20 20" fill="none">
                <circle cx="10" cy="10" r="8" stroke="white" strokeWidth="2" strokeDasharray="40 14" strokeLinecap="round"/>
              </svg>
              Opening browser…
            </>
          ) : (
            <>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
                <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
                <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" fill="#FBBC05"/>
                <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
              </svg>
              Sign in with Google
            </>
          )}
        </button>
      )}

      {state === 'no-client' && (
        <button
          onClick={() => setState('idle')}
          className="text-sm text-[#5B6EF5] hover:text-[#8B5CF6] transition-colors"
        >
          Try again
        </button>
      )}

      <button
        onClick={handleSkip}
        className="text-sm text-white/30 hover:text-white/60 underline transition-colors focus:outline-none"
      >
        Skip for now
      </button>
    </div>
  )
}
