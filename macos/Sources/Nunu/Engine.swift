import Darwin
import Foundation

/// Owns the Android VM process: launch (or re-attach after a nunu crash),
/// boot detection, guest tweaks, and graceful shutdown with quick-boot save.
@MainActor
final class Engine {
    enum Phase: Equatable {
        case stopped, launching, booting, ready, stopping
        case failed(String)
    }

    /// Private adb server so nunu never fights another SDK's adb on 5037.
    nonisolated static let adbServerPort = 5137

    private(set) var phase: Phase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            log(String(format: "%@ (+%.1fs)", "\(phase)", Date().timeIntervalSince(phaseClock)))
            onPhase?(phase)
        }
    }
    private var phaseClock = Date()
    var onPhase: ((Phase) -> Void)?
    var onClientReady: ((EngineClient) -> Void)?
    /// Fires once adb can reach the guest after each boot/re-attach.
    var onGuestReady: (() -> Void)?

    /// Settings the running engine was started with (guest tweaks read the live ones).
    private(set) var settings = DeviceSettings()
    private var activity: NSObjectProtocol?

    private(set) var client: EngineClient?
    private(set) var consolePort = 0
    private(set) var grpcPort = 0
    private var pid: pid_t = 0
    private var process: Process?
    private var watchdog: Task<Void, Never>?

    var serial: String { "emulator-\(consolePort)" }

    private struct State: Codable {
        var pid: Int32
        var grpcPort: Int
        var consolePort: Int
    }

    // MARK: - Start

    func start(_ settings: DeviceSettings, wipeData: Bool = false) async {
        guard phase == .stopped || phase.isFailed else { return }
        self.settings = settings
        phaseClock = Date()
        phase = .launching
        Paths.ensure(Paths.logs, Paths.run)
        Self.killOrphanedWatchers()

        if let running = Self.loadState().flatMap({ Self.isEngineProcess($0.pid) ? $0 : nil })
            ?? Self.discoverRunningEngine() {
            pid = running.pid
            grpcPort = running.grpcPort
            consolePort = running.consolePort
            Self.saveState(running)
            log("re-attaching to running engine pid \(pid)")
        } else {
            do {
                try AVD.write(settings)
                try launch(settings, wipeData: wipeData)
            } catch {
                phase = .failed("Couldn't start Android: \(error.localizedDescription)")
                return
            }
        }

        do {
            let c = try EngineClient(port: grpcPort)
            c.start()
            client = c
            onClientReady?(c)
        } catch {
            phase = .failed("Couldn't connect to Android: \(error.localizedDescription)")
            return
        }
        startWatchdog()
        phase = .booting
        await waitForBoot()
    }

    private func launch(_ s: DeviceSettings, wipeData: Bool) throws {
        consolePort = Self.freeConsolePort()
        grpcPort = Self.freePort(startingAt: 8580)
        _ = Self.adbSync(["start-server"])

        let logURL = Paths.logs.appendingPathComponent("engine.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)

        let p = Process()
        p.executableURL = Paths.emulator
        p.arguments = [
            "-avd", Paths.avdName,
            "-qt-hide-window",
            "-grpc", "\(grpcPort)",
            "-port", "\(consolePort)",
            "-gpu", s.renderer == .metal ? "host" : "swiftshader_indirect",
            "-no-boot-anim",
            "-no-metrics",
            "-crash-report-mode", "disabled",
            "-netfast",
        ]
        if !s.audio { p.arguments! += ["-no-audio"] }
        if !s.quickBoot { p.arguments! += ["-no-snapshot"] }
        if !s.vulkan { p.arguments! += ["-feature", "-Vulkan"] }
        if wipeData { p.arguments! += ["-wipe-data"] }
        // vCPU threads inherit this, which keeps them on the performance cores.
        p.qualityOfService = s.highPriority ? .userInteractive : .default
        p.environment = Self.environment
        p.standardOutput = logHandle
        p.standardError = logHandle
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let exited = proc.processIdentifier
            Task { @MainActor in self?.engineExited(pid: exited, status: status) }
        }
        try p.run()
        process = p
        pid = p.processIdentifier
        Self.saveState(State(pid: pid, grpcPort: grpcPort, consolePort: consolePort))
        log("launched engine pid \(pid) grpc \(grpcPort) console \(consolePort)")
    }

    private func waitForBoot() async {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline, phase == .booting {
            if let status = try? await client?.status(), status.booted {
                phase = .ready
                if settings.highPriority {
                    // Keep App Nap and timer coalescing away from nunu while Android runs.
                    activity = ProcessInfo.processInfo.beginActivity(
                        options: [.userInitiated, .latencyCritical], reason: "Running Android")
                }
                await prepareGuest()
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        if phase == .booting { phase = .failed("Android didn't finish booting within 5 minutes.") }
    }

    /// One-time-per-boot guest settings. Idempotent, so quick-boot resumes are fine.
    private func prepareGuest() async {
        // A freshly started private adb server needs a moment to find the device.
        let serial = self.serial
        for _ in 0..<20 {
            let devices = await Self.offPool { Self.adbSync(["devices"]) }
            if devices.contains("\(serial)\tdevice") { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        await applyTweaks(settings)
        onGuestReady?()
    }

    /// Live settings (debloat, animations, game mode) take effect without a reboot.
    func updateLive(_ s: DeviceSettings) async {
        let device = self.settings
        var merged = s
        // Keep boot-time fields as the engine actually runs them.
        merged.width = device.width; merged.height = device.height; merged.density = device.density
        merged.ramMB = device.ramMB; merged.cores = device.cores; merged.refreshRate = device.refreshRate
        settings = merged
        guard phase == .ready else { return }
        await applyTweaks(merged)
    }

    /// Factory reset: stop, then boot once with -wipe-data (drops the snapshot too).
    func reset(_ s: DeviceSettings) async {
        await stop()
        try? FileManager.default.removeItem(at: Paths.avdDir.appendingPathComponent("snapshots"))
        await start(s, wipeData: true)
    }

    /// "37.2.13" style revisions of the installed engine and system image.
    nonisolated static var versions: (engine: String, image: String) {
        func rev(_ dir: URL) -> String {
            let text = (try? String(contentsOf: dir.appendingPathComponent("source.properties"), encoding: .utf8)) ?? ""
            let line = text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("Pkg.Revision=") }
            return line.map { String($0.dropFirst("Pkg.Revision=".count)) } ?? "?"
        }
        return (rev(Paths.sdk.appendingPathComponent("emulator")),
                rev(Paths.sdk.appendingPathComponent(AVD.systemImage)))
    }

    /// Address external tools (Android Studio, scrcpy, adb) can connect to.
    var adbAddress: String { consolePort == 0 ? "not running" : "127.0.0.1:\(consolePort + 1)" }

    // MARK: - Stop

    /// Graceful stop: the engine saves its quick-boot snapshot and exits.
    func stop() async {
        guard pid != 0 else { phase = .stopped; return }
        phaseClock = Date()
        phase = .stopping
        // The console's `kill` is what writes the quick-boot snapshot; gRPC
        // SHUTDOWN powers Android off and the engine gives up on saving.
        let port = consolePort
        let viaConsole = await Self.offPool { Self.console(port: port, "kill") }
        if !viaConsole { await client?.shutdown() }
        log("stop requested (\(viaConsole ? "console" : "gRPC")), waiting for snapshot save")
        if !(await waitForExit(seconds: 150)) {
            log("engine didn't exit; sending SIGTERM")
            kill(pid, SIGTERM)
            if !(await waitForExit(seconds: 5)) { kill(pid, SIGKILL) }
        }
        teardown()
        phase = .stopped
    }

    func restart(_ settings: DeviceSettings) async {
        await stop()
        await start(settings)
    }

    private func waitForExit(seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !Self.isAlive(pid) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return !Self.isAlive(pid)
    }

    /// Only the engine we're running right now counts: a restart's previous engine
    /// (or its watchdog) reporting late must not take the new one down.
    private func engineExited(pid exited: pid_t, status: Int32) {
        guard exited == pid, phase != .stopping, phase != .stopped else { return }
        teardown()
        phase = .failed("Android stopped unexpectedly (exit \(status)). See ~/.nunu/logs/engine.log")
    }

    /// A re-attached engine isn't our child, so poll it.
    private func startWatchdog() {
        watchdog?.cancel()
        let watched = pid
        watchdog = Task { [weak self] in
            while true {
                // A cancelled sleep throws: stop here instead of checking a dead pid.
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if !Self.isAlive(watched) {
                    self?.engineExited(pid: watched, status: -1)
                    return
                }
            }
        }
    }

    private func teardown() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        watchdog?.cancel()
        client?.close()
        client = nil
        process = nil
        pid = 0
        try? FileManager.default.removeItem(at: Paths.engineState)
    }

    // MARK: - adb

    @discardableResult
    func shell(_ command: String) async -> String {
        await adb(["shell", command])
    }

    @discardableResult
    func adb(_ args: [String]) async -> String {
        let serial = self.serial
        return await Self.offPool { Self.adbSync(["-s", serial] + args) }
    }

    /// Blocking work (adb, sockets) runs here, never on Swift's cooperative pool:
    /// that pool is tiny, and a few blocked threads stall every task in nunu,
    /// including the input stream and the foreground watcher.
    private nonisolated static let blockingQueue = DispatchQueue(label: "nunu.blocking", qos: .userInitiated, attributes: .concurrent)

    nonisolated static func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            blockingQueue.async { cont.resume(returning: work()) }
        }
    }

    nonisolated static func adbSync(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = Paths.adb
        p.arguments = args
        p.environment = environment
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_SDK_ROOT"] = Paths.sdk.path
        env["ANDROID_HOME"] = Paths.sdk.path
        env["ANDROID_AVD_HOME"] = Paths.avdHome.path
        env["ANDROID_ADB_SERVER_PORT"] = "\(adbServerPort)"
        // Default is 20 s, too short to write a large RAM snapshot on quit.
        env["ANDROID_EMULATOR_WAIT_TIME_BEFORE_KILL"] = "120"
        // Keep the engine's own adb lookups on nunu's adb, not whatever is in PATH.
        env["PATH"] = Paths.sdk.appendingPathComponent("platform-tools").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }

    /// Sends one command to the engine's telnet console, authenticating with
    /// the token the engine keeps in ~/.emulator_console_auth_token.
    nonisolated static func console(port: Int, _ command: String) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard connected else { return false }

        func readReply() -> String {
            var buf = [UInt8](repeating: 0, count: 4096)
            var out = ""
            while !out.contains("OK") && !out.contains("KO") {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { break }
                out += String(decoding: buf[..<n], as: UTF8.self)
            }
            return out
        }
        func send(_ line: String) { _ = line.withCString { write(fd, $0, strlen($0)) } }

        _ = readReply()  // banner
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".emulator_console_auth_token")
        if let token = try? String(contentsOf: tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            send("auth \(token)\r\n")
            guard readReply().contains("OK") else { return false }
        }
        send("\(command)\r\n")
        return readReply().contains("OK")
    }

    // MARK: - Helpers

    private func log(_ s: String) {
        FileHandle.standardError.write(Data("nunu: \(s)\n".utf8))
    }

    nonisolated static func isAlive(_ pid: pid_t) -> Bool {
        pid > 0 && kill(pid, 0) == 0
    }

    nonisolated static func isEngineProcess(_ pid: pid_t) -> Bool {
        guard isAlive(pid) else { return false }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        let path = String(cString: buf)
        return path.hasPrefix(Paths.sdk.path) && path.contains("qemu-system")
    }

    /// logcat watchers (`adb shell logcat …`) from a nunu that crashed or was killed
    /// get re-parented to launchd and would stream forever; stop them.
    private static func killOrphanedWatchers() {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let out = Pipe()
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        for line in text.split(whereSeparator: \.isNewline) {
            let cols = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard cols.count == 3, cols[1] == "1", cols[2].hasPrefix(Paths.adb.path),
                  cols[2].contains(" shell logcat "), let pid = pid_t(cols[0]) else { continue }
            kill(pid, SIGTERM)
        }
    }

    /// Finds nunu's engine through the discovery file it writes on start, for when
    /// nunu lost its own state file (e.g. crashed mid-restart).
    private static func discoverRunningEngine() -> State? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/TemporaryItems/avd/running")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where name.hasPrefix("pid_") && name.hasSuffix(".ini") {
            guard let pid = pid_t(name.dropFirst(4).dropLast(4)), isEngineProcess(pid),
                  let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { continue }
            var fields: [String: String] = [:]
            for line in text.split(whereSeparator: \.isNewline) {
                let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { fields[kv[0]] = kv[1] }
            }
            guard fields["avd.dir"] == Paths.avdDir.path,
                  let grpc = fields["grpc.port"].flatMap(Int.init),
                  let console = fields["port.serial"].flatMap(Int.init) else { continue }
            return State(pid: pid, grpcPort: grpc, consolePort: console)
        }
        return nil
    }

    private static func loadState() -> State? {
        guard let data = try? Data(contentsOf: Paths.engineState) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private static func saveState(_ s: State) {
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: Paths.engineState) }
    }

    /// Console ports are even, adb is console+1; both must be free. Stay inside
    /// 5554...5584 so adb's own emulator scan finds us too.
    private static func freeConsolePort() -> Int {
        for port in stride(from: 5580, through: 5554, by: -2) where isFree(port) && isFree(port + 1) {
            return port
        }
        return 5580
    }

    private static func freePort(startingAt start: Int) -> Int {
        (start..<(start + 100)).first(where: isFree) ?? start
    }

    private static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

extension Engine.Phase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
