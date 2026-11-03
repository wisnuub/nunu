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

    func start(_ settings: DeviceSettings) async {
        guard phase == .stopped || phase.isFailed else { return }
        phaseClock = Date()
        phase = .launching
        Paths.ensure(Paths.logs, Paths.run)

        if let saved = Self.loadState(), Self.isEngineProcess(saved.pid) {
            pid = saved.pid
            grpcPort = saved.grpcPort
            consolePort = saved.consolePort
            log("re-attaching to running engine pid \(pid)")
        } else {
            do {
                try AVD.write(settings)
                try launch()
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

    private func launch() throws {
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
            "-gpu", "host",
            "-no-boot-anim",
            "-no-metrics",
            "-crash-report-mode", "disabled",
            "-netfast",
        ]
        p.environment = Self.environment
        p.standardOutput = logHandle
        p.standardError = logHandle
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in self?.engineExited(status: status) }
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
            let devices = await Task.detached { Self.adbSync(["devices"]) }.value
            if devices.contains("\(serial)\tdevice") { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        await shell("settings put system screen_off_timeout 2147483647")
        await shell("svc power stayon true")
        await shell("settings put global stay_on_while_plugged_in 7")
    }

    // MARK: - Stop

    /// Graceful stop: the engine saves its quick-boot snapshot and exits.
    func stop() async {
        guard pid != 0 else { phase = .stopped; return }
        phaseClock = Date()
        phase = .stopping
        // The console's `kill` is what writes the quick-boot snapshot; gRPC
        // SHUTDOWN powers Android off and the engine gives up on saving.
        let port = consolePort
        let viaConsole = await Task.detached { Self.console(port: port, "kill") }.value
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

    private func engineExited(status: Int32) {
        guard phase != .stopping, phase != .stopped else { return }
        teardown()
        phase = .failed("Android stopped unexpectedly (exit \(status)). See ~/.nunu/logs/engine.log")
    }

    /// A re-attached engine isn't our child, so poll it.
    private func startWatchdog() {
        watchdog?.cancel()
        let watched = pid
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if !Self.isAlive(watched) {
                    self?.engineExited(status: -1)
                    return
                }
            }
        }
    }

    private func teardown() {
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
        return await Task.detached { Self.adbSync(["-s", serial] + args) }.value
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
