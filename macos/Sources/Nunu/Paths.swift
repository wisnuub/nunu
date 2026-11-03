import Foundation

/// Everything nunu owns lives under ~/.nunu, shared with the Windows launcher's layout.
enum Paths {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".nunu", isDirectory: true)
    static let sdk = root.appendingPathComponent("sdk", isDirectory: true)
    static let avdHome = root.appendingPathComponent("avd", isDirectory: true)
    static let logs = root.appendingPathComponent("logs", isDirectory: true)
    static let keymaps = root.appendingPathComponent("keymaps", isDirectory: true)
    static let run = root.appendingPathComponent("run", isDirectory: true)
    /// KernelSU artifacts: the custom kernel, manager APK, generated profile module.
    static let rootKit = root.appendingPathComponent("root", isDirectory: true)
    static let screenshots = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/nunu", isDirectory: true)

    static let avdName = "nunu"
    static var avdDir: URL { avdHome.appendingPathComponent("\(avdName).avd", isDirectory: true) }
    static var emulator: URL { sdk.appendingPathComponent("emulator/emulator") }
    static var adb: URL { sdk.appendingPathComponent("platform-tools/adb") }
    static var engineState: URL { run.appendingPathComponent("engine.json") }

    /// Custom KernelSU + SUSFS kernel. When present and root is enabled, the
    /// engine boots this instead of the stock `kernel-ranchu`.
    static var ksuKernel: URL { rootKit.appendingPathComponent("kernel-ranchu-ksu") }
    static var ksuManagerAPK: URL { rootKit.appendingPathComponent("KernelSUManager.apk") }

    static func ensure(_ dirs: URL...) {
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
