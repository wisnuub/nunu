import Foundation
import LocalAuthentication

/// Mac Touch ID as Android's fingerprint sensor. Watches the guest's fingerprint
/// HAL; when Android asks for a finger, macOS asks for Touch ID, and a successful
/// match becomes a touch on Android's virtual sensor.
@MainActor
final class TouchIDBridge {
    private let engine: Engine
    var enabled = true
    private var watcher: Task<Void, Never>?
    private var context: LAContext?
    private var enrolling = false

    /// The finger id nunu enrolls and touches with.
    private static let finger: Int32 = 1

    init(engine: Engine) {
        self.engine = engine
    }

    func start() {
        watcher?.cancel()
        // Only lines from now on: an old AUTHENTICATING line must not pop a prompt.
        watcher = engine.streamLogcat("-T \"$(date +'%m-%d %H:%M:%S.000')\" -s fingerprint-service.ranchu") { [weak self] line in
            await self?.handle(line)
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        context?.invalidate()
        context = nil
        enrolling = false
    }

    /// Strings come from the ranchu fingerprint HAL (vendor image).
    private func handle(_ line: String) {
        if line.contains("AUTHENTICATING operationId") {
            guard enabled else { return }
            Task { await authenticate() }
        } else if line.contains("ENROLLING_START") {
            guard enabled else { return }
            Task { await enroll() }
        } else if line.contains("onEnrollmentProgress"), line.contains("left=0)") {
            enrolling = false
        } else if line.contains("onError(CANCELED") || line.contains("onSessionClosed") {
            // Android dismissed its prompt; take the Mac one down too.
            enrolling = false
            context?.invalidate()
            context = nil
        }
    }

    /// Toolbar button / menu: answer whatever fingerprint prompt Android is showing.
    func touchSensor() async {
        guard await confirm("use Touch ID as your Android fingerprint") else { return }
        await tap()
    }

    private func authenticate() async {
        guard context == nil else { return }  // a prompt is already up
        guard await confirm("use your fingerprint in Android") else { return }
        await tap()
    }

    /// Android's setup wants 10–15 separate touches; ask once, then supply them.
    private func enroll() async {
        guard context == nil, !enrolling else { return }
        guard await confirm("add your Touch ID fingerprint to Android") else { return }
        enrolling = true
        for _ in 0..<30 where enrolling {
            await tap()
            try? await Task.sleep(for: .milliseconds(450))
        }
        enrolling = false
    }

    private func tap() async {
        guard let client = engine.client else { return }
        await client.fingerprint(touching: true, id: Self.finger)
        try? await Task.sleep(for: .milliseconds(250))
        await client.fingerprint(touching: false, id: Self.finger)
    }

    /// Touch ID (or the Mac password where there's no sensor).
    private func confirm(_ reason: String) async -> Bool {
        let ctx = LAContext()
        context = ctx
        defer { if context === ctx { context = nil } }
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
