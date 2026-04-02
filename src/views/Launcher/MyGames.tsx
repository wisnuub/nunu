import { useAppStore } from '../../store/appStore'
import { GAMES } from '../../data/games'
import { GameCard } from './GameCard'

export function MyGames() {
  const { installedGames } = useAppStore()

  const myGames = GAMES.filter((g) => installedGames.includes(g.id))

  if (myGames.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-80 gap-4 text-center">
        <div className="text-6xl opacity-30">🎮</div>
        <p className="text-white/40 text-lg font-medium">No games installed yet</p>
        <p className="text-white/25 text-sm">Head to Home to discover and install games.</p>
      </div>
    )
  }

  return (
    <div className="pt-4">
      <div className="grid grid-cols-3 gap-4">
        {myGames.map((game) => (
          <GameCard key={game.id} game={game} />
        ))}
      </div>
    </div>
  )
}
