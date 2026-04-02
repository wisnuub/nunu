import SwiftUI

struct Game: Identifiable {
    let id: String
    let name: String
    let genre: String
    let size: String
    let description: String
    let gradientStart: Color
    let gradientEnd: Color
    let sfSymbol: String
}

extension Game {
    static let catalog: [Game] = [
        Game(
            id: "com.tencent.ig",
            name: "PUBG Mobile",
            genre: "Action",
            size: "740 MB",
            description: "Battle royale survival shooter. Land, loot, and survive against 100 players on a shrinking map.",
            gradientStart: Color(hex: "#6B21A8"),
            gradientEnd: Color(hex: "#EA580C"),
            sfSymbol: "scope"
        ),
        Game(
            id: "com.miHoYo.GenshinImpact",
            name: "Genshin Impact",
            genre: "RPG",
            size: "2.1 GB",
            description: "Open-world action RPG. Explore Teyvat, a vast world teeming with life and elemental powers.",
            gradientStart: Color(hex: "#1D4ED8"),
            gradientEnd: Color(hex: "#0D9488"),
            sfSymbol: "sparkles"
        ),
        Game(
            id: "com.riotgames.league.teamfighttactics",
            name: "Teamfight Tactics",
            genre: "Strategy",
            size: "320 MB",
            description: "Auto battler strategy game. Draft, position, and battle to be the last one standing.",
            gradientStart: Color(hex: "#92400E"),
            gradientEnd: Color(hex: "#1C1917"),
            sfSymbol: "checkerboard.rectangle"
        ),
        Game(
            id: "com.mobile.legends",
            name: "Mobile Legends",
            genre: "MOBA",
            size: "1.2 GB",
            description: "5v5 MOBA on mobile. Choose your hero, destroy the enemy base, and claim victory.",
            gradientStart: Color(hex: "#991B1B"),
            gradientEnd: Color(hex: "#0C0A09"),
            sfSymbol: "shield.lefthalf.filled"
        ),
        Game(
            id: "com.activision.callofduty.shooter",
            name: "Call of Duty Mobile",
            genre: "Shooter",
            size: "2.4 GB",
            description: "AAA shooter on mobile. Battle Royale, multiplayer modes, and iconic maps await.",
            gradientStart: Color(hex: "#14532D"),
            gradientEnd: Color(hex: "#0C0A09"),
            sfSymbol: "target"
        ),
        Game(
            id: "com.HoYoverse.hkrpgoversea",
            name: "Honkai: Star Rail",
            genre: "RPG",
            size: "1.8 GB",
            description: "Turn-based space fantasy RPG. Board the Astral Express and explore the galaxy.",
            gradientStart: Color(hex: "#581C87"),
            gradientEnd: Color(hex: "#DB2777"),
            sfSymbol: "star.circle.fill"
        )
    ]
}
