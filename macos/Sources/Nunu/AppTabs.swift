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
    /// Frame-rate readout, empty when the counter is off.
    @Published var fps = ""
    /// Transient note, e.g. fingerprint setup progress.
    @Published var notice = ""

    var onHome: (() -> Void)?
    var onTitleBarDoubleClick: (() -> Void)?
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

    /// Something without a tab is in front (e.g. a sign-in screen we can't attribute).
    func showOther() { active = "" }

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
    /// Matches the system title bar so tabs line up with the traffic lights.
    let height: CGFloat
    /// Room for the traffic-light buttons.
    var leadingInset: CGFloat = 80

    /// Height of a standard title bar on this macOS version.
    static var titleBarHeight: CGFloat {
        let content = NSRect(x: 0, y: 0, width: 200, height: 200)
        let frame = NSWindow.frameRect(forContentRect: content, styleMask: [.titled])
        return max(28, frame.height - content.height)
    }

    var body: some View {
        HStack(spacing: 4) {
            dragArea.frame(width: leadingInset)
            TabButton(title: "Home", symbol: "house.fill", icon: nil, active: model.active == nil,
                      height: height - 6, onSelect: { model.onHome?() }, onClose: nil)
            ForEach(model.tabs) { tab in
                TabButton(title: tab.title, symbol: tab.symbol, icon: tab.icon, active: model.active == tab.id,
                          height: height - 6, onSelect: { model.onSelect?(tab.id) }, onClose: { model.close([tab.id]) })
                    .contextMenu {
                        Button("Close \(tab.title)") { model.close([tab.id]) }
                        Button("Close Other Apps") { model.close(model.tabs.map(\.id).filter { $0 != tab.id }) }
                        Button("Close All Apps") { model.close(model.tabs.map(\.id)) }
                    }
            }
            dragArea
            if !model.notice.isEmpty {
                Label(model.notice, systemImage: "touchid")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                    .padding(.trailing, 8)
            }
            if !model.fps.isEmpty {
                Text(model.fps)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(.trailing, 12)
            }
        }
        .frame(height: height)
        .background(Color(white: 0.105))
        // The strip *is* the title bar; without this SwiftUI pushes it below it.
        .ignoresSafeArea()
    }

    /// Empty title-bar space behaves like a title bar: drag moves the window,
    /// double-click zooms/minimises per the system setting.
    private var dragArea: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.onTitleBarDoubleClick?() })
    }
}

private struct TabButton: View {
    let title: String
    let symbol: String?
    let icon: NSImage?
    let active: Bool
    let height: CGFloat
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
            .frame(width: 16, height: 16)
            Text(title).font(.system(size: 12, weight: active ? .semibold : .regular)).lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
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
        .frame(height: height)
        .background(active ? Color.white.opacity(0.14) : hover ? Color.white.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
    }
}
