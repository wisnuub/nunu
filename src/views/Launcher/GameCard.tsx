import { useState, useEffect, useRef } from 'react'
import { useAppStore } from '../../store/appStore'
import type { Game } from '../../data/games'

interface GameCardProps {
  game: Game
}

export function GameCard({ game }: GameCardProps) {
  const { installedGames, installProgress, setInstallProgress, addInstalledGame, removeInstalledGame, vmStatus, launchingPackageId, setVmStatus } = useAppStore()

  const isInstalled = installedGames.includes(game.id)
  const progress = installProgress[game.id] ?? 0
  const isInstalling = progress > 0 && progress < 100

  const isThisGameLaunching = launchingPackageId === game.packageId &&
    (vmStatus === 'booting' || vmStatus === 'ready')
  const launchStatusText = isThisGameLaunching
    ? (vmStatus === 'booting' ? 'Booting…' : '')
    : ''

  const [artUrl, setArtUrl] = useState<string | null>(null)
  const [bannerUrl, setBannerUrl] = useState<string | null>(null)
  const [menuOpen, setMenuOpen] = useState(false)
  const [launchError, setLaunchError] = useState('')
  const [restartPrompt, setRestartPrompt] = useState<{ runningGameName: string } | null>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    window.nunu?.fetchGameArt?.(game.packageId).then((url) => { if (url) setArtUrl(url) })
    window.nunu?.fetchGameBanner?.(game.packageId).then((url) => { if (url) setBannerUrl(url) })
  }, [game.packageId])

  // Close menu on outside click
  useEffect(() => {
    if (!menuOpen) return
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [menuOpen])

  const doLaunch = async (forceRestart?: boolean) => {
    setLaunchError('')
    setVmStatus('booting', game.packageId)
    const result = await window.nunu?.launchGame?.(
      game.packageId,
      game.name,
      game.defaultConfig,
      forceRestart,
    )
    if (result?.needsRestart) {
      setVmStatus('idle', null)
      setRestartPrompt({ runningGameName: result.runningGameName ?? 'another game' })
      return
    }
    if (result && !result.success && !result.alreadyRunning) {
      setVmStatus('idle', null)
      setLaunchError(result.error ?? 'Failed to launch')
      setTimeout(() => setLaunchError(''), 6000)
    }
  }

  const handleRestartConfirm = async () => {
    setRestartPrompt(null)
    await doLaunch(true)
  }

  const handleAction = async () => {
    if (isInstalled) {
      await doLaunch()
      return
    }
    if (isInstalling) return

    setInstallProgress(game.id, 1)

    if (window.nunu?.installGame) {
      const unsub = window.nunu.onInstallProgress((evt) => {
        if (evt.phase === 'game') {
          setInstallProgress(game.id, evt.percent)
          if (evt.percent >= 100) {
            addInstalledGame(game.id)
            unsub()
          }
        }
      })
      await window.nunu.installGame(game.id).catch(() => {
        setInstallProgress(game.id, 0)
        unsub()
      })
    } else {
      for (let i = 1; i <= 100; i += 5) {
        await new Promise<void>((r) => setTimeout(r, 100))
        setInstallProgress(game.id, i)
      }
      addInstalledGame(game.id)
    }
  }

  return (
    <>
    {restartPrompt && (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
        <div className="bg-[#1a1d2a] border border-white/10 rounded-[16px] shadow-2xl p-6 w-[340px] mx-4">
          <p className="text-white/50 text-xs font-medium uppercase tracking-wider mb-1">One game at a time</p>
          <h3 className="text-white text-base font-semibold mb-1">
            {restartPrompt.runningGameName} is running
          </h3>
          <p className="text-white/60 text-sm mb-1">
            Restart for <span className="text-white font-medium">{game.name}</span>?
          </p>
          <p className="text-white/35 text-xs mb-5">
            {(game.defaultConfig.memoryMb / 1024).toFixed(0)} GB RAM &middot; {game.defaultConfig.cores} cores
          </p>
          <div className="flex gap-2">
            <button
              onClick={() => setRestartPrompt(null)}
              className="flex-1 py-2 rounded-[8px] text-sm font-medium text-white/60 bg-white/5 hover:bg-white/10 transition-colors focus:outline-none"
            >
              Cancel
            </button>
            <button
              onClick={handleRestartConfirm}
              className="flex-1 py-2 rounded-[8px] text-sm font-semibold text-white transition-colors focus:outline-none"
              style={{ background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }}
            >
              Restart &amp; Play
            </button>
          </div>
        </div>
      </div>
    )}
    <div className="rounded-[12px] overflow-hidden border border-white/5 bg-[#141720] hover:border-white/10 transition-all duration-200 hover:scale-[1.01] cursor-pointer group">
      {/* Art area — banner as background, icon on top */}
      <div
        className="relative h-36 flex items-end justify-start overflow-hidden"
        style={
          bannerUrl
            ? { backgroundImage: `url(${bannerUrl})`, backgroundSize: 'cover', backgroundPosition: 'center' }
            : { background: `linear-gradient(135deg, ${game.gradientFrom}, ${game.gradientTo})` }
        }
      >
        {/* Dark scrim so the bottom info area is readable */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent" />

        {/* App icon bottom-left */}
        <div className="relative z-10 p-3">
          {artUrl ? (
            <img src={artUrl} alt={game.name} className="w-12 h-12 rounded-xl object-cover shadow-lg border border-white/10" />
          ) : (
            <div
              className="w-12 h-12 rounded-xl flex items-center justify-center font-black text-base text-white/90 select-none border border-white/10"
              style={{ background: 'rgba(0,0,0,0.4)', backdropFilter: 'blur(6px)' }}
            >
              {game.abbr.slice(0, 2)}
            </div>
          )}
        </div>

        {/* Installing overlay */}
        {isInstalling && (
          <div className="absolute inset-0 bg-black/60 flex flex-col items-center justify-center gap-2 px-4">
            <div className="w-full h-1.5 bg-white/20 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-200"
                style={{ width: `${progress}%`, background: 'linear-gradient(90deg, #5B6EF5, #8B5CF6)' }}
              />
            </div>
            <span className="text-white text-xs font-medium">{progress}%</span>
          </div>
        )}
      </div>

      {/* Info */}
      <div className="p-4">
        <div className="flex items-start justify-between gap-2 mb-2">
          <span className="text-white text-sm font-semibold leading-tight">{game.name}</span>
          <span className="text-white/30 text-xs shrink-0">{game.size}</span>
        </div>

        {launchError && (
          <p className="text-red-400 text-xs mb-2 leading-tight">{launchError}</p>
        )}
        {launchStatusText && !launchError && (
          <p className="text-white/50 text-xs mb-2 leading-tight flex items-center gap-1.5">
            <span className="inline-block w-2.5 h-2.5 rounded-full border border-white/30 border-t-white/80 animate-spin" />
            {launchStatusText}
          </p>
        )}

        <div className="flex items-center justify-between">
          <span className="text-xs px-2 py-0.5 rounded-full bg-white/5 text-white/40 font-medium">
            {game.genre}
          </span>

          <div className="flex items-center gap-1.5">
            <button
              onClick={handleAction}
              disabled={isInstalling || isThisGameLaunching}
              className="px-3 py-1.5 rounded-[6px] text-xs font-semibold transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
              style={
                isInstalled
                  ? { background: '#16A34A', color: '#fff' }
                  : { background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)', color: '#fff' }
              }
            >
              {isInstalling ? 'Installing…' : isThisGameLaunching ? (launchStatusText || 'Starting…') : isInstalled ? 'Play' : 'Install'}
            </button>

            {isInstalled && (
              <div className="relative" ref={menuRef}>
                <button
                  onClick={() => setMenuOpen((v) => !v)}
                  className="w-7 h-7 rounded-[6px] flex items-center justify-center text-white/40 hover:text-white/80 hover:bg-white/5 transition-colors focus:outline-none text-lg leading-none"
                >
                  ⋮
                </button>
                {menuOpen && (
                  <div className="absolute right-0 bottom-full mb-1 bg-[#1e2232] border border-white/10 rounded-[8px] shadow-2xl z-20 min-w-[148px] overflow-hidden">
                    {[
                      { label: 'Clear cache', action: () => { setMenuOpen(false) } },
                      { label: 'Clear data', action: () => { setMenuOpen(false) } },
                      { label: 'Uninstall', action: () => { removeInstalledGame(game.id); setMenuOpen(false) }, danger: true },
                    ].map((item) => (
                      <button
                        key={item.label}
                        onClick={item.action}
                        className={`w-full text-left px-4 py-2.5 text-sm transition-colors hover:bg-white/5 focus:outline-none ${
                          item.danger ? 'text-red-400' : 'text-white/70'
                        }`}
                      >
                        {item.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
    </>
  )
}
