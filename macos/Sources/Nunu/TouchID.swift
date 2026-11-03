import AppKit
import Foundation
import LocalAuthentication

/// Mac Touch ID as Android's fingerprint sensor. Watches the guest's fingerprint
/// HAL; when Android asks for a finger, macOS asks for Touch ID, and a successful
/// match becomes a touch on Android's virtual sensor.
@MainActor
final class TouchIDBridge {
    private let engine: Engine
    var enabled = true
    /// Short progress note for the tab strip (Macs can't vibrate like a phone's sensor).
    var onNotice: ((String?) -> Void)?

    private var watcher: Task<Void, Never>?
    private var context: LAContext?
    private var enrollActive = false    // the HAL has an enroll session open
    private var authActive = false      // the HAL is waiting for a finger to verify
    private var feeding = false         // our enrollment touch loop is running
    /// Android's setup opens several enroll sessions in a row (find sensor, then
    /// enrolling); one Touch ID approval covers the whole flow.
    private var enrollApprovedUntil = Date.distantPast

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
        Task { await resumePending() }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        context?.invalidate()
        context = nil
        enrollActive = false
        authActive = false
    }

    /// Android may already be waiting (nunu started mid-setup): ask it directly.
    private func resumePending() async {
        let op = await engine.shell("dumpsys fingerprint | grep -m1 'Current operation'")
        if op.contains("EnrollClient") {
            enrollActive = true
            if enabled { await enroll() }
        } else if op.contains("AuthenticationClient") {
            authActive = true
            if enabled { await authenticate() }
        }
    }

    /// Strings come from the ranchu fingerprint HAL (vendor image).
    private func handle(_ line: String) {
        if line.contains("AUTHENTICATING operationId") {
            authActive = true
            if enabled { Task { await authenticate() } }
        } else if line.contains("ENROLLING_START") {
            enrollActive = true
            if enabled { Task { await enroll() } }
        } else if line.contains("onEnrollmentProgress"), let left = Self.number(after: "left=", in: line) {
            if left == 0 {
                enrollActive = false
                NSSound(named: "Glass")?.play()
                notice("Fingerprint added", clearAfter: 3)
            } else {
                NSSound(named: "Tink")?.play()
                notice("Adding fingerprint: \(left) more")
            }
        } else if line.contains("onAuthenticationSucceeded") {
            authActive = false
            notice("Fingerprint accepted", clearAfter: 2)
        } else if line.contains("onError(CANCELED") || line.contains("onSessionClosed") {
            // Android closed its prompt (Cancel, or setup moving to its next screen).
            enrollActive = false
            authActive = false
            context?.invalidate()
            context = nil
        }
    }

    /// Toolbar button / ⇧⌘T: answer whatever Android is waiting for.
    func touchSensor() async {
        if enrollActive {
            await enroll()
        } else {
            guard await confirm("use Touch ID as your Android fingerprint") else { return }
            await tap()
        }
    }

    private func authenticate() async {
        guard context == nil else { return }  // a prompt is already up
        guard await confirm("use your fingerprint in Android") else { return }
        guard authActive else { return }      // Android gave up meanwhile
        await tap()
    }

    /// Touch the sensor until Android says the fingerprint is complete.
    private func enroll() async {
        guard !feeding else { return }
        if Date() > enrollApprovedUntil {
            guard context == nil else { return }
            guard await confirm("add your Touch ID fingerprint to Android") else { return }
            enrollApprovedUntil = Date().addingTimeInterval(180)
        }
        feeding = true
        defer { feeding = false }
        notice("Adding fingerprint…")
        var taps = 0
        // Re-checked after every touch: a follow-up session keeps the loop going.
        while enrollActive, taps < 40 {
            await tap()
            taps += 1
            try? await Task.sleep(for: .milliseconds(650))
        }
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
        NSApp.activate()  // the Touch ID sheet shows over the frontmost app
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    private var clearTask: Task<Void, Never>?

    private func notice(_ text: String, clearAfter seconds: Double? = nil) {
        clearTask?.cancel()
        onNotice?(text)
        guard let seconds else { return }
        clearTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { onNotice?(nil) }
        }
    }

    /// "…left=3)" -> 3
    private static func number(after key: String, in line: String) -> Int? {
        guard let r = line.range(of: key) else { return nil }
        return Int(line[r.upperBound...].prefix { $0.isNumber })
    }
}
