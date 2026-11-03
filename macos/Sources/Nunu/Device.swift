import Foundation

/// User-tunable shape of the Android device. Persisted in UserDefaults and
/// rendered into the AVD config.ini before every boot.
struct DeviceSettings: Codable, Equatable {
    var width: Int
    var height: Int
    var density: Int
    var ramMB: Int
    var cores: Int
    var showFPS: Bool = false

    static let resolutions: [(label: String, width: Int, height: Int, density: Int)] = [
        ("1280 × 720", 1280, 720, 240),
        ("1600 × 900", 1600, 900, 280),
        ("1920 × 1080", 1920, 1080, 320),
        ("2560 × 1440", 2560, 1440, 440),
    ]

    /// Sized for the host: an 8 GB M1 gets 3 GB / 4 cores, bigger Macs get more.
    static var recommended: DeviceSettings {
        let hostGB = Int(ProcessInfo.processInfo.physicalMemory >> 30)
        let perfCores = sysctlInt("hw.perflevel0.physicalcpu") ?? 4
        let ram = hostGB >= 32 ? 8192 : hostGB >= 16 ? 4096 : 3072
        let cores = max(2, min(perfCores, hostGB >= 16 ? 8 : 4))
        return DeviceSettings(width: 1280, height: 720, density: 240, ramMB: ram, cores: cores)
    }

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
            ("disk.dataPartition.size", "8G"),
            ("image.sysdir.1", systemImage),
            ("tag.id", "google_apis_playstore"),
            ("tag.display", "Google Play"),
            ("hw.lcd.width", "\(s.width)"),
            ("hw.lcd.height", "\(s.height)"),
            ("hw.lcd.density", "\(s.density)"),
            ("hw.initialOrientation", s.width >= s.height ? "landscape" : "portrait"),
            ("hw.gpu.enabled", "yes"),
            ("hw.gpu.mode", "host"),
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
            ("hw.audioOutput", "yes"),
            ("hw.camera.back", "none"),
            ("hw.camera.front", "none"),
            ("hw.gps", "yes"),
            ("hw.sdCard", "no"),
            ("showDeviceFrame", "no"),
            ("fastboot.forceColdBoot", "no"),
        ]
        let body = config.map { "\($0.0)=\($0.1)" }.joined(separator: "\n") + "\n"
        try body.write(to: Paths.avdDir.appendingPathComponent("config.ini"),
                       atomically: true, encoding: .utf8)
    }
}
