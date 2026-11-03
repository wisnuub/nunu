import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = Engine()
    private var settings = DeviceSettings.load()
    private var player: PlayerWindowController?
    private var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private lazy var installer = SDKInstaller()
    private var pendingAPKs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        if SDKInstaller.isInstalled { startPlayer() } else { showSetup() }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// APKs double-clicked or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        let apks = urls.filter(Sideloader.accepts)
        guard !apks.isEmpty else { return }
        if let player { player.sideload(apks) } else { pendingAPKs += apks }
    }

    /// Quitting saves Android's state (quick boot) so the next launch resumes in seconds.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        FileHandle.standardError.write(Data("nunu: quit requested (engine \(engine.phase))\n".utf8))
        switch engine.phase {
        case .stopped, .failed: return .terminateNow
        default:
            Task {
                await engine.stop()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    // MARK: Windows

    private func showSetup() {
        let view = SetupView(installer: installer) { [weak self] in
            self?.setupWindow?.close()
            self?.setupWindow = nil
            self?.startPlayer()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Set up nunu"
        w.styleMask = [.titled, .closable]
        w.center()
        w.makeKeyAndOrderFront(nil)
        setupWindow = w
    }

    private func startPlayer() {
        let p = PlayerWindowController(engine: engine, settings: settings)
        p.onOpenSettings = { [weak self] in self?.showSettings(nil) }
        engine.onPhase = { [weak p] phase in p?.engineChanged(phase) }
        engine.onClientReady = { [weak p] client in p?.attach(client) }
        engine.onGuestReady = { [weak self, weak p] in
            p?.guestReady()
            if let apks = self?.pendingAPKs, !apks.isEmpty {
                self?.pendingAPKs = []
                p?.sideload(apks)
            }
        }
        player = p
        p.showWindow(nil)
        let settings = self.settings
        Task { await engine.start(settings) }
    }

    @objc func showSettings(_ sender: Any?) {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(
            settings: settings,
            running: engine.settings,
            adbAddress: engine.adbAddress,
            onApply: { [weak self] new, restart in
                guard let self else { return }
                self.settings = new
                self.player?.apply(settings: new)
                self.settingsWindow?.close()
                Task {
                    if restart { await self.engine.restart(new) } else { await self.engine.updateLive(new) }
                }
            },
            onCancel: { [weak self] in self?.settingsWindow?.close() },
            onReset: { [weak self] in
                guard let self else { return }
                self.settingsWindow?.close()
                let s = self.settings
                Task { await self.engine.reset(s) }
            },
            onEditControls: { [weak self] in
                self?.settingsWindow?.close()
                self?.player?.toggleControls()
            },
            onSetUpFingerprint: { [weak self] in
                self?.settingsWindow?.close()
                self?.player?.setUpFingerprint()
            }
        )
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "nunu Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsWindow = nil }
        }
        settingsWindow = w
    }

    @objc func restartAndroid(_ sender: Any?) {
        let settings = self.settings
        Task { await engine.restart(settings) }
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About nunu", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(showSettings(_:)), ",", target: self))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide nunu", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit nunu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, "nunu"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, "Edit"))

        // Targets resolve through the responder chain to the player window controller.
        let android = NSMenu(title: "Android")
        android.addItem(item("Back", #selector(PlayerWindowController.back), "["))
        android.addItem(item("Home", #selector(PlayerWindowController.home), "H", mods: [.command, .shift]))
        android.addItem(item("Close App", #selector(PlayerWindowController.closeApp), "w"))
        android.addItem(item("Next App", #selector(PlayerWindowController.nextApp), "\t", mods: [.control]))
        android.addItem(item("Previous App", #selector(PlayerWindowController.previousApp), "\t", mods: [.control, .shift]))
        android.addItem(item("Play Store", #selector(PlayerWindowController.playStore), "P", mods: [.command, .shift]))
        android.addItem(item("Install APK…", #selector(PlayerWindowController.installAPK), "o"))
        android.addItem(.separator())
        android.addItem(item("Edit Game Controls", #selector(PlayerWindowController.toggleControls), "k"))
        android.addItem(item("Show Control Hints", #selector(PlayerWindowController.toggleHints), "K", mods: [.command, .shift]))
        android.addItem(item("Screenshot", #selector(PlayerWindowController.screenshot), "s"))
        android.addItem(item("Fingerprint (Touch ID)", #selector(PlayerWindowController.useFingerprint), "T", mods: [.command, .shift]))
        android.addItem(item("Volume Up", #selector(PlayerWindowController.volumeUp), "="))
        android.addItem(item("Volume Down", #selector(PlayerWindowController.volumeDown), "-"))
        android.addItem(.separator())
        android.addItem(item("Restart Android", #selector(restartAndroid(_:)), "", target: self))
        main.addItem(submenu(android, "Android"))

        let view = NSMenu(title: "View")
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", mods: [.command, .control]))
        main.addItem(submenu(view, "View"))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu(window, "Window"))
        NSApp.windowsMenu = window
        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String,
                      mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key.lowercased())
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        i.submenu = menu
        return i
    }
}
