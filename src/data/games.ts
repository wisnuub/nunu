export interface SystemApp {
  id: string
  name: string
  packageId: string
}

export const SYSTEM_APPS: SystemApp[] = [
  { id: 'play-store', name: 'Play Store', packageId: 'com.android.vending' },
  { id: 'settings', name: 'Settings', packageId: 'com.android.settings' },
  { id: 'chrome', name: 'Chrome', packageId: 'com.android.chrome' },
  { id: 'google', name: 'Google', packageId: 'com.google.android.googlequicksearchbox' },
]

export interface GameConfig {
  memoryMb: number
  cores: number
}

export interface Game {
  id: string
  name: string
  genre: string
  size: string
  description: string
  gradientFrom: string
  gradientTo: string
  abbr: string
  packageId: string
  defaultConfig: GameConfig
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
    abbr: 'PUBG',
    packageId: 'com.tencent.ig',
    defaultConfig: { memoryMb: 6144, cores: 4 },
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
    abbr: 'GI',
    packageId: 'com.miHoYo.GenshinImpact',
    defaultConfig: { memoryMb: 8192, cores: 6 },
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
    abbr: 'TFT',
    packageId: 'com.riotgames.league.teamfighttactics',
    defaultConfig: { memoryMb: 4096, cores: 4 },
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
    abbr: 'ML',
    packageId: 'com.mobile.legends',
    defaultConfig: { memoryMb: 4096, cores: 4 },
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
    abbr: 'CoD',
    packageId: 'com.activision.callofduty.shooter',
    defaultConfig: { memoryMb: 6144, cores: 4 },
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
    abbr: 'HSR',
    packageId: 'com.HoYoverse.hkrpgoversea',
    defaultConfig: { memoryMb: 6144, cores: 4 },
  },
]
