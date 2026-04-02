import SwiftUI

enum SidebarTab: String, CaseIterable {
    case home = "Home"
    case games = "My Games"
    case discover = "Discover"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .games: return "gamecontroller.fill"
        case .discover: return "safari.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false

    private let collapsedWidth: CGFloat = 72
    private let expandedWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(hex: "#0A0C10"))
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 1),
                    alignment: .trailing
                )

            VStack(alignment: .leading, spacing: 4) {
                // Logo
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: "android")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36)
                    .overlay(alignment: .topTrailing) {
                        if appState.isUpdateAvailable {
                            Circle()
                                .fill(Color(hex: "#F59E0B"))
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }

                    if isExpanded {
                        Text("nunu")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 28)

                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    SidebarTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        isExpanded: isExpanded,
                        badge: tab == .settings && appState.isUpdateAvailable ? "1" : nil
                    ) {
                        selectedTab = tab
                    }
                }

                Spacer()

                if isExpanded {
                    Text("v1.0.0")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded = hovering
            }
        }
    }
}

private struct SidebarTabButton: View {
    let tab: SidebarTab
    let isSelected: Bool
    let isExpanded: Bool
    let badge: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? Color(hex: "#5B6EF5") : Color.white.opacity(isHovering ? 0.8 : 0.45))
                        .frame(width: 36, height: 36)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Color(hex: "#F59E0B"))
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }

                if isExpanded {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.6))
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color(hex: "#5B6EF5").opacity(0.12)
                          : (isHovering ? Color.white.opacity(0.04) : Color.clear))
                    .padding(.horizontal, 8)
            )
            .overlay(
                isSelected
                ? RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#5B6EF5"))
                    .frame(width: 3, height: 28)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                : nil
            )
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
