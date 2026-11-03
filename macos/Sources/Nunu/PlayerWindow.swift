import AppKit
import EmulatorAPI

/// The one window nunu shows while playing: the Android display, a slim
/// toolbar on the right, the controls overlay and a boot/status cover.
@MainActor
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private let engine: Engine
    private var settings: DeviceSettings
    private let renderer: FrameRenderer
    private let keyMapper = KeyMapper()
    private let frameView: FrameView
    private let overlay: ControlsOverlay
    private let toolbar = NSStackView()
    private let cover = NSVisualEffectView()
    private let coverLabel = NSTextField(labelWithString: "Starting Android…")
    private let spinner = NSProgressIndicator()
    private let fpsLabel = NSTextField(labelWithString: "")

    private var streamTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var shared: SharedFrame?
    private let stats = FrameStats()

    var onOpenSettings: (() -> Void)?

    private static let toolbarWidth: CGFloat = 44

    init(engine: Engine, settings: DeviceSettings) {
        guard let renderer = FrameRenderer() else { fatalError("Metal is unavailable") }
        self.engine = engine
        self.settings = settings
        self.renderer = renderer
        frameView = FrameView(renderer: renderer, keyMapper: keyMapper)
        overlay = ControlsOverlay(keyMapper: keyMapper, frameView: frameView)

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "nunu"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildContent()
        sizeWindow(animate: false)
        window.center()
        window.setFrameAutosaveName("nunu.player")

        keyMapper.onAimChanged = { [weak self] on in
            self?.window?.title = on ? "nunu · Mouse-look (Esc or ` to release)" : "nunu"
            self?.overlay.needsDisplay = true
        }
        overlay.onEditingChanged = { [weak self] _ in self?.overlay.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildContent() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor

        for v in [frameView, overlay, toolbar, cover, fpsLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }

        toolbar.orientation = .vertical
        toolbar.alignment = .centerX
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(white: 0.11, alpha: 1).cgColor
        let items: [(String, String, Selector)] = [
            ("chevron.backward", "Back", #selector(back)),
            ("circle", "Home", #selector(home)),
            ("square.on.square", "Recent apps", #selector(recents)),
            ("", "", #selector(noop)),
            ("bag", "Play Store", #selector(playStore)),
            ("keyboard", "Game controls (⌘K)", #selector(toggleControls)),
            ("camera", "Screenshot (⌘S)", #selector(screenshot)),
            ("speaker.wave.3", "Volume up", #selector(volumeUp)),
            ("speaker.wave.1", "Volume down", #selector(volumeDown)),
            ("", "", #selector(noop)),
            ("gearshape", "Settings (⌘,)", #selector(openSettings)),
        ]
        for (symbol, tip, action) in items {
            if symbol.isEmpty {
                let line = NSBox()
                line.boxType = .separator
                line.widthAnchor.constraint(equalToConstant: 24).isActive = true
                toolbar.addArrangedSubview(line)
                continue
            }
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!,
                             target: self, action: action)
            b.isBordered = false
            b.contentTintColor = NSColor(white: 0.85, alpha: 1)
            b.toolTip = tip
            b.symbolConfiguration = .init(pointSize: 15, weight: .regular)
            b.widthAnchor.constraint(equalToConstant: 32).isActive = true
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            toolbar.addArrangedSubview(b)
        }

        cover.material = .hudWindow
        cover.blendingMode = .withinWindow
        cover.state = .active
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        coverLabel.textColor = .white
        coverLabel.font = .systemFont(ofSize: 14, weight: .medium)
        coverLabel.alignment = .center
        coverLabel.maximumNumberOfLines = 4
        coverLabel.preferredMaxLayoutWidth = 420
        let coverStack = NSStackView(views: [spinner, coverLabel])
        coverStack.orientation = .vertical
        coverStack.spacing = 12
        coverStack.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(coverStack)

        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        fpsLabel.textColor = .systemGreen
        fpsLabel.isHidden = !settings.showFPS

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.widthAnchor.constraint(equalToConstant: Self.toolbarWidth),

            frameView.topAnchor.constraint(equalTo: root.topAnchor),
            frameView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            frameView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            frameView.trailingAnchor.constraint(equalTo: toolbar.leadingAnchor),

            overlay.topAnchor.constraint(equalTo: frameView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),

            cover.topAnchor.constraint(equalTo: frameView.topAnchor),
            cover.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
            coverStack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            coverStack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),

            fpsLabel.topAnchor.constraint(equalTo: frameView.topAnchor, constant: 6),
            fpsLabel.leadingAnchor.constraint(equalTo: frameView.leadingAnchor, constant: 8),
        ])
        window?.contentView = root
        window?.initialFirstResponder = frameView
    }

    /// Fit the device at 1 point per guest pixel when it fits, else scale to ~85% of the screen.
    private func sizeWindow(animate: Bool) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.size
        let device = CGSize(width: settings.width, height: settings.height)
        let chrome = window.frameRect(forContentRect: .zero).size
        let maxW = visible.width * 0.85 - Self.toolbarWidth - chrome.width
        let maxH = visible.height * 0.85 - chrome.height
        let scale = min(1, maxW / device.width, maxH / device.height)
        let content = CGSize(width: (device.width * scale).rounded() + Self.toolbarWidth,
                             height: (device.height * scale).rounded())
        var frame = window.frameRect(forContentRect: CGRect(origin: window.frame.origin, size: content))
        frame.origin.y += window.frame.height - frame.height
        window.setFrame(frame, display: true, animate: animate)
        window.contentMinSize = CGSize(width: 320 + Self.toolbarWidth, height: 180)
    }

    /// Keep the picture's aspect ratio while dragging the window edge.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let size = renderer.frameSize.width > 0 ? renderer.frameSize : CGSize(width: settings.width, height: settings.height)
        let content = sender.contentRect(forFrameRect: CGRect(origin: .zero, size: frameSize)).size
        let pictureW = max(content.width - Self.toolbarWidth, 100)
        let h = (pictureW * size.height / size.width).rounded()
        let fitted = CGSize(width: pictureW + Self.toolbarWidth, height: h)
        return sender.frameRect(forContentRect: CGRect(origin: .zero, size: fitted)).size
    }

    /// Closing the player quits nunu, keeping the window up while Android saves.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        frameView.releaseInput()
    }

    // MARK: Engine wiring

    func attach(_ client: EngineClient) {
        frameView.client = client
        streamTask?.cancel()
        shared = renderer.prepare(width: settings.width, height: settings.height)
        guard let shared else {
            show(status: "Couldn't allocate the shared display buffer.", spinning: false)
            return
        }
        let renderer = self.renderer
        let stats = self.stats
        let handle = shared.handle
        let fpsLabel = self.fpsLabel
        // 0 x 0 asks for the native size, so rotation never downscales the picture.
        streamTask = Task.detached {
            while !Task.isCancelled {
                do {
                    try await client.streamFrames(handle: handle, width: 0, height: 0) { image in
                        let fw = Int(image.format.width), fh = Int(image.format.height)
                        guard fw > 0, fh > 0 else { return }
                        renderer.frameArrived(width: fw, height: fh)
                        if let fps = stats.tick() {
                            Task { @MainActor in fpsLabel.stringValue = "\(fps) fps" }
                            if FrameStats.logToStderr {
                                FileHandle.standardError.write(Data("nunu: \(fps) fps \(fw)x\(fh) seq \(image.seq)\n".utf8))
                            }
                        }
                    }
                } catch {}
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func engineChanged(_ phase: Engine.Phase) {
        switch phase {
        case .launching: show(status: "Starting Android…", spinning: true)
        case .booting: show(status: "Booting Android…", spinning: true)
        case .ready:
            hideCover()
            startFocusWatcher()
        case .stopping:
            stopStreaming()
            show(status: "Saving Android state so it resumes in seconds next time…", spinning: true)
        case .stopped:
            stopStreaming()
            show(status: "Android is off.", spinning: false)
        case .failed(let msg):
            stopStreaming()
            show(status: msg, spinning: false)
        }
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        focusTask?.cancel()
        focusTask = nil
        frameView.releaseInput()
    }

    private func show(status: String, spinning: Bool) {
        coverLabel.stringValue = status
        spinner.isHidden = !spinning
        cover.isHidden = false
    }

    private func hideCover() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            cover.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.cover.isHidden = true
            self?.cover.alphaValue = 1
        }
        window?.makeFirstResponder(frameView)
    }

    /// Swap key maps when the foreground app changes.
    private func startFocusWatcher() {
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.window?.isKeyWindow == true, !self.overlay.editing {
                    let out = await self.engine.shell("dumpsys activity activities | grep -m1 topResumedActivity")
                    if let pkg = Self.package(fromActivityLine: out) {
                        self.keyMapper.load(package: pkg)
                        self.overlay.needsDisplay = true
                    }
                }
                try? await Task.sleep(for: .seconds(2))
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

    func apply(settings: DeviceSettings) {
        let resized = settings.width != self.settings.width || settings.height != self.settings.height
        self.settings = settings
        fpsLabel.isHidden = !settings.showFPS
        if resized { sizeWindow(animate: true) }
    }

    // MARK: Toolbar actions

    @objc private func noop() {}
    @objc func back() { frameView.client?.press("GoBack") }
    @objc func home() { frameView.client?.press("GoHome") }
    @objc func recents() { frameView.client?.press("AppSwitch") }
    @objc func volumeUp() { frameView.client?.press("AudioVolumeUp") }
    @objc func volumeDown() { frameView.client?.press("AudioVolumeDown") }
    @objc func openSettings() { onOpenSettings?() }

    @objc func playStore() {
        Task { await engine.shell("monkey -p com.android.vending -c android.intent.category.LAUNCHER 1") }
    }

    @objc func toggleControls() {
        overlay.setEditing(!overlay.editing)
    }

    @objc func toggleHints() {
        overlay.showHints.toggle()
    }

    @objc func screenshot() {
        Task {
            Paths.ensure(Paths.screenshots)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let remote = "/data/local/tmp/nunu-shot.png"
            let local = Paths.screenshots.appendingPathComponent("nunu \(stamp).png")
            await engine.shell("screencap -p \(remote)")
            await engine.adb(["pull", remote, local.path])
            await engine.shell("rm \(remote)")
            if FileManager.default.fileExists(atPath: local.path) {
                NSWorkspace.shared.activateFileViewerSelecting([local])
            }
        }
    }
}

/// Counts delivered frames; returns a new per-second figure once a second.
final class FrameStats: @unchecked Sendable {
    static let logToStderr = ProcessInfo.processInfo.environment["NUNU_LOG_FPS"] == "1"
    private let lock = NSLock()
    private var count = 0
    private var windowStart = CACurrentMediaTime()

    func tick() -> Int? {
        lock.lock(); defer { lock.unlock() }
        count += 1
        let now = CACurrentMediaTime()
        guard now - windowStart >= 1 else { return nil }
        let fps = Int((Double(count) / (now - windowStart)).rounded())
        count = 0
        windowStart = now
        return fps
    }
}
