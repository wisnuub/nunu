import { useAppStore } from '../../store/appStore'

const GOOGLE_OAUTH_URL =
  'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&client_id=nunu-app&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Foauth&scope=email%20profile'

export function SignInStep() {
  const { setOnboardingStep, signIn } = useAppStore()

  const handleSkip = () => setOnboardingStep('complete')

  // In production, the webview would post a message with the token/email.
  // This stub just listens for a message event.
  const handleWebviewMessage = (e: MessageEvent) => {
    if (typeof e.data === 'object' && e.data?.type === 'google-signin') {
      const email = e.data.email as string
      if (email) {
        signIn(email)
        setOnboardingStep('complete')
      }
    }
  }

  return (
    <div className="h-full flex flex-col items-center justify-center px-12 gap-6 pb-10">
      <div className="text-center">
        <div className="text-5xl mb-4">🔑</div>
        <h2 className="text-2xl font-bold text-white mb-2">Connect your Google Account</h2>
        <p className="text-white/50 text-sm">
          Sign in to sync your games and purchases across devices.
        </p>
      </div>

      {/* Webview for Google OAuth */}
      <div
        className="w-full max-w-md rounded-[12px] overflow-hidden border border-white/10 bg-[#0D0F14]"
        style={{ height: 320 }}
      >
        {/* @ts-ignore – webview is an Electron-specific element */}
        <webview
          src={GOOGLE_OAUTH_URL}
          style={{ width: '100%', height: '100%' }}
          webpreferences="nodeIntegration=no, contextIsolation=yes"
          allowpopups={true}
        />
      </div>

      <button
        onClick={handleSkip}
        className="text-sm text-white/40 hover:text-white/70 underline transition-colors focus:outline-none"
      >
        Skip for now
      </button>
    </div>
  )
}
