import { useAppStore } from '../../store/appStore'
import type { Game } from '../../data/games'

interface GameCardProps {
  game: Game
}

export function GameCard({ game }: GameCardProps) {
  const { installedGames, installProgress, setInstallProgress, addInstalledGame } = useAppStore()

  const isInstalled = installedGames.includes(game.id)
  const progress = installProgress[game.id] ?? 0
  const isInstalling = progress > 0 && progress < 100

  const handleAction = async () => {
    if (isInstalled) {
      await window.nunu?.launchGame?.(game.packageId)
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
      // Demo mode
      for (let i = 1; i <= 100; i += 5) {
        await new Promise<void>((r) => setTimeout(r, 100))
        setInstallProgress(game.id, i)
      }
      addInstalledGame(game.id)
    }
  }

  return (
    <div
      className="rounded-[12px] overflow-hidden border border-white/5 bg-[#141720] hover:border-white/10 transition-all duration-200 hover:scale-[1.01] cursor-pointer group"
    >
      {/* Art area */}
      <div
        className="relative h-36 flex items-center justify-center"
        style={{
          background: `linear-gradient(135deg, ${game.gradientFrom}, ${game.gradientTo})`,
        }}
      >
        <div
          className="px-4 py-2 rounded-xl font-black text-2xl tracking-widest text-white/90 select-none"
          style={{ background: 'rgba(0,0,0,0.25)', backdropFilter: 'blur(6px)' }}
        >
          {game.abbr}
        </div>

        {/* Installing overlay */}
        {isInstalling && (
          <div className="absolute inset-0 bg-black/60 flex flex-col items-center justify-center gap-2 px-4">
            <div className="w-full h-1.5 bg-white/20 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-200"
                style={{
                  width: `${progress}%`,
                  background: 'linear-gradient(90deg, #5B6EF5, #8B5CF6)',
                }}
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

        <div className="flex items-center justify-between">
          <span className="text-xs px-2 py-0.5 rounded-full bg-white/5 text-white/40 font-medium">
            {game.genre}
          </span>

          <button
            onClick={handleAction}
            disabled={isInstalling}
            className="px-3 py-1.5 rounded-[6px] text-xs font-semibold transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
            style={
              isInstalled
                ? { background: '#16A34A', color: '#fff' }
                : { background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)', color: '#fff' }
            }
          >
            {isInstalling ? 'Installing…' : isInstalled ? 'Play' : 'Install'}
          </button>
        </div>
      </div>
    </div>
  )
}
