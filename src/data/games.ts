export interface Game {
  id: string
  name: string
  genre: string
  size: string
  description: string
  gradientFrom: string
  gradientTo: string
  icon: string
}

export const GAMES: Game[] = [
  {
    id: 'pubg-mobile',
    name: 'PUBG Mobile',
    genre: 'Battle Royale',
    size: '2.4 GB',
    description:
      'Drop into intense 100-player battles across massive maps. Loot, survive, and be the last one standing.',
    gradientFrom: '#1a3a2a',
    gradientTo: '#2d6a4f',
    icon: '🎯',
  },
  {
    id: 'genshin-impact',
    name: 'Genshin Impact',
    genre: 'Action RPG',
    size: '18.3 GB',
    description:
      'Explore the magical world of Teyvat with a diverse cast of characters and an epic open world.',
    gradientFrom: '#1a1a3a',
    gradientTo: '#3d2b6d',
    icon: '⚔️',
  },
  {
    id: 'teamfight-tactics',
    name: 'Teamfight Tactics',
    genre: 'Strategy',
    size: '1.1 GB',
    description:
      'Build and battle with powerful champion combinations in this auto-battler strategy game.',
    gradientFrom: '#1a2a3a',
    gradientTo: '#1e4d8c',
    icon: '♟️',
  },
  {
    id: 'mobile-legends',
    name: 'Mobile Legends',
    genre: 'MOBA',
    size: '1.8 GB',
    description:
      'Join 5v5 MOBA battles with over 100 heroes. Destroy the enemy base to claim victory.',
    gradientFrom: '#2a1a1a',
    gradientTo: '#6d1f1f',
    icon: '🏆',
  },
  {
    id: 'cod-mobile',
    name: 'Call of Duty: Mobile',
    genre: 'FPS',
    size: '3.2 GB',
    description:
      'Experience iconic multiplayer maps and modes from the Call of Duty franchise on your desktop.',
    gradientFrom: '#1a1a1a',
    gradientTo: '#2d3a1a',
    icon: '🔫',
  },
  {
    id: 'honkai-star-rail',
    name: 'Honkai: Star Rail',
    genre: 'Turn-Based RPG',
    size: '14.7 GB',
    description:
      'Board the Astral Express and explore a universe full of wonders, mystery, and diverse civilizations.',
    gradientFrom: '#1a1a2a',
    gradientTo: '#2a1a3d',
    icon: '🌟',
  },
]
