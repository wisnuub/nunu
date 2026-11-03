import AppKit
import EmulatorAPI
import SwiftUI

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
    private let library = LibraryModel()
    private let tabs = TabsModel()
    private let barHeight = TabStripView.titleBarHeight
    private lazy var tabHost: NSHostingView<TabStripView> = {
        let host = NSHostingView(rootView: TabStripView(model: tabs, height: barHeight))
        host.safeAreaRegions = []
        return host
    }()
    private var fpsTimer: Timer?
    private lazy var touchID = TouchIDBridge(engine: engine)
    private lazy var homeView = NSHostingView(rootView: HomeView(model: library))
    private(set) var homeVisible = false

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

        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "nunu"
        // App tabs live in the title bar, next to the traffic lights.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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
            self?.tabs.status = on ? "Mouse-look · Esc or ` to release" : ""
            self?.overlay.needsDisplay = true
        }
        overlay.onEditingChanged = { [weak self] _ in self?.overlay.needsDisplay = true }
        overlay.showHints = settings.showHints
        keyMapper.sensitivityScale = settings.aimSensitivity
        touchID.enabled = settings.touchID
        wireLibrary()
        wireTabs()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildContent() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor

        homeView.isHidden = true
        for v in [tabHost, frameView, overlay, homeView, toolbar, cover] as [NSView] {
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
            ("", "", #selector(noop)),
            ("bag", "Play Store", #selector(playStore)),
            ("keyboard", "Game controls (⌘K)", #selector(toggleControls)),
            ("touchid", "Fingerprint: Touch ID (⇧⌘T)", #selector(useFingerprint)),
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

        NSLayoutConstraint.activate([
            tabHost.topAnchor.constraint(equalTo: root.topAnchor),
            tabHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabHost.heightAnchor.constraint(equalToConstant: barHeight),

            toolbar.topAnchor.constraint(equalTo: tabHost.bottomAnchor),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.widthAnchor.constraint(equalToConstant: Self.toolbarWidth),

            frameView.topAnchor.constraint(equalTo: tabHost.bottomAnchor),
            frameView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            frameView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            frameView.trailingAnchor.constraint(equalTo: toolbar.leadingAnchor),

            overlay.topAnchor.constraint(equalTo: frameView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),

            homeView.topAnchor.constraint(equalTo: frameView.topAnchor),
            homeView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
            homeView.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            homeView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),

            cover.topAnchor.constraint(equalTo: frameView.topAnchor),
            cover.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
            coverStack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            coverStack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),

        ])
        window?.contentView = root
        window?.initialFirstResponder = frameView
    }

    /// Fit the device at 1 point per guest pixel when it fits, else scale to ~85% of the screen.
    /// The content view spans the whole window (tabs sit in the title bar).
    private func sizeWindow(animate: Bool) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.size
        let device = CGSize(width: settings.width, height: settings.height)
        let maxW = visible.width * 0.85 - Self.toolbarWidth
        let maxH = visible.height * 0.85 - barHeight
        let scale = min(1, maxW / device.width, maxH / device.height)
        let content = CGSize(width: (device.width * scale).rounded() + Self.toolbarWidth,
                             height: (device.height * scale).rounded() + barHeight)
        var frame = window.frameRect(forContentRect: CGRect(origin: window.frame.origin, size: content))
        frame.origin.y += window.frame.height - frame.height
        window.setFrame(frame, display: true, animate: animate)
        window.contentMinSize = CGSize(width: 480 + Self.toolbarWidth, height: 270 + barHeight)
    }

    /// Keep the picture's aspect ratio while dragging the window edge.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let size = renderer.frameSize.width > 0 ? renderer.frameSize : CGSize(width: settings.width, height: settings.height)
        let content = sender.contentRect(forFrameRect: CGRect(origin: .zero, size: frameSize)).size
        let pictureW = max(content.width - Self.toolbarWidth, 100)
        let h = (pictureW * size.height / size.width).rounded()
        let fitted = CGSize(width: pictureW + Self.toolbarWidth, height: h + barHeight)
        return sender.frameRect(forContentRect: CGRect(origin: .zero, size: fitted)).size
    }

    /// What macOS would do on a title-bar double-click (System Settings > Desktop & Dock).
    private func titleBarDoubleClicked() {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.miniaturize(nil)
        case "None": break
        default: window?.zoom(nil)   // "Maximize" / "Fill" / unset
        }
    }

    /// Zoom target: the biggest window that keeps the picture's aspect ratio on this
    /// screen, so the game fills it with no black bars. zoom() toggles back by itself.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? newFrame
        let size = renderer.frameSize.width > 0 ? renderer.frameSize : CGSize(width: settings.width, height: settings.height)
        let aspect = size.height / size.width
        let pictureW = min(visible.width - Self.toolbarWidth, (visible.height - barHeight) / aspect).rounded(.down)
        let content = CGSize(width: pictureW + Self.toolbarWidth, height: (pictureW * aspect).rounded() + barHeight)
        let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: content))
        return CGRect(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2,
                      width: frame.width, height: frame.height)
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
        startFPSTimer()
        let handle = shared.handle
        // 0 x 0 asks for the native size, so rotation never downscales the picture.
        streamTask = Task.detached {
            while !Task.isCancelled {
                do {
                    try await client.streamFrames(handle: handle, width: 0, height: 0) { image in
                        let fw = Int(image.format.width), fh = Int(image.format.height)
                        guard fw > 0, fh > 0 else { return }
                        renderer.frameArrived(width: fw, height: fh)
                        stats.record()
                    }
                } catch {}
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    /// Frames only arrive when the picture changes, so a still screen really is 0 fps;
    /// count over a sliding second and say "idle" instead of a confusing 0.
    private func startFPSTimer() {
        fpsTimer?.invalidate()
        var ticks = 0
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let fps = self.stats.fps()
                // Shown in the tab strip so it never covers Android's status bar.
                let text = self.settings.showFPS && !self.homeVisible ? (fps == 0 ? "idle" : "\(fps) fps") : ""
                if self.tabs.fps != text { self.tabs.fps = text }
                ticks += 1
                if FrameStats.logToStderr, ticks % 4 == 0, fps > 0 {
                    FileHandle.standardError.write(Data("nunu: \(fps) fps \(Int(self.renderer.frameSize.width))x\(Int(self.renderer.frameSize.height))\n".utf8))
                }
            }
        }
    }

    func engineChanged(_ phase: Engine.Phase) {
        switch phase {
        case .launching: show(status: "Starting Android…", spinning: true)
        case .booting: show(status: "Booting Android…", spinning: true)
        case .ready:
            hideCover()
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
        touchID.stop()
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

    /// adb can reach the guest: follow the foreground app from now on.
    func guestReady() {
        focusTask?.cancel()
        focusTask = engine.watchForeground { [weak self] pkg in self?.foregroundChanged(pkg) }
        touchID.enabled = settings.touchID
        touchID.start()
        Task {
            tabs.sync(running: await engine.runningApps())
            if let pkg = await engine.foregroundPackage() { foregroundChanged(pkg) }
        }
    }

    /// Swap key maps per app, and cover Android's launcher with nunu Home.
    private func foregroundChanged(_ pkg: String) {
        FileHandle.standardError.write(Data("nunu: foreground \(pkg)\n".utf8))
        if transientPackages.contains(pkg) {
            // A dialog or sign-in screen: show it (never leave it behind Home), keep the
            // game's controls, and credit the tab of the app whose task it's in.
            setHome(visible: false)
            if tabs.active == nil || tabs.active == "" {
                Task {
                    let owner = await engine.recentTasks().first?.pkg
                    if let owner, !transientPackages.contains(owner) { tabs.activate(owner) } else { tabs.showOther() }
                }
            }
            return
        }
        if pkg == androidLauncher {
            tabs.showHome()
            setHome(visible: true)
        } else {
            tabs.activate(pkg)
            setHome(visible: false)
            keyMapper.load(package: pkg)
            overlay.needsDisplay = true
        }
    }

    private func setHome(visible: Bool) {
        guard visible != homeVisible else { return }
        homeVisible = visible
        if visible {
            frameView.releaseInput()
            if overlay.editing { overlay.setEditing(false) }
            homeView.isHidden = false
            window?.makeFirstResponder(homeView)
            Task { await library.refresh() }
        } else {
            library.opening = nil
            homeView.isHidden = true
            window?.makeFirstResponder(frameView)
        }
    }

    /// Runs `action` (which brings an app to the front) while Home stays up with an
    /// "Opening…" note; the foreground event then swaps Home out, so Android's own
    /// launcher never flashes in between.
    private func open(_ name: String, _ action: @escaping () async -> Void) {
        if homeVisible { library.opening = name }
        Task {
            await action()
            try? await Task.sleep(for: .seconds(8))
            if library.opening == name { library.opening = nil }  // nothing came up; drop the spinner
        }
    }

    private func title(for pkg: String) -> String {
        tabs.tabs.first { $0.id == pkg }?.title
            ?? library.installed.first { $0.id == pkg }?.title
            ?? library.featured.first { $0.id == pkg }?.title
            ?? systemAppInfo[pkg]?.name
            ?? LibraryModel.fallbackTitle(pkg)
    }

    private func wireTabs() {
        let engine = self.engine
        tabs.onHome = { [weak self] in self?.home() }
        tabs.onTitleBarDoubleClick = { [weak self] in self?.titleBarDoubleClicked() }
        tabs.onSelect = { [weak self] pkg in
            guard let self else { return }
            if pkg == self.tabs.active, !self.homeVisible { return }
            self.open(self.title(for: pkg)) { await engine.launchApp(pkg) }
        }
        tabs.onClose = { pkgs in
            Task { await engine.closeApps(pkgs) }
        }
    }

    private func wireLibrary() {
        let engine = self.engine
        library.listApps = { await engine.userApps() }
        library.onLaunch = { [weak self] pkg in
            guard let self else { return }
            self.open(self.title(for: pkg)) {
                if engine.settings.gameMode { await engine.shell("cmd game mode performance \(pkg) >/dev/null 2>&1") }
                await engine.launchApp(pkg)
            }
        }
        library.onStorePage = { [weak self] pkg in
            self?.open("Play Store") { await engine.openStorePage(pkg) }
        }
        library.onPlayStore = { [weak self] in
            self?.open("Play Store") { await engine.openPlayStore() }
        }
        library.onAndroidSettings = { [weak self] in
            self?.open("Android settings") { await engine.openAndroidSettings() }
        }
        library.onNunuSettings = { [weak self] in self?.onOpenSettings?() }
        library.onEditControls = { [weak self] pkg in self?.editControls(for: pkg) }
        library.onUninstall = { [weak self] pkg in
            Task {
                await engine.uninstall(pkg)
                await self?.library.refresh()
            }
        }
    }

    /// Opens the game, then the controls editor on top of it.
    func editControls(for pkg: String) {
        let engine = self.engine
        open(title(for: pkg)) { await engine.launchApp(pkg) }
        Task {
            // Wait for the game to come to the front, then open the editor over it.
            for _ in 0..<40 where homeVisible || tabs.active != pkg {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard tabs.active == pkg else { return }
            try? await Task.sleep(for: .seconds(1))
            overlay.setEditing(true)
        }
    }

    func apply(settings: DeviceSettings) {
        let resized = settings.width != self.settings.width || settings.height != self.settings.height
        self.settings = settings
        overlay.showHints = settings.showHints
        keyMapper.sensitivityScale = settings.aimSensitivity
        touchID.enabled = settings.touchID
        if resized { sizeWindow(animate: true) }
    }

    // MARK: Toolbar actions

    @objc private func noop() {}
    @objc func back() { frameView.client?.press("GoBack") }
    @objc func home() {
        frameView.client?.press("GoHome")
        tabs.showHome()
        setHome(visible: true)
    }
    @objc func closeApp() { tabs.closeActive() }
    @objc func useFingerprint() { Task { await touchID.touchSensor() } }

    func setUpFingerprint() {
        let engine = self.engine
        open("fingerprint setup") { await engine.shell("am start -a android.settings.BIOMETRIC_ENROLL >/dev/null 2>&1") }
    }
    @objc func nextApp() { tabs.cycle(by: 1) }
    @objc func previousApp() { tabs.cycle(by: -1) }
    @objc func volumeUp() { frameView.client?.press("AudioVolumeUp") }
    @objc func volumeDown() { frameView.client?.press("AudioVolumeDown") }
    @objc func openSettings() { onOpenSettings?() }

    @objc func playStore() {
        let engine = self.engine
        open("Play Store") { await engine.openPlayStore() }
    }

    @objc func toggleControls() {
        if homeVisible { return }  // controls belong to a game, not Home
        overlay.setEditing(!overlay.editing)
    }

    @objc func toggleHints() {
        settings.showHints.toggle()
        settings.save()
        overlay.showHints = settings.showHints
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

/// Timestamps of recently delivered frames, for a sliding one-second FPS figure.
final class FrameStats: @unchecked Sendable {
    static let logToStderr = ProcessInfo.processInfo.environment["NUNU_LOG_FPS"] == "1"
    private let lock = NSLock()
    private var times: [CFTimeInterval] = []

    /// Called on the stream thread for every delivered frame.
    func record() {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        times.append(now)
        if times.count > 256 { times.removeFirst(times.count - 256) }
    }

    /// Frames delivered during the last second.
    func fps() -> Int {
        let cutoff = CACurrentMediaTime() - 1
        lock.lock(); defer { lock.unlock() }
        times.removeAll { $0 < cutoff }
        return times.count
    }
}
