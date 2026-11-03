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

struct InstallSession: Equatable {
    let id: Int
    let pkg: String
    let progress: Double   // 0...1
}

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
            // Typing comes from the Mac keyboard; don't cover half the screen with Gboard.
            "settings put secure show_ime_with_hard_keyboard 0",
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

    /// Installed apps that have a home-screen icon (skips background components
    /// like Play's verifier/SafetyCore that arrive after sign-in).
    func launchableUserApps() async -> [String] {
        let user = await userApps()
        let out = await shell("cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER")
        let launchable = Set(out.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.contains(" "), let slash = line.firstIndex(of: "/") else { return nil }
            return String(line[..<slash])
        })
        return user.filter(launchable.contains)
    }

    /// Downloads/installs in progress (Play Store install sessions).
    func installSessions() async -> [InstallSession] {
        let out = await shell("dumpsys package installs")
        guard let start = out.range(of: "Active install sessions:") else { return [] }
        let end = out.range(of: "Historical install sessions:")?.lowerBound ?? out.endIndex
        guard start.upperBound < end else { return [] }
        var sessions: [InstallSession] = []
        for block in out[start.upperBound..<end].components(separatedBy: "Active Session ").dropFirst() {
            func value(_ key: String) -> String? {
                guard let r = block.range(of: key) else { return nil }
                return String(block[r.upperBound...].prefix { !$0.isWhitespace })
            }
            guard let id = Int(block.prefix { $0.isNumber }), let pkg = value("appPackageName="),
                  !pkg.isEmpty, pkg != "null", value("mCommitted=") != "true", value("mDestroyed=") != "true"
            else { continue }
            sessions.append(InstallSession(id: id, pkg: pkg, progress: Double(value("mClientProgress=") ?? "") ?? 0))
        }
        return sessions
    }

    /// Cancels a download. The session belongs to the Play Store, so if Android
    /// won't let shell abandon it, press Play's own cancel button on the app's page.
    func cancelDownload(_ s: InstallSession) async -> Bool {
        if await shell("pm install-abandon \(s.id) 2>&1").contains("Success") { return true }
        await openStorePage(s.pkg)
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(1200))
            if await tapNode(labelled: ["Cancel download", "Cancel install", "Cancel"]) { return true }
        }
        return false
    }

    /// Finds an on-screen element by text/content description via uiautomator and taps it.
    func tapNode(labelled labels: [String]) async -> Bool {
        let xml = await shell("uiautomator dump /dev/tty 2>/dev/null")
        for node in xml.components(separatedBy: "<node ").dropFirst() {
            func attr(_ name: String) -> String? {
                guard let r = node.range(of: " \(name)=\"") ?? (node.hasPrefix("\(name)=\"") ? node.range(of: "\(name)=\"") : nil)
                else { return nil }
                return String(node[r.upperBound...].prefix { $0 != "\"" })
            }
            let names = [attr("text"), attr("content-desc")].compactMap { $0 }
            guard names.contains(where: { n in labels.contains { n.caseInsensitiveCompare($0) == .orderedSame } }),
                  let bounds = attr("bounds") else { continue }
            let nums = bounds.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard nums.count == 4 else { continue }
            await shell("input tap \((nums[0] + nums[2]) / 2) \((nums[1] + nums[3]) / 2)")
            return true
        }
        return false
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
    /// instead of polling dumpsys. Stop it with `cancel()`.
    func watchForeground(_ onChange: @escaping @MainActor (String) -> Void) -> LogStream? {
        streamLogcat("-b events -T 1 -v brief -s wm_set_resumed_activity") { line in
            // I/wm_set_resumed_activity( 567): [0,com.foo/.Main,reason]
            guard let open = line.firstIndex(of: "[") else { return }
            let fields = line[line.index(after: open)...].split(separator: ",")
            guard fields.count > 1, let slash = fields[1].firstIndex(of: "/") else { return }
            onChange(String(fields[1][..<slash]))
        }
    }

    /// Runs `logcat <args>` in the guest and hands each line to `onLine` on the main actor.
    func streamLogcat(_ args: String, onLine: @escaping @MainActor (String) -> Void) -> LogStream? {
        LogStream(arguments: ["-s", serial, "shell", "logcat \(args)"], onLine: onLine)
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

/// A long-running `adb shell logcat`. Lines are read with a GCD readability
/// handler (no Swift task sits blocked in read()) and delivered on the main actor.
final class LogStream: @unchecked Sendable {
    private let process = Process()
    private var pending = Data()

    init?(arguments: [String], onLine: @escaping @MainActor (String) -> Void) {
        process.executableURL = Paths.adb
        process.arguments = arguments
        process.environment = Engine.environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else {
                handle.readabilityHandler = nil   // EOF: adb exited
                return
            }
            self.pending.append(chunk)
            while let nl = self.pending.firstIndex(of: 0x0A) {
                let line = String(decoding: self.pending[self.pending.startIndex..<nl], as: UTF8.self)
                self.pending.removeSubrange(self.pending.startIndex...nl)
                DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
            }
        }
        guard (try? process.run()) != nil else { return nil }
    }

    func cancel() {
        if process.isRunning { process.terminate() }
    }

    deinit { cancel() }
}
