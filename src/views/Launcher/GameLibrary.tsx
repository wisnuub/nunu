import { useState, useEffect } from 'react'
import { useAppStore } from '../../store/appStore'
import { GAMES, SYSTEM_APPS } from '../../data/games'
import { GameCard } from './GameCard'

function SystemAppTile({ packageId, name }: { packageId: string; name: string }) {
  const [artUrl, setArtUrl] = useState<string | null>(null)
  const [launchError, setLaunchError] = useState('')

  useEffect(() => {
    window.nunu?.fetchGameArt?.(packageId).then((url) => {
      if (url) setArtUrl(url)
    })
  }, [packageId])

  const handleLaunch = async () => {
    const result = await window.nunu?.launchGame?.(packageId)
    if (result && !result.success && !result.alreadyRunning) {
      setLaunchError(result.error ?? 'Failed to launch')
      setTimeout(() => setLaunchError(''), 3000)
    }
  }

  return (
    <button
      onClick={handleLaunch}
      className="flex flex-col items-center gap-2 p-3 rounded-[10px] hover:bg-white/5 transition-colors focus:outline-none group"
      title={launchError || name}
    >
      <div
        className="w-14 h-14 rounded-2xl flex items-center justify-center overflow-hidden"
        style={{ background: 'linear-gradient(135deg, #1e2232, #2a2f45)' }}
      >
        {artUrl ? (
          <img src={artUrl} alt={name} className="w-full h-full object-cover rounded-2xl" />
        ) : (
          <span className="text-white/30 text-xs font-bold">{name[0]}</span>
        )}
      </div>
      <span className="text-white/50 text-xs font-medium group-hover:text-white/80 transition-colors">{name}</span>
    </button>
  )
}

export function GameLibrary() {
  const { installedGames, setInstallProgress, addInstalledGame } = useAppStore()

  const featured = GAMES[0]
  const isFeaturedInstalled = installedGames.includes(featured.id)
  const featuredProgress = useAppStore((s) => s.installProgress[featured.id] ?? 0)
  const isFeaturedInstalling = featuredProgress > 0 && featuredProgress < 100

  const [featuredArt, setFeaturedArt] = useState<string | null>(null)
  const [featuredLaunchError, setFeaturedLaunchError] = useState('')

  useEffect(() => {
    window.nunu?.fetchGameArt?.(featured.packageId).then((url) => {
      if (url) setFeaturedArt(url)
    })
  }, [featured.packageId])

  const handleFeaturedAction = async () => {
    if (isFeaturedInstalled) {
      const result = await window.nunu?.launchGame?.(featured.packageId)
      if (result && !result.success && !result.alreadyRunning) {
        setFeaturedLaunchError(result.error ?? 'Failed to launch')
        setTimeout(() => setFeaturedLaunchError(''), 4000)
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
        style={{
          height: 280,
          background: `linear-gradient(135deg, ${featured.gradientFrom}, ${featured.gradientTo})`,
        }}
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
              </div>
            </div>

            <button
              onClick={handleFeaturedAction}
              disabled={isFeaturedInstalling}
              className="px-8 py-3 rounded-[8px] text-white font-semibold text-sm transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none disabled:opacity-50 shrink-0"
              style={
                isFeaturedInstalled
                  ? { background: '#16A34A' }
                  : { background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }
              }
            >
              {isFeaturedInstalling
                ? `Installing… ${featuredProgress}%`
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
