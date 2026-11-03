import EmulatorAPI
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf

typealias Ctl = Android_Emulation_Control_EmulatorController

/// Thin wrapper over the engine's gRPC control API. Input goes through one
/// long-lived client stream so a touch costs a single HTTP/2 DATA frame.
final class EngineClient: @unchecked Sendable {
    private let grpc: GRPCClient<HTTP2ClientTransport.Posix>
    private let api: Ctl.Client<HTTP2ClientTransport.Posix>
    private let input: AsyncStream<Android_Emulation_Control_InputEvent>
    private let inputSink: AsyncStream<Android_Emulation_Control_InputEvent>.Continuation
    private var tasks: [Task<Void, Never>] = []

    init(port: Int) throws {
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(address: "127.0.0.1", port: port),
            transportSecurity: .plaintext,
            // The engine starts listening a few seconds after launch; don't let the
            // default backoff (up to 2 min) leave us idle once it's up.
            config: .defaults {
                $0.backoff = .init(initial: .milliseconds(100), max: .milliseconds(500), multiplier: 1.6, jitter: 0.2)
            }
        )
        grpc = GRPCClient(transport: transport)
        api = Ctl.Client(wrapping: grpc)
        (input, inputSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(512))
    }

    func start() {
        let grpc = self.grpc
        tasks.append(Task.detached { try? await grpc.runConnections() })
        tasks.append(Task.detached { [weak self] in await self?.pumpInput() })
    }

    func close() {
        inputSink.finish()
        grpc.beginGracefulShutdown()
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Status / lifecycle

    func status() async throws -> Android_Emulation_Control_EmulatorStatus {
        try await api.getStatus(Google_Protobuf_Empty(), options: Self.quick)
    }

    /// Graceful shutdown: the engine writes its quick-boot snapshot and exits.
    func shutdown() async {
        var state = Android_Emulation_Control_VmRunState()
        state.state = .shutdown
        _ = try? await api.setVmState(state, options: Self.quick)
    }

    func reset() async {
        var state = Android_Emulation_Control_VmRunState()
        state.state = .reset
        _ = try? await api.setVmState(state, options: Self.quick)
    }

    private static var quick: CallOptions {
        var o = CallOptions.defaults
        o.timeout = .seconds(3)
        return o
    }

    // MARK: - Frames

    /// Streams frames into a client-owned shared-memory file. `onFrame` fires once
    /// per guest frame, after the pixels have landed in the mapping.
    func streamFrames(handle: String, width: Int, height: Int,
                      onFrame: @escaping @Sendable (Android_Emulation_Control_Image) -> Void) async throws {
        var fmt = Android_Emulation_Control_ImageFormat()
        fmt.format = .rgba8888
        fmt.width = UInt32(width)
        fmt.height = UInt32(height)
        fmt.transport.channel = .mmap
        fmt.transport.handle = handle
        try await api.streamScreenshot(fmt) { response in
            for try await image in response.messages {
                onFrame(image)
            }
        }
    }

    // MARK: - Input

    func send(_ event: Android_Emulation_Control_InputEvent) {
        inputSink.yield(event)
    }

    func touch(_ touches: [Android_Emulation_Control_Touch]) {
        var e = Android_Emulation_Control_InputEvent()
        e.touchEvent.touches = touches
        send(e)
    }

    func key(macKeyCode: UInt16, down: Bool) {
        var e = Android_Emulation_Control_InputEvent()
        if macKeyCode == 0 {
            // kVK_ANSI_A is 0, which protobuf treats as "no key code" and the engine
            // drops. Send A as Linux KEY_A instead.
            e.keyEvent.codeType = .evdev
            e.keyEvent.keyCode = 30
        } else {
            e.keyEvent.codeType = .mac
            e.keyEvent.keyCode = Int32(macKeyCode)
        }
        e.keyEvent.eventType = down ? .keydown : .keyup
        send(e)
    }

    /// Touches (or lifts) Android's virtual fingerprint sensor with finger `id`.
    func fingerprint(touching: Bool, id: Int32 = 1) async {
        var f = Android_Emulation_Control_Fingerprint()
        f.isTouching = touching
        f.touchID = id
        _ = try? await api.sendFingerprint(f, options: Self.quick)
    }

    /// W3C key name, e.g. "GoBack", "GoHome", "AppSwitch", "AudioVolumeUp", "Power".
    func press(_ w3cKey: String) {
        var e = Android_Emulation_Control_InputEvent()
        e.keyEvent.key = w3cKey
        e.keyEvent.eventType = .keypress
        send(e)
    }

    func type(_ text: String) {
        var e = Android_Emulation_Control_InputEvent()
        e.keyEvent.text = text
        e.keyEvent.eventType = .keypress
        send(e)
    }

    /// Keeps one streamInputEvent RPC open; if it drops (engine restarting),
    /// reconnect and keep draining the same queue.
    private func pumpInput() async {
        // One iterator for the queue's whole life; AsyncStream allows only one.
        let queue = IteratorBox(input.makeAsyncIterator())
        while !Task.isCancelled {
            do {
                _ = try await api.streamInputEvent(requestProducer: { writer in
                    while let event = await queue.iterator.next() {
                        try await writer.write(event)
                    }
                })
                return  // queue finished: client closed
            } catch {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}

private final class IteratorBox: @unchecked Sendable {
    var iterator: AsyncStream<Android_Emulation_Control_InputEvent>.Iterator
    init(_ iterator: AsyncStream<Android_Emulation_Control_InputEvent>.Iterator) {
        self.iterator = iterator
    }
}

extension Android_Emulation_Control_Touch {
    static func at(_ x: Int, _ y: Int, id: Int32, down: Bool) -> Self {
        var t = Self()
        t.x = Int32(x)
        t.y = Int32(y)
        t.identifier = id
        t.pressure = down ? 1024 : 0
        t.touchMajor = down ? 6 : 0
        t.expiration = .neverExpire
        return t
    }
}
