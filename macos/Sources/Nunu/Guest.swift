import Foundation

/// Preinstalled apps a gaming VM doesn't need. Disabling (`pm disable-user`)
/// stops them running in the background and is fully reversible.
enum Debloat {
    struct App: Identifiable {
        let id: String
        let name: String
        let recommended: Bool
        /// Everyday apps people recognise; the rest sit behind "Show all".
        var common = false
    }

    static let catalog: [App] = [
        App(id: "com.google.android.youtube", name: "YouTube", recommended: true, common: true),
        App(id: "com.google.android.apps.youtube.music", name: "YouTube Music", recommended: true, common: true),
        App(id: "com.google.android.apps.maps", name: "Google Maps", recommended: true, common: true),
        App(id: "com.google.android.apps.docs", name: "Google Drive", recommended: true, common: true),
        App(id: "com.google.android.apps.photos", name: "Google Photos", recommended: true, common: true),
        App(id: "com.google.android.gm", name: "Gmail", recommended: true, common: true),
        App(id: "com.google.android.calendar", name: "Calendar", recommended: true, common: true),
        App(id: "com.google.android.apps.messaging", name: "Messages", recommended: true, common: true),
        App(id: "com.google.android.dialer", name: "Phone", recommended: true, common: true),
        App(id: "com.google.android.contacts", name: "Contacts", recommended: true, common: true),
        App(id: "com.google.android.deskclock", name: "Clock", recommended: true, common: true),
        App(id: "com.android.camera2", name: "Camera", recommended: true, common: true),
        App(id: "com.google.android.apps.wellbeing", name: "Digital Wellbeing", recommended: true),
        App(id: "com.google.android.projection.gearhead", name: "Android Auto", recommended: true),
        App(id: "com.google.android.googlequicksearchbox", name: "Google app & Assistant", recommended: true),
        App(id: "com.google.android.as", name: "Android System Intelligence", recommended: true),
        App(id: "com.google.android.as.oss", name: "Private Compute Services", recommended: true),
        App(id: "com.android.emergency", name: "Emergency info", recommended: true),
        App(id: "com.android.dreams.basic", name: "Screen saver", recommended: true),
        App(id: "com.google.android.apps.wallpaper.nexus", name: "Live wallpapers", recommended: true),
        App(id: "com.google.android.apps.customization.pixel", name: "Theme picker", recommended: true),
        App(id: "com.google.android.markup", name: "Screenshot markup", recommended: true),
        App(id: "com.android.chrome", name: "Chrome (Google sign-in may open it)", recommended: false, common: true),
    ]

    static let recommended = catalog.filter(\.recommended).map(\.id)
}

/// Android's own home app. nunu Home covers it whenever it's in front, including
/// its Recents overview, which nunu replaces with its own Recent row.
let androidLauncher = "com.google.android.apps.nexuslauncher"

/// An app task in Android's recents list.
struct RecentTask: Identifiable, Equatable {
    let id: Int        // task id (== root task id on Android 14)
    let pkg: String
}

/// System apps with no Play Store page get a name and SF Symbol instead.
let systemAppInfo: [String: (name: String, symbol: String)] = [
    "com.android.vending": ("Play Store", "play.fill"),
    "com.android.settings": ("Settings", "gearshape.fill"),
    "com.google.android.gms": ("Google Play services", "puzzlepiece.fill"),
    "com.google.android.packageinstaller": ("Package installer", "shippingbox.fill"),
    "com.google.android.documentsui": ("Files", "folder.fill"),
]

/// Catalogue shown under "Popular games" (same list as the Windows launcher).
struct FeaturedGame: Identifiable {
    let id: String
    let name: String
    let genre: String

    static let all: [FeaturedGame] = [
        FeaturedGame(id: "com.tencent.ig", name: "PUBG Mobile", genre: "Battle Royale"),
        FeaturedGame(id: "com.miHoYo.GenshinImpact", name: "Genshin Impact", genre: "Action RPG"),
        FeaturedGame(id: "com.riotgames.league.teamfighttactics", name: "Teamfight Tactics", genre: "Strategy"),
        FeaturedGame(id: "com.mobile.legends", name: "Mobile Legends", genre: "MOBA"),
        FeaturedGame(id: "com.activision.callofduty.shooter", name: "Call of Duty: Mobile", genre: "FPS"),
        FeaturedGame(id: "com.HoYoverse.hkrpgoversea", name: "Honkai: Star Rail", genre: "Turn-Based RPG"),
    ]
}

extension Engine {
    /// Per-boot tuning. Every command is idempotent, so quick-boot resumes are fine.
    func applyTweaks(_ s: DeviceSettings) async {
        let anim = s.reduceAnimations ? "0.5" : "1.0"
        let commands = [
            "settings put system screen_off_timeout 2147483647",
            "svc power stayon true",
            "settings put global window_animation_scale \(anim)",
            "settings put global transition_animation_scale \(anim)",
            "settings put global animator_duration_scale \(anim)",
            // Background Wi-Fi/BLE scanning is pointless in a VM
            "settings put global wifi_scan_always_enabled 0",
            "settings put global ble_scan_always_enabled 0",
            "settings put system peak_refresh_rate \(s.refreshRate).0",
            "settings put system min_refresh_rate \(s.refreshRate).0",
        ]
        await shell(commands.joined(separator: "; ") + " >/dev/null 2>&1")
        await applyDebloat(Set(s.disabledApps))
        if s.gameMode { await applyGameMode() }
    }

    /// Brings the enabled/disabled state of catalogue apps in line with `disabled`,
    /// in a single shell round trip.
    func applyDebloat(_ disabled: Set<String>) async {
        let current = Set(await shell("pm list packages -d")
            .split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) })
        var commands: [String] = []
        for app in Debloat.catalog {
            let want = disabled.contains(app.id)
            if want && !current.contains(app.id) {
                commands.append("pm disable-user --user 0 \(app.id)")
            } else if !want && current.contains(app.id) {
                commands.append("pm enable \(app.id)")
            }
        }
        guard !commands.isEmpty else { return }
        await shell(commands.joined(separator: "; ") + " >/dev/null 2>&1")
    }

    /// Asks Android's Game Manager for performance mode on every installed app.
    /// Games that declare game-mode support switch; everything else ignores it.
    func applyGameMode() async {
        let apps = await userApps()
        guard !apps.isEmpty else { return }
        let commands = apps.map { "cmd game mode performance \($0)" }
        await shell(commands.joined(separator: "; ") + " >/dev/null 2>&1")
    }

    /// Packages the user installed (not part of the system image).
    func userApps() async -> [String] {
        await shell("pm list packages -3")
            .split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func launchApp(_ pkg: String) async {
        await shell("monkey -p \(pkg) -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
    }

    func openStorePage(_ pkg: String) async {
        await shell("am start -a android.intent.action.VIEW -d 'market://details?id=\(pkg)' >/dev/null 2>&1")
    }

    func openPlayStore() async { await launchApp("com.android.vending") }

    func openAndroidSettings() async {
        await shell("am start -a android.settings.SETTINGS >/dev/null 2>&1")
    }

    func uninstall(_ pkg: String) async {
        await shell("pm uninstall \(pkg) >/dev/null 2>&1")
    }

    /// Recent app tasks, most recent first, without home tasks. `unique` keeps
    /// only each app's newest task.
    func recentTasks(unique: Bool = true) async -> [RecentTask] {
        let out = await shell("dumpsys activity recents")
        var tasks: [RecentTask] = []
        var seen: Set<String> = []
        for block in out.components(separatedBy: "* Recent #").dropFirst() {
            let header = block.prefix { $0 != "\n" }
            guard !header.contains("type=home"),
                  let hash = header.range(of: " #"),
                  let id = Int(header[hash.upperBound...].prefix { $0.isNumber }),
                  let real = block.range(of: "realActivity={") else { continue }
            let pkg = String(block[real.upperBound...].prefix { $0 != "/" && $0 != "}" })
            guard !pkg.isEmpty, pkg != androidLauncher, !(unique && seen.contains(pkg)) else { continue }
            seen.insert(pkg)
            tasks.append(RecentTask(id: id, pkg: pkg))
        }
        return tasks
    }

    /// Recent apps that still have a live process, oldest first (tab order).
    func runningApps() async -> [String] {
        let tasks = await recentTasks().filter { !transientPackages.contains($0.pkg) }
        guard !tasks.isEmpty else { return [] }
        let probe = tasks.map { "pidof \($0.pkg) >/dev/null && echo \($0.pkg)" }.joined(separator: "; ")
        let alive = Set(await shell(probe).split(whereSeparator: \.isNewline).map(String.init))
        return tasks.reversed().map(\.pkg).filter(alive.contains)
    }

    /// Removes the apps' tasks from recents and stops them, freeing their memory.
    func closeApps(_ pkgs: [String]) async {
        let tasks = await recentTasks(unique: false)
        var commands: [String] = []
        for pkg in pkgs {
            for t in tasks where t.pkg == pkg { commands.append("cmd activity stack remove \(t.id)") }
            commands.append("am force-stop \(pkg)")
        }
        await shell(commands.joined(separator: "; ") + " >/dev/null 2>&1")
    }

    func foregroundPackage() async -> String? {
        let out = await shell("dumpsys activity activities | grep -m1 topResumedActivity")
        return Self.package(fromActivityLine: out)
    }

    /// Streams foreground-app changes from Android's event log as they happen,
    /// instead of polling dumpsys. Ends when the engine goes away.
    func watchForeground(_ onChange: @escaping @MainActor (String) -> Void) -> Task<Void, Never> {
        let serial = self.serial
        return Task.detached {
            let p = Process()
            p.executableURL = Paths.adb
            p.arguments = ["-s", serial, "shell", "logcat -b events -T 1 -v brief -s wm_set_resumed_activity"]
            p.environment = Engine.environment
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            await withTaskCancellationHandler {
                do {
                    for try await line in out.fileHandleForReading.bytes.lines {
                        // I/wm_set_resumed_activity( 567): [0,com.foo/.Main,reason]
                        guard let open = line.firstIndex(of: "[") else { continue }
                        let fields = line[line.index(after: open)...].split(separator: ",")
                        guard fields.count > 1, let slash = fields[1].firstIndex(of: "/") else { continue }
                        let pkg = String(fields[1][..<slash])
                        await onChange(pkg)
                    }
                } catch {}
            } onCancel: {
                p.terminate()
            }
        }
    }

    /// "topResumedActivity=ActivityRecord{1a2b u0 com.foo.bar/.Main t12}" -> "com.foo.bar"
    nonisolated static func package(fromActivityLine line: String) -> String? {
        guard let slash = line.firstIndex(of: "/") else { return nil }
        let head = line[..<slash]
        guard let space = head.lastIndex(of: " ") else { return nil }
        let pkg = String(head[head.index(after: space)...])
        return pkg.isEmpty ? nil : pkg
    }
}
