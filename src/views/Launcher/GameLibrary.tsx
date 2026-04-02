import { useAppStore } from '../../store/appStore'
import { GAMES } from '../../data/games'
import { GameCard } from './GameCard'

export function GameLibrary() {
  const { installedGames, setInstallProgress, addInstalledGame } = useAppStore()

  const featured = GAMES[0]
  const isFeaturedInstalled = installedGames.includes(featured.id)
  const featuredProgress = useAppStore((s) => s.installProgress[featured.id] ?? 0)
  const isFeaturedInstalling = featuredProgress > 0 && featuredProgress < 100

  const handleFeaturedAction = async () => {
    if (isFeaturedInstalled || isFeaturedInstalling) return

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
      // Demo
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
        <div className="absolute inset-0 opacity-20">
          <div className="absolute bottom-0 right-0 text-[200px] leading-none select-none">{featured.icon}</div>
        </div>

        {/* Content */}
        <div className="absolute inset-0 flex flex-col justify-end p-8 bg-gradient-to-t from-black/60 to-transparent">
          <div className="flex items-end justify-between">
            <div>
              <div className="flex items-center gap-3 mb-3">
                <span className="px-3 py-1 rounded-full bg-white/20 text-white/90 text-xs font-medium">
                  {featured.genre}
                </span>
                <span className="text-white/50 text-xs">{featured.size}</span>
              </div>
              <h2 className="text-4xl font-bold text-white mb-2">{featured.name}</h2>
              <p className="text-white/60 text-sm max-w-md">{featured.description}</p>
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
