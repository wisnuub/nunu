import Foundation

/// Everything the user can tune. Persisted in UserDefaults; the device part is
/// rendered into the AVD config.ini and engine flags before every boot.
struct DeviceSettings: Codable, Equatable {
    enum Renderer: String, Codable, CaseIterable {
        case metal, software
    }

    enum Profile: String, CaseIterable {
        case low, balanced, high, custom
    }

    // Device (Android restarts to apply)
    var width = 1280
    var height = 720
    var density = 240
    var ramMB = 3072
    var cores = 4
    var refreshRate = 60
    var renderer = Renderer.metal
    var vulkan = true
    var audio = true
    var quickBoot = true
    var dataSizeGB = 8
    var highPriority = true

    // Live (applied without a restart)
    var reduceAnimations = true
    var gameMode = true
    var showFPS = false
    var showHints = true
    var aimSensitivity = 1.0
    var touchID = true
    var disabledApps: [String] = Debloat.recommended

    init() {}

    /// Older saves lack newer keys; fall back to defaults instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DeviceSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        width = v(.width, d.width)
        height = v(.height, d.height)
        density = v(.density, d.density)
        ramMB = v(.ramMB, d.ramMB)
        cores = v(.cores, d.cores)
        refreshRate = v(.refreshRate, d.refreshRate)
        renderer = v(.renderer, d.renderer)
        vulkan = v(.vulkan, d.vulkan)
        audio = v(.audio, d.audio)
        quickBoot = v(.quickBoot, d.quickBoot)
        dataSizeGB = v(.dataSizeGB, d.dataSizeGB)
        highPriority = v(.highPriority, d.highPriority)
        reduceAnimations = v(.reduceAnimations, d.reduceAnimations)
        gameMode = v(.gameMode, d.gameMode)
        showFPS = v(.showFPS, d.showFPS)
        showHints = v(.showHints, d.showHints)
        aimSensitivity = v(.aimSensitivity, d.aimSensitivity)
        touchID = v(.touchID, d.touchID)
        disabledApps = v(.disabledApps, d.disabledApps)
    }

    /// True when `other` differs in anything that only takes effect on boot.
    func needsRestart(comparedTo other: DeviceSettings) -> Bool {
        width != other.width || height != other.height || density != other.density
            || ramMB != other.ramMB || cores != other.cores || refreshRate != other.refreshRate
            || renderer != other.renderer || vulkan != other.vulkan || audio != other.audio
            || quickBoot != other.quickBoot || dataSizeGB != other.dataSizeGB
            || highPriority != other.highPriority
    }

    var isLandscape: Bool { width >= height }

    // MARK: Presets

    static let resolutions: [(label: String, width: Int, height: Int, density: Int)] = [
        ("1280 × 720 (HD)", 1280, 720, 240),
        ("1600 × 900", 1600, 900, 280),
        ("1920 × 1080 (Full HD)", 1920, 1080, 320),
        ("1920 × 1200 (Tablet)", 1920, 1200, 280),
        ("2560 × 1440 (QHD)", 2560, 1440, 440),
        ("720 × 1280 (HD)", 720, 1280, 280),
        ("1080 × 1920 (Full HD)", 1080, 1920, 420),
        ("1080 × 2400 (Tall phone)", 1080, 2400, 420),
    ]

    static let densities = [160, 200, 240, 280, 320, 360, 400, 440, 480]
    static let refreshRates = [30, 60, 90, 120]
    static let dataSizes = [8, 16, 32, 64]

    static var hostGB: Int { Int(ProcessInfo.processInfo.physicalMemory >> 30) }
    static var hostCores: Int { ProcessInfo.processInfo.activeProcessorCount }
    static var perfCores: Int { sysctlInt("hw.perflevel0.physicalcpu") ?? 4 }

    /// RAM choices that leave macOS at least ~40% of the Mac's memory.
    static var ramChoices: [Int] {
        [2048, 3072, 4096, 6144, 8192, 12288, 16384].filter { $0 <= hostGB * 1024 * 6 / 10 }
    }

    func applying(_ profile: Profile) -> DeviceSettings {
        var s = self
        let ram = Self.ramChoices
        switch profile {
        case .low:
            s.cores = 2
            s.ramMB = 2048
        case .balanced:
            s.cores = Self.recommended.cores
            s.ramMB = Self.recommended.ramMB
        case .high:
            s.cores = min(Self.hostCores, max(Self.perfCores, 4) + 2)
            s.ramMB = ram.last ?? 4096
        case .custom:
            break
        }
        return s
    }

    var profile: Profile {
        for p in [Profile.low, .balanced, .high] {
            let t = applying(p)
            if t.cores == cores && t.ramMB == ramMB { return p }
        }
        return .custom
    }

    /// Sized for the host: an 8 GB M1 gets 3 GB / 4 cores, bigger Macs get more.
    static var recommended: DeviceSettings {
        var s = DeviceSettings()
        s.ramMB = hostGB >= 32 ? 8192 : hostGB >= 16 ? 4096 : 3072
        s.cores = max(2, min(perfCores, hostGB >= 16 ? 8 : 4))
        return s
    }

    // MARK: Persistence

    private static let defaultsKey = "deviceSettings"

    static func load() -> DeviceSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(DeviceSettings.self, from: data)
        else { return .recommended }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

/// Writes the AVD by hand so nunu never needs Java/avdmanager.
enum AVD {
    static let systemImage = "system-images/android-34/google_apis_playstore/arm64-v8a/"

    static func write(_ s: DeviceSettings) throws {
        Paths.ensure(Paths.avdDir)
        let ini = """
        avd.ini.encoding=UTF-8
        path=\(Paths.avdDir.path)
        path.rel=\(Paths.avdName).avd
        target=android-34

        """
        try ini.write(to: Paths.avdHome.appendingPathComponent("\(Paths.avdName).ini"),
                      atomically: true, encoding: .utf8)

        let config: [(String, String)] = [
            ("AvdId", Paths.avdName),
            ("avd.ini.displayname", "nunu"),
            ("avd.ini.encoding", "UTF-8"),
            ("PlayStore.enabled", "true"),
            ("abi.type", "arm64-v8a"),
            ("hw.cpu.arch", "arm64"),
            ("hw.cpu.ncore", "\(s.cores)"),
            ("hw.ramSize", "\(s.ramMB)"),
            ("vm.heapSize", "512"),
            ("disk.dataPartition.size", "\(s.dataSizeGB)G"),
            ("image.sysdir.1", systemImage),
            ("tag.id", "google_apis_playstore"),
            ("tag.display", "Google Play"),
            ("hw.lcd.width", "\(s.width)"),
            ("hw.lcd.height", "\(s.height)"),
            ("hw.lcd.density", "\(s.density)"),
            ("hw.lcd.vsync", "\(s.refreshRate)"),
            ("hw.initialOrientation", s.isLandscape ? "landscape" : "portrait"),
            ("hw.gpu.enabled", "yes"),
            ("hw.gpu.mode", s.renderer == .metal ? "host" : "software"),
            ("hw.keyboard", "yes"),
            ("hw.mainKeys", "no"),
            ("hw.dPad", "no"),
            ("hw.trackBall", "no"),
            ("hw.accelerometer", "yes"),
            ("hw.gyroscope", "yes"),
            ("hw.sensors.orientation", "yes"),
            ("hw.sensors.proximity", "no"),
            ("hw.battery", "yes"),
            ("hw.audioInput", "no"),
            ("hw.audioOutput", s.audio ? "yes" : "no"),
            ("hw.camera.back", "none"),
            ("hw.camera.front", "none"),
            ("hw.gps", "yes"),
            ("hw.sdCard", "no"),
            ("showDeviceFrame", "no"),
            ("fastboot.forceColdBoot", s.quickBoot ? "no" : "yes"),
        ]
        let body = config.map { "\($0.0)=\($0.1)" }.joined(separator: "\n") + "\n"
        try body.write(to: Paths.avdDir.appendingPathComponent("config.ini"),
                       atomically: true, encoding: .utf8)
    }
}
