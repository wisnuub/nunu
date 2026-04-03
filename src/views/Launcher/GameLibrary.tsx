import { useState, useEffect } from 'react'
import { useAppStore } from '../../store/appStore'
import { GAMES, SYSTEM_APPS } from '../../data/games'
import { GameCard } from './GameCard'

function SystemAppTile({ packageId, name }: { packageId: string; name: string }) {
  const [artUrl, setArtUrl] = useState<string | null>(null)
  const [launching, setLaunching] = useState(false)
  const [error, setError] = useState('')
  const [restartPrompt, setRestartPrompt] = useState<{ runningGameName: string } | null>(null)

  useEffect(() => {
    window.nunu?.fetchGameArt?.(packageId).then((url) => { if (url) setArtUrl(url) })
  }, [packageId])

  const doLaunch = async (forceRestart?: boolean) => {
    setError('')
    setLaunching(true)
    const result = await window.nunu?.launchGame?.(packageId, name, { memoryMb: 4096, cores: 4 }, forceRestart)
    setLaunching(false)
    if (result?.needsRestart) {
      setRestartPrompt({ runningGameName: result.runningGameName ?? 'another game' })
    } else if (result && !result.success && !result.alreadyRunning) {
      setError(result.error ?? 'Failed')
      setTimeout(() => setError(''), 4000)
    }
  }

  return (
    <>
      {restartPrompt && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
          <div className="bg-[#1a1d2a] border border-white/10 rounded-[16px] shadow-2xl p-6 w-[320px] mx-4">
            <p className="text-white/50 text-xs font-medium uppercase tracking-wider mb-1">One game at a time</p>
            <h3 className="text-white text-base font-semibold mb-2">{restartPrompt.runningGameName} is running</h3>
            <p className="text-white/60 text-sm mb-5">Restart to open <span className="text-white font-medium">{name}</span>?</p>
            <div className="flex gap-2">
              <button onClick={() => setRestartPrompt(null)} className="flex-1 py-2 rounded-[8px] text-sm font-medium text-white/60 bg-white/5 hover:bg-white/10 transition-colors focus:outline-none">Cancel</button>
              <button onClick={() => { setRestartPrompt(null); doLaunch(true) }} className="flex-1 py-2 rounded-[8px] text-sm font-semibold text-white focus:outline-none" style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}>Restart &amp; Open</button>
            </div>
          </div>
        </div>
      )}
      <button
        onClick={() => doLaunch()}
        disabled={launching}
        className="flex flex-col items-center gap-2 p-3 rounded-[10px] hover:bg-white/5 transition-colors focus:outline-none group disabled:opacity-60"
        title={error || name}
      >
        <div
          className="relative w-14 h-14 rounded-2xl flex items-center justify-center overflow-hidden"
          style={{ background: 'linear-gradient(135deg, #1e2232, #2a2f45)' }}
        >
          {artUrl ? (
            <img src={artUrl} alt={name} className="w-full h-full object-cover rounded-2xl" />
          ) : (
            <span className="text-white/30 text-xs font-bold">{name[0]}</span>
          )}
          {launching && (
            <div className="absolute inset-0 bg-black/50 flex items-center justify-center rounded-2xl">
              <span className="w-4 h-4 rounded-full border border-white/30 border-t-white animate-spin" />
            </div>
          )}
        </div>
        <span className={`text-xs font-medium transition-colors ${error ? 'text-red-400' : 'text-white/50 group-hover:text-white/80'}`}>
          {error ? 'Error' : launching ? '…' : name}
        </span>
      </button>
    </>
  )
}

export function GameLibrary() {
  const { installedGames, setInstallProgress, addInstalledGame } = useAppStore()

  const featured = GAMES[0]
  const isFeaturedInstalled = installedGames.includes(featured.id)
  const featuredProgress = useAppStore((s) => s.installProgress[featured.id] ?? 0)
  const isFeaturedInstalling = featuredProgress > 0 && featuredProgress < 100

  const [featuredArt, setFeaturedArt] = useState<string | null>(null)
  const [featuredBanner, setFeaturedBanner] = useState<string | null>(null)
  const [featuredLaunching, setFeaturedLaunching] = useState(false)
  const [featuredLaunchStatus, setFeaturedLaunchStatus] = useState('')
  const [featuredLaunchError, setFeaturedLaunchError] = useState('')

  useEffect(() => {
    return window.nunu?.onVmStatus?.((evt) => {
      if (evt.status === 'booting') setFeaturedLaunchStatus('Booting…')
      else if (evt.status === 'ready') setFeaturedLaunchStatus('')
      else if (evt.status === 'stopped') { setFeaturedLaunchStatus(''); setFeaturedLaunching(false) }
    })
  }, [])

  useEffect(() => {
    window.nunu?.fetchGameArt?.(featured.packageId).then((url) => { if (url) setFeaturedArt(url) })
    window.nunu?.fetchGameBanner?.(featured.packageId).then((url) => { if (url) setFeaturedBanner(url) })
  }, [featured.packageId])

  const handleFeaturedAction = async () => {
    if (isFeaturedInstalled) {
      setFeaturedLaunchError('')
      setFeaturedLaunching(true)
      setFeaturedLaunchStatus('Starting…')
      const result = await window.nunu?.launchGame?.(featured.packageId, featured.name, featured.defaultConfig)
      setFeaturedLaunching(false)
      setFeaturedLaunchStatus('')
      if (result && !result.success && !result.alreadyRunning) {
        setFeaturedLaunchError(result.error ?? 'Failed to launch')
        setTimeout(() => setFeaturedLaunchError(''), 6000)
      }
      return
    }
    if (isFeaturedInstalling) return

    setInstallProgress(featured.id, 1)

    if (window.nunu?.installGame) {
      const unsub = window.nunu.onInstallProgress((evt) => {
        if (evt.phase === 'game') {
          setInstallProgress(featured.id, evt.percent)
          if (evt.percent >= 100) {
            addInstalledGame(featured.id)
            unsub()
          }
        }
      })
      await window.nunu.installGame(featured.id).catch(() => {
        setInstallProgress(featured.id, 0)
        unsub()
      })
    } else {
      for (let i = 1; i <= 100; i += 3) {
        await new Promise<void>((r) => setTimeout(r, 80))
        setInstallProgress(featured.id, i)
      }
      addInstalledGame(featured.id)
    }
  }

  return (
    <div className="flex flex-col gap-8 pt-4">
      {/* Featured hero card */}
      <div
        className="relative w-full rounded-[16px] overflow-hidden border border-white/5"
        style={
          featuredBanner
            ? { height: 280, backgroundImage: `url(${featuredBanner})`, backgroundSize: 'cover', backgroundPosition: 'center' }
            : { height: 280, background: `linear-gradient(135deg, ${featured.gradientFrom}, ${featured.gradientTo})` }
        }
      >
        {/* Background pattern */}
        <div className="absolute inset-0 overflow-hidden">
          <div
            className="absolute -bottom-6 -right-4 font-black text-[160px] leading-none select-none tracking-widest"
            style={{ color: 'rgba(255,255,255,0.07)' }}
          >
            {featured.abbr}
          </div>
        </div>

        {/* Content */}
        <div className="absolute inset-0 flex flex-col justify-end p-8 bg-gradient-to-t from-black/60 to-transparent">
          <div className="flex items-end justify-between gap-6">
            <div className="flex items-end gap-5">
              {featuredArt && (
                <img
                  src={featuredArt}
                  alt={featured.name}
                  className="w-20 h-20 rounded-2xl shadow-xl shrink-0"
                />
              )}
              <div>
                <div className="flex items-center gap-3 mb-3">
                  <span className="px-3 py-1 rounded-full bg-white/20 text-white/90 text-xs font-medium">
                    {featured.genre}
                  </span>
                  <span className="text-white/50 text-xs">{featured.size}</span>
                </div>
                <h2 className="text-4xl font-bold text-white mb-1">{featured.name}</h2>
                {featuredLaunchError && (
                  <p className="text-red-400 text-xs mt-1">{featuredLaunchError}</p>
                )}
                {featuredLaunchStatus && !featuredLaunchError && (
                  <p className="text-white/60 text-xs mt-1 flex items-center gap-1.5">
                    <span className="inline-block w-2.5 h-2.5 rounded-full border border-white/30 border-t-white/80 animate-spin" />
                    {featuredLaunchStatus}
                  </p>
                )}
              </div>
            </div>

            <button
              onClick={handleFeaturedAction}
              disabled={isFeaturedInstalling || featuredLaunching}
              className="px-8 py-3 rounded-[8px] text-white font-semibold text-sm transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none disabled:opacity-50 shrink-0"
              style={
                isFeaturedInstalled
                  ? { background: '#16A34A' }
                  : { background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }
              }
            >
              {isFeaturedInstalling
                ? `Installing… ${featuredProgress}%`
                : featuredLaunching
                ? (featuredLaunchStatus || 'Starting…')
                : isFeaturedInstalled
                ? '▶ Play Now'
                : '⬇ Install'}
            </button>
          </div>
        </div>
      </div>

      {/* System apps */}
      <div>
        <h2 className="text-base font-semibold text-white/70 mb-3">System Apps</h2>
        <div className="flex gap-1">
          {SYSTEM_APPS.map((app) => (
            <SystemAppTile key={app.id} packageId={app.packageId} name={app.name} />
          ))}
        </div>
      </div>

      {/* Popular games grid */}
      <div>
        <h2 className="text-base font-semibold text-white/70 mb-4">Popular Games</h2>
        <div className="grid grid-cols-3 gap-4">
          {GAMES.slice(1).map((game) => (
            <GameCard key={game.id} game={game} />
          ))}
        </div>
      </div>
    </div>
  )
}
