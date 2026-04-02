import { GAMES } from '../../data/games'
import { GameCard } from './GameCard'

const CATEGORIES = ['All', 'Battle Royale', 'RPG', 'Strategy', 'MOBA', 'FPS']

export function Discover() {
  return (
    <div className="flex flex-col gap-6 pt-4">
      {/* Category filter pills */}
      <div className="flex gap-2 flex-wrap">
        {CATEGORIES.map((cat, i) => (
          <button
            key={cat}
            className={`px-4 py-1.5 rounded-full text-sm font-medium transition-all focus:outline-none ${
              i === 0
                ? 'text-white'
                : 'text-white/40 hover:text-white/70 bg-white/5 hover:bg-white/10'
            }`}
            style={
              i === 0
                ? { background: 'linear-gradient(135deg, #5B6EF5, #8B5CF6)' }
                : {}
            }
          >
            {cat}
          </button>
        ))}
      </div>

      {/* All games grid */}
      <div className="grid grid-cols-3 gap-4">
        {GAMES.map((game) => (
          <GameCard key={game.id} game={game} />
        ))}
      </div>
    </div>
  )
}
