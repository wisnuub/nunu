import AppKit
import SwiftUI

/// Packages whose activities pop up over an app for a moment (permission
/// prompts, Google sign-in, share sheets). They never get a tab or steal
/// the game's controls.
let transientPackages: Set<String> = [
    "android",
    "com.android.systemui",
    "com.android.intentresolver",
    "com.android.permissioncontroller",
    "com.google.android.permissioncontroller",
    "com.android.packageinstaller",
    "com.google.android.packageinstaller",
    "com.google.android.gms",
    "com.google.android.gsf",
    "com.google.android.inputmethod.latin",
]

struct AppTab: Identifiable, Equatable {
    let id: String          // package name
    var title: String
    var icon: NSImage?
    var symbol: String?

    init(_ pkg: String) {
        id = pkg
        title = systemAppInfo[pkg]?.name ?? LibraryModel.fallbackTitle(pkg)
        symbol = systemAppInfo[pkg]?.symbol
    }
}

/// Open apps shown as tabs in the title bar, BlueStacks/MuMu style.
@MainActor
final class TabsModel: ObservableObject {
    @Published var tabs: [AppTab] = []
    /// nil means the Home tab.
    @Published var active: String?
    /// Right-aligned hint, e.g. while mouse-look holds the cursor.
    @Published var status = ""

    var onHome: (() -> Void)?
    var onSelect: ((String) -> Void)?
    var onClose: (([String]) -> Void)?

    func activate(_ pkg: String) {
        if !tabs.contains(where: { $0.id == pkg }) {
            tabs.append(AppTab(pkg))
            loadMetadata(pkg)
        }
        active = pkg
    }

    func showHome() { active = nil }

    /// Seed tabs from Android's running tasks (after a launch or re-attach).
    func sync(running: [String]) {
        for pkg in running where !tabs.contains(where: { $0.id == pkg }) {
            tabs.append(AppTab(pkg))
            loadMetadata(pkg)
        }
    }

    func close(_ pkgs: [String]) {
        guard !pkgs.isEmpty else { return }
        tabs.removeAll { pkgs.contains($0.id) }
        if let a = active, pkgs.contains(a) { active = nil }
        onClose?(pkgs)
    }

    func closeActive() {
        if let a = active { close([a]) }
    }

    /// ⌃Tab / ⌃⇧Tab: Home, then each app tab, wrapping around.
    func cycle(by step: Int) {
        let order: [String?] = [nil] + tabs.map(\.id)
        let i = order.firstIndex(of: active) ?? 0
        let next = order[(i + step + order.count) % order.count]
        if let next { onSelect?(next) } else { onHome?() }
    }

    private func loadMetadata(_ pkg: String) {
        guard systemAppInfo[pkg] == nil else { return }
        Task {
            guard let meta = await StoreMetadata.shared.fetch(pkg),
                  let i = tabs.firstIndex(where: { $0.id == pkg }) else { return }
            if let title = meta.title { tabs[i].title = title }
            tabs[i].icon = meta.icon
        }
    }
}

struct TabStripView: View {
    @ObservedObject var model: TabsModel
    /// Room for the traffic-light buttons.
    var leadingInset: CGFloat = 78

    static let height: CGFloat = 38

    var body: some View {
        HStack(spacing: 4) {
            dragArea.frame(width: leadingInset)
            TabButton(title: "Home", symbol: "house.fill", icon: nil, active: model.active == nil,
                      onSelect: { model.onHome?() }, onClose: nil)
            ForEach(model.tabs) { tab in
                TabButton(title: tab.title, symbol: tab.symbol, icon: tab.icon, active: model.active == tab.id,
                          onSelect: { model.onSelect?(tab.id) }, onClose: { model.close([tab.id]) })
                    .contextMenu {
                        Button("Close \(tab.title)") { model.close([tab.id]) }
                        Button("Close Other Apps") { model.close(model.tabs.map(\.id).filter { $0 != tab.id }) }
                        Button("Close All Apps") { model.close(model.tabs.map(\.id)) }
                    }
            }
            dragArea
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: Self.height)
        .background(Color(white: 0.105))
    }

    /// Empty title-bar space still moves the window.
    private var dragArea: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }
}

private struct TabButton: View {
    let title: String
    let symbol: String?
    let icon: NSImage?
    let active: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: symbol ?? "app.fill").font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 18, height: 18)
            Text(title).font(.system(size: 12, weight: active ? .semibold : .regular)).lineLimit(1)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(hover ? Color.white.opacity(0.12) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(hover || active ? 1 : 0)
                .help("Close \(title)")
            }
        }
        .foregroundStyle(.white.opacity(active ? 1 : 0.7))
        .padding(.leading, 10).padding(.trailing, onClose == nil ? 12 : 6)
        .frame(height: 28)
        .frame(maxWidth: 210)
        .background(active ? Color.white.opacity(0.14) : hover ? Color.white.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
    }
}
