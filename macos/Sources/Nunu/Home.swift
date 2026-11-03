import AppKit
import SwiftUI

/// One tile in nunu Home.
struct AppTile: Identifiable, Equatable {
    let id: String          // package name
    var title: String
    var subtitle: String = ""
    var icon: NSImage?
    var symbol: String?     // system apps without a store icon
    var progress: Double?   // set while downloading / installing

    init(id: String, title: String, subtitle: String = "") {
        self.id = id
        self.title = systemAppInfo[id]?.name ?? title
        self.subtitle = subtitle
        self.symbol = systemAppInfo[id]?.symbol
    }
}

/// Installed games and apps, downloads in progress, and a "Popular games" shelf.
/// Names, icons and game/app category come from the app's public Play Store
/// page and are cached in ~/.nunu/library.
@MainActor
final class LibraryModel: ObservableObject {
    @Published var games: [AppTile] = []
    @Published var others: [AppTile] = []
    @Published var downloads: [AppTile] = []
    @Published var featured: [AppTile] = []
    @Published var loading = false
    /// Name of the app being opened; Home stays up with a spinner until it's in front.
    @Published var opening: String?

    var onLaunch: ((String) -> Void)?
    var onStorePage: ((String) -> Void)?
    var onPlayStore: (() -> Void)?
    var onAndroidSettings: (() -> Void)?
    var onNunuSettings: (() -> Void)?
    var onInstallAPK: (() -> Void)?
    var onEditControls: ((String) -> Void)?
    var onUninstall: ((String) -> Void)?
    var onCancelDownload: ((String) -> Void)?
    var listApps: (() async -> [String])?

    /// Reached from Home's own buttons instead of the grids.
    private static let hidden: Set<String> = ["com.android.vending", "com.google.android.gms", "com.android.chrome"]
    private var isGame: [String: Bool] = [:]
    private var installed: [String] = []

    func refresh() async {
        guard let listApps else { return }
        loading = true
        installed = await listApps().filter { !Self.hidden.contains($0) }
        regroup()
        let have = Set(installed)
        featured = FeaturedGame.all.filter { !have.contains($0.id) }.map { g in
            featured.first { $0.id == g.id } ?? AppTile(id: g.id, title: g.name, subtitle: g.genre)
        }
        loading = false
        for pkg in installed + featured.map(\.id) {
            Task { await self.loadMetadata(pkg) }
        }
    }

    /// Install sessions from Android plus local sideloads; a finished one triggers a refresh.
    func updateDownloads(_ sessions: [(pkg: String, progress: Double)]) {
        let finished = downloads.contains { d in !sessions.contains { $0.pkg == d.id } }
        downloads = sessions.map { s in
            var tile = downloads.first { $0.id == s.pkg } ?? existingTile(s.pkg) ?? Self.downloadTile(s.pkg)
            tile.progress = s.progress
            return tile
        }
        for d in downloads where d.icon == nil && !d.id.hasPrefix("apk:") { Task { await loadMetadata(d.id) } }
        if finished { Task { await refresh() } }
    }

    /// "apk:<file name>" ids are sideloads from the Mac.
    private static func downloadTile(_ id: String) -> AppTile {
        guard id.hasPrefix("apk:") else { return AppTile(id: id, title: fallbackTitle(id)) }
        var tile = AppTile(id: id, title: String(id.dropFirst(4)), subtitle: "Installing from Mac")
        tile.symbol = "shippingbox.fill"
        return tile
    }

    /// Unknown apps go to Others until their store page says they're a game.
    private func regroup() {
        let tiles = installed.map { existingTile($0) ?? AppTile(id: $0, title: Self.fallbackTitle($0)) }
        games = tiles.filter { isGame[$0.id] == true }
        others = tiles.filter { isGame[$0.id] != true }
    }

    private func existingTile(_ pkg: String) -> AppTile? {
        (games + others + downloads + featured).first { $0.id == pkg }
    }

    private func loadMetadata(_ pkg: String) async {
        guard let meta = await StoreMetadata.shared.fetch(pkg) else { return }
        func apply(_ list: inout [AppTile], keepTitle: Bool = false) {
            for i in list.indices where list[i].id == pkg {
                if !keepTitle, list[i].symbol == nil, let title = meta.title { list[i].title = title }
                list[i].icon = meta.icon
                if list[i].subtitle.isEmpty, let genre = meta.genre { list[i].subtitle = genre }
            }
        }
        if let game = meta.isGame { isGame[pkg] = game }
        // Popular games keep nunu's short names ("Genshin Impact", not the store's promo title).
        apply(&games); apply(&others); apply(&downloads); apply(&featured, keepTitle: true)
        if installed.contains(pkg) { regroup() }
    }

    /// "com.supercell.clashroyale" -> "Clashroyale"
    nonisolated static func fallbackTitle(_ pkg: String) -> String {
        let last = pkg.split(separator: ".").last.map(String.init) ?? pkg
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

/// Play Store page scraping for title, icon and category, cached on disk.
actor StoreMetadata {
    static let shared = StoreMetadata()

    struct Meta {
        var title: String?
        var icon: NSImage?
        /// Play category id, e.g. "GAME_STRATEGY", "TOOLS".
        var category: String?

        var isGame: Bool? { category.map { $0.hasPrefix("GAME") } }

        /// "GAME_ROLE_PLAYING" -> "Role Playing"
        var genre: String? {
            guard let category else { return nil }
            let words = category.replacingOccurrences(of: "GAME_", with: "").split(separator: "_")
            return words.map { $0.prefix(1) + $0.dropFirst().lowercased() }.joined(separator: " ")
        }
    }

    private struct Cached: Codable {
        var title: String?
        var category: String?
    }

    private var memory: [String: Meta] = [:]
    private let dir = Paths.root.appendingPathComponent("library", isDirectory: true)

    func fetch(_ pkg: String) async -> Meta? {
        if let m = memory[pkg] { return m }
        Paths.ensure(dir)
        let iconFile = dir.appendingPathComponent("\(pkg).png")
        let metaFile = dir.appendingPathComponent("\(pkg).json")
        if let image = NSImage(contentsOf: iconFile),
           let data = try? Data(contentsOf: metaFile),
           let cached = try? JSONDecoder().decode(Cached.self, from: data) {
            let m = Meta(title: cached.title, icon: image, category: cached.category)
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
        if let title = Self.metaContent("og:title", in: html) {
            meta.title = Self.unescape(title.replacingOccurrences(of: " - Apps on Google Play", with: ""))
        }
        meta.category = Self.category(in: html)
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
        if let data = try? JSONEncoder().encode(Cached(title: meta.title, category: meta.category)) {
            try? data.write(to: metaFile)
        }
        memory[pkg] = meta
        return meta
    }

    /// The app's own category link. FAMILY is in the site navigation on every page.
    private static func category(in html: String) -> String? {
        var rest = html[...]
        while let r = rest.range(of: "/store/apps/category/") {
            let id = String(rest[r.upperBound...].prefix { $0.isUppercase || $0 == "_" })
            if !id.isEmpty, id != "FAMILY" { return id }
            rest = rest[r.upperBound...]
        }
        return nil
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

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 18, alignment: .top)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color(red: 0.07, green: 0.08, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if !model.downloads.isEmpty {
                        section("Downloading") {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(model.downloads) { tile in
                                    TileView(tile: tile, onCancel: { model.onCancelDownload?(tile.id) }) {
                                        model.onStorePage?(tile.id)
                                    }
                                }
                            }
                        }
                    }
                    section("My games") {
                        if model.games.isEmpty && !model.loading {
                            emptyState
                        } else {
                            grid(model.games)
                        }
                    }
                    if !model.others.isEmpty {
                        section("Others") { grid(model.others) }
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
        .overlay(alignment: .bottom) {
            if let name = model.opening {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Opening \(name)…").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.opening)
        .alert(item: $confirmUninstall) { tile in
            Alert(title: Text("Uninstall \(tile.title)?"),
                  message: Text("Its data and saved controls on this Mac stay until you reinstall."),
                  primaryButton: .destructive(Text("Uninstall")) { model.onUninstall?(tile.id) },
                  secondaryButton: .cancel())
        }
    }

    private func grid(_ tiles: [AppTile]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(tiles) { tile in
                TileView(tile: tile) { model.onLaunch?(tile.id) }
                    .contextMenu { menu(for: tile) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("nunu").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            pill("Play Store", "bag.fill") { model.onPlayStore?() }
            pill("Install APK", "square.and.arrow.down") { model.onInstallAPK?() }
            pill("Android settings", "gearshape.fill") { model.onAndroidSettings?() }
            pill("nunu settings", "slider.horizontal.3") { model.onNunuSettings?() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No games yet. Install one from the Play Store, or drop an APK from your Mac onto this window.")
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
    var onCancel: (() -> Void)? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if let icon = tile.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else if let symbol = tile.symbol {
                        LinearGradient(colors: [Color(white: 0.28), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
                        Image(systemName: symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(tile.title.prefix(1)))
                            .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    if let p = tile.progress, p < 0 {
                        // Sideloads: adb reports no progress
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.45))
                            ProgressView().controlSize(.regular).tint(.white)
                        }
                    } else if let p = tile.progress {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.45))
                            Circle().stroke(.white.opacity(0.25), lineWidth: 5).frame(width: 46, height: 46)
                            Circle().trim(from: 0, to: max(0.02, p))
                                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90)).frame(width: 46, height: 46)
                                .animation(.linear(duration: 0.4), value: p)
                            Text("\(Int(p * 100))%").font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: hover ? 10 : 4, y: hover ? 6 : 2)
                .scaleEffect(hover ? 1.06 : 1)
                .overlay(alignment: .topTrailing) {
                    if let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22)).symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel download")
                        .offset(x: 8, y: -8)
                    } else if let badge {
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
