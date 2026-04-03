import { useState, useEffect } from 'react'
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
  const { hasUpdate, pendingUpdate, isSignedIn, userEmail, signOut, signIn, setOnboardingDone, setOnboardingStep } = useAppStore()

  const FPS_STEPS = [1, 15, 30, 45, 60]

  const [ram, setRam] = useState(4)
  const [cores, setCores] = useState(4)
  const [resolution, setResolution] = useState('1920x1080')
  const [fpsIndex, setFpsIndex] = useState(4) // default: 60
  const [launchOnStartup, setLaunchOnStartup] = useState(false)
  const [checkingUpdate, setCheckingUpdate] = useState(false)
  const [updateMsg, setUpdateMsg] = useState('')
  const [updateUrl, setUpdateUrl] = useState<string | null>(null)
  const [appVersion, setAppVersion] = useState('')
  const [signingIn, setSigningIn] = useState(false)
  const [signInError, setSignInError] = useState('')
  const [vmRunning, setVmRunning] = useState(false)
  const [vmBusy, setVmBusy] = useState(false)
  const [vmError, setVmError] = useState('')
  const [uninstalling, setUninstalling] = useState(false)
  const [uninstallDone, setUninstallDone] = useState(false)

  useEffect(() => {
    window.nunu?.getVersion?.().then((v) => setAppVersion(v))
    window.nunu?.isVmRunning?.().then((r) => setVmRunning(r))
  }, [])

  useEffect(() => {
    return window.nunu?.onVmStatus?.((evt) => {
      if (evt.status === 'booting') { setVmRunning(false); setVmBusy(true) }
      else if (evt.status === 'ready') { setVmRunning(true); setVmBusy(false) }
      else if (evt.status === 'stopped') { setVmRunning(false); setVmBusy(false) }
      else if (evt.status === 'error') { setVmRunning(false); setVmBusy(false); setVmError(evt.error ?? 'Error') }
    })
  }, [])

  const handleStartVm = async () => {
    setVmError('')
    setVmBusy(true)
    const result = await window.nunu?.bootVm?.({ memoryMb: ram * 1024, cores })
    if (result && !result.success && !result.alreadyRunning) {
      setVmError(result.error ?? 'Failed to start')
      setVmBusy(false)
    }
  }

  const handleStopVm = async () => {
    setVmBusy(true)
    await window.nunu?.stopVm?.()
    setVmBusy(false)
  }

  const handleUninstall = async () => {
    if (!confirm('Remove Android emulator data? This deletes the AVD and shader cache.')) return
    setUninstalling(true)
    await window.nunu?.uninstallAndroid?.()
    setUninstalling(false)
    setUninstallDone(true)
    setVmRunning(false)
    setTimeout(() => setUninstallDone(false), 3000)
  }

  const handleCheckUpdate = async () => {
    setCheckingUpdate(true)
    setUpdateMsg('')
    setUpdateUrl(null)
    try {
      const result = await window.nunu.checkUpdate()
      const release = result.release as { tag_name?: string; html_url?: string } | null
      if (result.hasUpdate && release) {
        setUpdateMsg(`v${result.installedVersion} → ${release.tag_name}`)
        setUpdateUrl(release.html_url ?? null)
        useAppStore.getState().setHasUpdate(true, result.release as never)
      } else if (result.error) {
        setUpdateMsg('Could not check for updates.')
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
      {/* Updates */}
      <Section title="Updates">
        <Row
          label="nunu"
          hint={appVersion ? `Installed: v${appVersion}` : undefined}
        >
          <div className="flex items-center gap-3">
            {hasUpdate && updateUrl && (
              <button
                onClick={() => window.nunu?.openExternal?.(updateUrl)}
                className="px-3 py-1.5 rounded-[6px] text-xs font-semibold text-white transition-all hover:scale-105 focus:outline-none"
                style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
              >
                Download update
              </button>
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
            <p className={`text-xs ${hasUpdate ? 'text-[#5B6EF5]' : 'text-white/40'}`}>{updateMsg}</p>
          </div>
        )}
      </Section>

      {/* General */}
      <Section title="General">
        <Row label="Launch on startup" hint="Start nunu when your computer boots">
          <Toggle value={launchOnStartup} onChange={setLaunchOnStartup} />
        </Row>
        <Row
          label="Android Emulator"
          hint={vmBusy ? 'Starting…' : vmRunning ? 'Running' : 'Stopped'}
        >
          <div className="flex items-center gap-2">
            {vmRunning ? (
              <button
                onClick={handleStopVm}
                disabled={vmBusy}
                className="px-3 py-1.5 rounded-[6px] text-xs font-semibold text-white bg-red-600/70 hover:bg-red-600 transition-colors focus:outline-none disabled:opacity-50"
              >
                Stop
              </button>
            ) : (
              <button
                onClick={handleStartVm}
                disabled={vmBusy}
                className="px-3 py-1.5 rounded-[6px] text-xs font-semibold text-white transition-colors focus:outline-none disabled:opacity-50"
                style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
              >
                {vmBusy ? 'Starting…' : 'Start'}
              </button>
            )}
            <button
              onClick={handleUninstall}
              disabled={vmBusy || uninstalling}
              className="px-3 py-1.5 rounded-[6px] text-xs font-medium text-red-400 border border-red-500/20 hover:bg-red-500/10 transition-colors focus:outline-none disabled:opacity-50"
            >
              {uninstalling ? 'Removing…' : uninstallDone ? 'Removed' : 'Uninstall'}
            </button>
          </div>
        </Row>
        {vmError && (
          <div className="px-5 pb-3">
            <p className="text-red-400 text-xs">{vmError}</p>
          </div>
        )}
        <Row label="Missed something?" hint="Re-run the Getting Started setup wizard">
          <button
            onClick={() => { setOnboardingDone(false); setOnboardingStep('welcome') }}
            className="px-3 py-1.5 rounded-[6px] text-xs font-medium text-white/60 border border-white/10 hover:bg-white/5 transition-colors focus:outline-none"
          >
            Redo Getting Started
          </button>
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
        <Row label={`FPS cap: ${FPS_STEPS[fpsIndex]}`} hint="Limit frame rate to reduce power consumption">
          <div className="flex items-center gap-3">
            <input
              type="range"
              min={0}
              max={FPS_STEPS.length - 1}
              step={1}
              value={fpsIndex}
              onChange={(e) => setFpsIndex(Number(e.target.value))}
              className="w-32 accent-[#5B6EF5]"
            />
            <span className="text-white/50 text-xs w-10 text-right">
              {FPS_STEPS[fpsIndex] === 1 ? 'Unlimited' : `${FPS_STEPS[fpsIndex]} fps`}
            </span>
          </div>
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
            <p className="text-white/40 text-xs mt-0.5">{appVersion ? `v${appVersion}` : 'Alpha'}</p>
            <p className="text-white/30 text-xs mt-2">Android without compromise</p>
          </div>
        </div>
      </Section>
    </div>
  )
}
