import SwiftUI

struct MainLauncherView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SidebarTab = .home

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedTab: $selectedTab)

            Divider()
                .background(Color.white.opacity(0.05))

            ZStack {
                Color(hex: "#0D0F14").ignoresSafeArea()
                contentView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1280, minHeight: 800)
        .background(Color(hex: "#0D0F14"))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .home:
            GameLibraryView().id("home")
        case .games:
            InstalledGamesView().id("games")
        case .discover:
            DiscoverView().id("discover")
        case .settings:
            SettingsView().id("settings")
        }
    }
}

// MARK: - Installed Games

private struct InstalledGamesView: View {
    @EnvironmentObject var appState: AppState

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var installedGames: [Game] {
        Game.catalog.filter { appState.installedGames.contains($0.id) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "My Games", subtitle: "\(installedGames.count) installed")

                if installedGames.isEmpty {
                    EmptyStateView(
                        icon: "gamecontroller",
                        title: "No games installed",
                        message: "Visit the Home tab to install games"
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(installedGames) { game in
                            GameCardView(game: game, isInstalled: true, installProgress: nil) {}
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Discover

private struct DiscoverView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Discover", subtitle: "New releases and top picks")
                EmptyStateView(icon: "safari", title: "Coming soon", message: "Browse and discover new Android games")
            }
            .padding(24)
        }
    }
}

// MARK: - Shared Components

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.white.opacity(0.15))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}
