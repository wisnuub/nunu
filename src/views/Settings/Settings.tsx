import { useState } from 'react'
import { useAppStore } from '../../store/appStore'

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-8">
      <h2 className="text-xs font-semibold text-white/40 uppercase tracking-widest mb-4">{title}</h2>
      <div className="rounded-[12px] bg-[#141720] border border-white/5 divide-y divide-white/5">
        {children}
      </div>
    </div>
  )
}

function Row({ label, hint, children }: { label: string; hint?: string; children?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between px-5 py-4">
      <div>
        <p className="text-sm font-medium text-white">{label}</p>
        {hint && <p className="text-xs text-white/35 mt-0.5">{hint}</p>}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  )
}

function Toggle({ value, onChange }: { value: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!value)}
      className={`relative w-10 h-5 rounded-full transition-all duration-200 focus:outline-none ${
        value ? '' : 'bg-white/10'
      }`}
      style={value ? { background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' } : {}}
    >
      <span
        className="absolute top-0.5 w-4 h-4 rounded-full bg-white shadow transition-all duration-200"
        style={{ left: value ? '22px' : '2px' }}
      />
    </button>
  )
}

export function Settings() {
  const { hasUpdate, pendingUpdate, isSignedIn, userEmail, signOut, signIn } = useAppStore()

  const [ram, setRam] = useState(4)
  const [cores, setCores] = useState(4)
  const [resolution, setResolution] = useState('1920x1080')
  const [fpsCap, setFpsCap] = useState(false)
  const [launchOnStartup, setLaunchOnStartup] = useState(false)
  const [checkingUpdate, setCheckingUpdate] = useState(false)
  const [updateMsg, setUpdateMsg] = useState('')
  const [signingIn, setSigningIn] = useState(false)
  const [signInError, setSignInError] = useState('')

  const handleCheckUpdate = async () => {
    setCheckingUpdate(true)
    setUpdateMsg('')
    try {
      const result = await window.nunu.checkUpdate()
      if (result.hasUpdate) {
        setUpdateMsg(`Update available: ${(result.release as { tag_name?: string })?.tag_name ?? 'new version'}`)
        useAppStore.getState().setHasUpdate(true, result.release as never)
      } else {
        setUpdateMsg('You are up to date.')
      }
    } catch {
      setUpdateMsg('Could not check for updates.')
    }
    setCheckingUpdate(false)
  }

  const handleSignIn = async () => {
    setSigningIn(true)
    setSignInError('')
    try {
      const result = await window.nunu?.signInWithGoogle()
      if (result?.success) {
        signIn(result.email ?? '')
      } else if (result?.error === 'NO_CLIENT_ID') {
        setSignInError('Google Client ID not configured in ~/.nunu/config.json')
      } else {
        setSignInError(result?.error ?? 'Sign-in failed')
      }
    } catch (err) {
      setSignInError(err instanceof Error ? err.message : 'Unknown error')
    }
    setSigningIn(false)
  }

  return (
    <div className="pt-4 max-w-2xl">
      {/* Android Engine */}
      <Section title="Android Engine">
        <Row
          label="Installed version"
          hint={pendingUpdate ? `Update: ${pendingUpdate.tag_name}` : undefined}
        >
          <div className="flex items-center gap-3">
            {hasUpdate && (
              <span
                className="px-2 py-0.5 rounded-full text-xs font-medium text-white"
                style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
              >
                Update ready
              </span>
            )}
            <button
              onClick={handleCheckUpdate}
              disabled={checkingUpdate}
              className="px-4 py-1.5 rounded-[6px] text-sm font-medium text-white/70 border border-white/10 hover:bg-white/5 transition-colors focus:outline-none disabled:opacity-50"
            >
              {checkingUpdate ? 'Checking…' : 'Check for updates'}
            </button>
          </div>
        </Row>
        {updateMsg && (
          <div className="px-5 pb-4">
            <p className="text-xs text-white/40">{updateMsg}</p>
          </div>
        )}
      </Section>

      {/* General */}
      <Section title="General">
        <Row label="Launch on startup" hint="Start nunu when your computer boots">
          <Toggle value={launchOnStartup} onChange={setLaunchOnStartup} />
        </Row>
        <Row label="Default Android version">
          <select
            value="13"
            className="bg-white/5 border border-white/10 rounded-[6px] text-sm text-white px-3 py-1.5 focus:outline-none"
          >
            <option value="13">Android 13</option>
            <option value="12">Android 12</option>
            <option value="11">Android 11</option>
          </select>
        </Row>
      </Section>

      {/* Performance */}
      <Section title="Performance">
        <Row label={`RAM allocation: ${ram} GB`} hint="Memory dedicated to the Android engine">
          <input
            type="range"
            min={2}
            max={16}
            step={2}
            value={ram}
            onChange={(e) => setRam(Number(e.target.value))}
            className="w-32 accent-[#5B6EF5]"
          />
        </Row>
        <Row label={`CPU cores: ${cores}`} hint="Processor cores assigned to Android">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setCores(Math.max(1, cores - 1))}
              className="w-7 h-7 rounded-full bg-white/5 hover:bg-white/10 text-white font-bold transition-colors focus:outline-none"
            >
              −
            </button>
            <span className="text-white w-4 text-center text-sm font-medium">{cores}</span>
            <button
              onClick={() => setCores(Math.min(16, cores + 1))}
              className="w-7 h-7 rounded-full bg-white/5 hover:bg-white/10 text-white font-bold transition-colors focus:outline-none"
            >
              +
            </button>
          </div>
        </Row>
      </Section>

      {/* Display */}
      <Section title="Display">
        <Row label="Resolution">
          <select
            value={resolution}
            onChange={(e) => setResolution(e.target.value)}
            className="bg-white/5 border border-white/10 rounded-[6px] text-sm text-white px-3 py-1.5 focus:outline-none"
          >
            <option value="1920x1080">1920 × 1080</option>
            <option value="2560x1440">2560 × 1440</option>
            <option value="3840x2160">3840 × 2160</option>
            <option value="1280x720">1280 × 720</option>
          </select>
        </Row>
        <Row label="FPS cap" hint="Limit frame rate to reduce power consumption">
          <Toggle value={fpsCap} onChange={setFpsCap} />
        </Row>
      </Section>

      {/* Google Account */}
      <Section title="Google Account">
        {isSignedIn ? (
          <div className="px-5 py-4 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div
                className="w-10 h-10 rounded-full flex items-center justify-center font-bold text-white text-sm shrink-0"
                style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
              >
                {(userEmail ?? 'U')[0].toUpperCase()}
              </div>
              <div>
                <p className="text-sm font-medium text-white">{userEmail}</p>
                <p className="text-xs text-white/40 mt-0.5">Google Account · Signed in</p>
              </div>
            </div>
            <button
              onClick={signOut}
              className="px-4 py-1.5 rounded-[6px] text-sm font-medium text-red-400 border border-red-500/20 hover:bg-red-500/10 transition-colors focus:outline-none"
            >
              Sign out
            </button>
          </div>
        ) : (
          <div className="px-5 py-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-white">No account connected</p>
                <p className="text-xs text-white/35 mt-0.5">Sign in to sync saves and purchases</p>
              </div>
              <button
                onClick={handleSignIn}
                disabled={signingIn}
                className="px-4 py-1.5 rounded-[6px] text-sm font-medium text-white transition-all focus:outline-none disabled:opacity-50"
                style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
              >
                {signingIn ? 'Opening…' : 'Sign In'}
              </button>
            </div>
            {signInError && (
              <p className="text-red-400 text-xs mt-3">{signInError}</p>
            )}
          </div>
        )}
      </Section>

      {/* About */}
      <Section title="About">
        <div className="px-5 py-6 flex flex-col items-center gap-3">
          <div
            className="w-14 h-14 rounded-xl flex items-center justify-center font-black text-white text-xl"
            style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
          >
            n
          </div>
          <div className="text-center">
            <p className="text-white font-bold text-lg">nunu</p>
            <p className="text-white/40 text-xs mt-0.5">Alpha v0.0.2</p>
            <p className="text-white/30 text-xs mt-2">Android without compromise</p>
          </div>
        </div>
      </Section>
    </div>
  )
}
