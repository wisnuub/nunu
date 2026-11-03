import AppKit
import Foundation
import UniformTypeIdentifiers

/// Installs Android apps from files on the Mac: plain .apk, split bundles
/// (.apks from SAI/bundletool, .xapk from APKPure, incl. OBB game data).
@MainActor
final class Sideloader {
    static let extensions: Set<String> = ["apk", "apks", "xapk"]

    private let engine: Engine
    /// File name -> running adb process, shown as Home download tiles.
    private(set) var active: [String: Process] = [:]
    var onChange: (() -> Void)?
    var onFinished: ((_ name: String, _ error: String?) -> Void)?

    init(engine: Engine) {
        self.engine = engine
    }

    static func accepts(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    func choose(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.title = "Install Android apps"
        panel.prompt = "Install"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.extensions.compactMap { UTType(filenameExtension: $0) }
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.install(panel.urls)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }

    func install(_ urls: [URL]) {
        for url in urls where Self.accepts(url) {
            Task { await install(url) }
        }
    }

    func cancel(_ name: String) {
        active[name]?.terminate()
    }

    private func install(_ url: URL) async {
        let name = url.deletingPathExtension().lastPathComponent
        guard active[name] == nil else { return }
        let serial = engine.serial
        let ext = url.pathExtension.lowercased()

        // Unpack bundles into a scratch folder: split APKs + optional OBB data.
        var apks = [url]
        var obbs: [(file: URL, pkg: String)] = []
        var scratch: URL?
        if ext != "apk" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nunu-sideload-\(UUID().uuidString)")
            scratch = dir
            guard await Self.unzip(url, to: dir) else {
                onFinished?(name, "Couldn't open \(url.lastPathComponent). APKMirror .apkm files are encrypted and not supported.")
                return
            }
            let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
            apks = files.filter { $0.pathExtension.lowercased() == "apk" }
            obbs = files.filter { $0.pathExtension.lowercased() == "obb" }.map { ($0, $0.deletingLastPathComponent().lastPathComponent) }
        }
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        guard !apks.isEmpty else {
            onFinished?(name, "\(url.lastPathComponent) doesn't contain any APK.")
            return
        }

        let args = apks.count == 1
            ? ["-s", serial, "install", "-r", apks[0].path]
            : ["-s", serial, "install-multiple", "-r"] + apks.map(\.path)
        let p = Process()
        p.executableURL = Paths.adb
        p.arguments = args
        p.environment = Engine.environment
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        active[name] = p
        onChange?()
        let output: String = await Engine.offPool {
            do { try p.run() } catch { return "adb failed to start" }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let cancelled = p.terminationReason == .uncaughtSignal

        if output.contains("Success") {
            for obb in obbs {
                let dest = "/sdcard/Android/obb/\(obb.pkg)/"
                await engine.shell("mkdir -p \(dest)")
                await engine.adb(["push", obb.file.path, dest])
            }
        }
        active[name] = nil
        onChange?()
        if cancelled { return }
        if output.contains("Success") {
            onFinished?(name, nil)
        } else {
            let reason = output.split(whereSeparator: \.isNewline).last { $0.contains("Failure") || $0.contains("INSTALL_") }
            onFinished?(name, Self.explain(reason.map(String.init) ?? output))
        }
    }

    /// Turns adb's failure codes into something readable.
    private static func explain(_ raw: String) -> String {
        if raw.contains("NO_MATCHING_ABIS") {
            return "This APK is built only for Intel/x86 phones. nunu runs real ARM64 Android, so it needs an ARM (arm64-v8a) version."
        }
        if raw.contains("UPDATE_INCOMPATIBLE") {
            return "A different build of this app is already installed (signed by someone else). Uninstall it first."
        }
        if raw.contains("INSUFFICIENT_STORAGE") {
            return "Android is out of space. Settings > Advanced > Storage for apps can make it bigger."
        }
        if raw.contains("OLDER_SDK") || raw.contains("DEPRECATED_SDK_VERSION") {
            return "This app needs a different Android version than nunu's Android 14."
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unzip(_ zip: URL, to dir: URL) async -> Bool {
        await Engine.offPool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, dir.path]
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
    }
}

/// The player's root view: accepts APK files dragged in from Finder.
final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func apkURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(Sideloader.accepts)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        apkURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = apkURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
