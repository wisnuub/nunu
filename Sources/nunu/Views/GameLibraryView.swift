import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var installService = InstallationService.shared

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let featured = Game.catalog.first {
                    FeaturedCard(game: featured)
                        .padding(.bottom, 32)
                }

                Text("Popular Games")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 16)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Game.catalog) { game in
                        GameCardView(
                            game: game,
                            isInstalled: appState.installedGames.contains(game.id),
                            installProgress: installService.installProgress[game.id]
                        ) {
                            appState.installGame(game.id)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Featured Card

private struct FeaturedCard: View {
    let game: Game
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [game.gradientStart, game.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.03))
                        .frame(width: CGFloat(80 + i * 40))
                        .offset(x: CGFloat(i * 30 - 60), y: CGFloat(-i * 20))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            Image(systemName: game.sfSymbol)
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.08))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 20)
                .padding(.trailing, 40)

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("FEATURED")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())

                Text(game.name)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text(game.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    GenreTag(genre: game.genre)
                    Text(game.size)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Spacer()
                    InstallButton(isInstalled: appState.installedGames.contains(game.id), isFeatured: true) {
                        appState.installGame(game.id)
                    }
                }
            }
            .padding(28)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(isHovering ? 0.15 : 0.06), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.005 : 1.0)
        .shadow(color: game.gradientStart.opacity(0.3), radius: isHovering ? 24 : 16, x: 0, y: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Game Card View

struct GameCardView: View {
    let game: Game
    let isInstalled: Bool
    let installProgress: Double?
    let onInstall: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [game.gradientStart, game.gradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 120)
                        .offset(x: 40, y: -20)
                    Image(systemName: game.sfSymbol)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .frame(height: 140)

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        GenreTag(genre: game.genre)
                        Text(game.size)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }

                    Spacer().frame(height: 4)

                    InstallButton(isInstalled: isInstalled, isFeatured: false, onAction: onInstall)
                        .frame(maxWidth: .infinity)
                }
                .padding(14)
                .background(Color(hex: "#141720"))
            }

            if let progress = installProgress, progress < 1.0 {
                ZStack {
                    Color.black.opacity(0.65)
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.9)
                            .tint(Color(hex: "#5B6EF5"))

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15)).frame(height: 3)
                                Capsule().fill(Color(hex: "#5B6EF5")).frame(width: geo.size.width * progress, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(isHovering ? 0.12 : 0.05), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .shadow(color: game.gradientStart.opacity(isHovering ? 0.25 : 0.1), radius: isHovering ? 16 : 6, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Shared Components

struct GenreTag: View {
    let genre: String

    var body: some View {
        Text(genre)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(hex: "#8B5CF6"))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: "#8B5CF6").opacity(0.12))
            .clipShape(Capsule())
    }
}

struct InstallButton: View {
    let isInstalled: Bool
    let isFeatured: Bool
    var onAction: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 6) {
                Image(systemName: isInstalled ? "play.fill" : "arrow.down.circle.fill")
                    .font(.system(size: isFeatured ? 15 : 13, weight: .medium))
                Text(isInstalled ? "Play" : "Install")
                    .font(.system(size: isFeatured ? 16 : 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isFeatured ? 24 : 0)
            .padding(.vertical, isFeatured ? 12 : 8)
            .frame(maxWidth: isFeatured ? nil : .infinity)
            .background(
                Group {
                    if isInstalled {
                        Color(hex: "#16A34A")
                            .clipShape(RoundedRectangle(cornerRadius: isFeatured ? 12 : 8))
                    } else {
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: isFeatured ? 12 : 8))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: isFeatured ? 12 : 8))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
