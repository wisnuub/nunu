import AppKit
import SwiftUI

/// One tile in nunu Home.
struct AppTile: Identifiable, Equatable {
    let id: String          // package name
    var title: String
    var subtitle: String = ""
    var icon: NSImage?
}

/// Installed games plus a "Popular games" shelf. Names and icons come from the
/// app's public Play Store page and are cached in ~/.nunu/library.
@MainActor
final class LibraryModel: ObservableObject {
    @Published var installed: [AppTile] = []
    @Published var featured: [AppTile] = []
    @Published var loading = false

    var onLaunch: ((String) -> Void)?
    var onStorePage: ((String) -> Void)?
    var onPlayStore: (() -> Void)?
    var onAndroidSettings: (() -> Void)?
    var onNunuSettings: (() -> Void)?
    var onEditControls: ((String) -> Void)?
    var onUninstall: ((String) -> Void)?
    var listApps: (() async -> [String])?

    /// Shown in Home's own row instead of "My games".
    private static let hidden: Set<String> = ["com.android.vending", "com.google.android.gms", "com.android.chrome"]

    func refresh() async {
        guard let listApps else { return }
        loading = true
        let packages = await listApps().filter { !Self.hidden.contains($0) }
        installed = packages.map { pkg in
            installed.first { $0.id == pkg } ?? AppTile(id: pkg, title: Self.fallbackTitle(pkg))
        }
        let installedSet = Set(packages)
        featured = FeaturedGame.all.filter { !installedSet.contains($0.id) }.map { g in
            featured.first { $0.id == g.id } ?? AppTile(id: g.id, title: g.name, subtitle: g.genre)
        }
        loading = false
        for pkg in packages + featured.map(\.id) {
            Task { await self.loadMetadata(pkg) }
        }
    }

    private func loadMetadata(_ pkg: String) async {
        guard let meta = await StoreMetadata.shared.fetch(pkg) else { return }
        if let i = installed.firstIndex(where: { $0.id == pkg }) {
            installed[i].title = meta.title ?? installed[i].title
            installed[i].icon = meta.icon
        }
        if let i = featured.firstIndex(where: { $0.id == pkg }) {
            featured[i].icon = meta.icon
        }
    }

    /// "com.supercell.clashroyale" -> "Clashroyale"
    static func fallbackTitle(_ pkg: String) -> String {
        let last = pkg.split(separator: ".").last.map(String.init) ?? pkg
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

/// Play Store page scraping for title + icon, cached on disk.
actor StoreMetadata {
    static let shared = StoreMetadata()

    struct Meta {
        var title: String?
        var icon: NSImage?
    }

    private var memory: [String: Meta] = [:]
    private let dir = Paths.root.appendingPathComponent("library", isDirectory: true)

    func fetch(_ pkg: String) async -> Meta? {
        if let m = memory[pkg] { return m }
        Paths.ensure(dir)
        let iconFile = dir.appendingPathComponent("\(pkg).png")
        let titleFile = dir.appendingPathComponent("\(pkg).txt")
        if let image = NSImage(contentsOf: iconFile) {
            let m = Meta(title: try? String(contentsOf: titleFile, encoding: .utf8), icon: image)
            memory[pkg] = m
            return m
        }
        guard let url = URL(string: "https://play.google.com/store/apps/details?id=\(pkg)&hl=en") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        var meta = Meta()
        if var title = Self.metaContent("og:title", in: html) {
            title = title.replacingOccurrences(of: " - Apps on Google Play", with: "")
            meta.title = Self.unescape(title)
            try? meta.title?.write(to: titleFile, atomically: true, encoding: .utf8)
        }
        if let raw = Self.metaContent("og:image", in: html) {
            // Ask for a 256 px icon instead of the original size.
            let base = raw.components(separatedBy: "=").dropLast().joined(separator: "=")
            if let iconURL = URL(string: (base.isEmpty ? raw : base) + "=s256"),
               let (img, _) = try? await URLSession.shared.data(from: iconURL),
               let image = NSImage(data: img) {
                meta.icon = image
                try? img.write(to: iconFile)
            }
        }
        memory[pkg] = meta
        return meta
    }

    private static func metaContent(_ property: String, in html: String) -> String? {
        guard let r = html.range(of: "property=\"\(property)\" content=\"") else { return nil }
        let rest = html[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

// MARK: - View

struct HomeView: View {
    @ObservedObject var model: LibraryModel
    @State private var confirmUninstall: AppTile?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 18)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color(red: 0.07, green: 0.08, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    section("My games") {
                        if model.installed.isEmpty && !model.loading {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(model.installed) { tile in
                                    TileView(tile: tile) { model.onLaunch?(tile.id) }
                                        .contextMenu { menu(for: tile) }
                                }
                            }
                        }
                    }
                    if !model.featured.isEmpty {
                        section("Popular games") {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(model.featured) { tile in
                                    TileView(tile: tile, badge: "Get") { model.onStorePage?(tile.id) }
                                }
                            }
                        }
                    }
                }
                .padding(28)
            }
        }
        .alert(item: $confirmUninstall) { tile in
            Alert(title: Text("Uninstall \(tile.title)?"),
                  message: Text("Its data and saved controls on this Mac stay until you reinstall."),
                  primaryButton: .destructive(Text("Uninstall")) { model.onUninstall?(tile.id) },
                  secondaryButton: .cancel())
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("nunu").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            pill("Play Store", "bag.fill") { model.onPlayStore?() }
            pill("Android settings", "gearshape.fill") { model.onAndroidSettings?() }
            pill("nunu settings", "slider.horizontal.3") { model.onNunuSettings?() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No games yet. Sign in to the Play Store and install one, it will show up here.")
                .foregroundStyle(.white.opacity(0.7))
            Button("Open Play Store") { model.onPlayStore?() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            content()
        }
    }

    private func pill(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.1), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for tile: AppTile) -> some View {
        Button("Play") { model.onLaunch?(tile.id) }
        Button("Edit game controls") { model.onEditControls?(tile.id) }
        Button("Open in Play Store") { model.onStorePage?(tile.id) }
        Divider()
        Button("Uninstall…") { confirmUninstall = tile }
    }
}

private struct TileView: View {
    let tile: AppTile
    var badge: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if let icon = tile.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(tile.title.prefix(1)))
                            .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: hover ? 10 : 4, y: hover ? 6 : 2)
                .scaleEffect(hover ? 1.06 : 1)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge).font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                            .offset(x: 6, y: -6)
                    }
                }
                Text(tile.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 104)
                if !tile.subtitle.isEmpty {
                    Text(tile.subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
