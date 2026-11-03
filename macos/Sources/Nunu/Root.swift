import Foundation

/// Manages KernelSU root for nunu: fetches the custom KernelSU + SUSFS kernel and
/// the KernelSU manager app, installs the manager, and applies a device profile as
/// a `resetprop` module so root stays hidden.
///
/// The toggle itself lives in `DeviceSettings.rootEnabled`: when on, `Engine`
/// boots `Paths.ksuKernel` instead of the stock `kernel-ranchu`. This service only
/// has to make sure the kernel + manager are present and the profile module matches.
@MainActor
final class RootManager: ObservableObject {
    enum Stage: Equatable {
        case idle, downloading, installing, ready
        case failed(String)
    }

    @Published var stage: Stage = .idle
    @Published var progress: Double = 0
    @Published var status = ""
    /// Refreshed from the guest; nil until we've checked.
    @Published var managerInstalled: Bool?
    @Published var rootActive: Bool?

    /// The custom kernel this build of nunu expects. The CI publishes an asset
    /// named exactly `kernel-ranchu` so it drops straight into place.
    static let kernelRepo = "wisnuub/nunu-kernel"
    static let kernelAsset = "kernel-ranchu"
    /// KernelSU-Next pairs with SUSFS for hiding; its manager APK ships per release.
    static let managerRepo = "KernelSU-Next/KernelSU-Next"
    static let managerPackage = "com.rifsxd.ksunext"

    var kernelReady: Bool { FileManager.default.isReadableFile(atPath: Paths.ksuKernel.path) }

    // MARK: Download

    /// Fetches the kernel and the manager APK into `~/.nunu/root`. Idempotent:
    /// files already present are left alone.
    func downloadKit() async {
        stage = .downloading
        progress = 0
        Paths.ensure(Paths.rootKit)
        do {
            if !kernelReady {
                status = "Finding the KernelSU kernel…"
                let url = try await Self.latestAsset(repo: Self.kernelRepo) { $0 == Self.kernelAsset }
                status = "Downloading KernelSU kernel…"
                try await download(url, to: Paths.ksuKernel) { [weak self] f in self?.progress = f * 0.6 }
            }
            if !FileManager.default.isReadableFile(atPath: Paths.ksuManagerAPK.path) {
                status = "Finding the KernelSU manager…"
                // Skip the "-spoofed" build: it installs under a random package, so
                // our status check (which looks for `managerPackage`) wouldn't see it.
                let url = try await Self.latestAsset(repo: Self.managerRepo) {
                    $0.hasSuffix(".apk") && !$0.contains("spoofed")
                }
                status = "Downloading KernelSU manager…"
                try await download(url, to: Paths.ksuManagerAPK) { [weak self] f in self?.progress = 0.6 + f * 0.4 }
            }
            progress = 1
            status = "Kernel and manager ready"
            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
            status = ""
        }
    }

    // MARK: Guest-side install

    /// Installs the KernelSU manager app. Safe to call on any boot (it's an
    /// ordinary APK); it only shows root once the KernelSU kernel is running.
    func installManager(serial: String) async {
        guard FileManager.default.isReadableFile(atPath: Paths.ksuManagerAPK.path) else {
            stage = .failed("Download the KernelSU kit first.")
            return
        }
        stage = .installing
        status = "Installing KernelSU manager…"
        let apk = Paths.ksuManagerAPK.path
        let out = await Engine.offPool { Engine.adbSync(["-s", serial, "install", "-r", "-g", apk]) }
        if out.contains("Success") {
            managerInstalled = true
            status = "KernelSU manager installed"
            stage = .ready
        } else {
            stage = .failed("Manager install failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Checks whether the manager is present and whether root is actually granted
    /// (i.e. the KernelSU kernel booted and `su` yields uid 0).
    func refreshStatus(serial: String) async {
        let (pkgs, whoami) = await Engine.offPool {
            (Engine.adbSync(["-s", serial, "shell", "pm", "list", "packages", Self.managerPackage]),
             Engine.adbSync(["-s", serial, "shell", "su", "-c", "id"]))
        }
        managerInstalled = pkgs.contains(Self.managerPackage)
        rootActive = whoami.contains("uid=0")
    }

    // MARK: Device profile (resetprop module)

    /// Builds a KernelSU module that spoofs the chosen device's build props and
    /// installs it, then asks for a reboot so it applies at post-fs-data. Needs an
    /// already-rooted boot (`refreshStatus` → rootActive).
    func applyProfile(_ profile: DeviceProfile, serial: String) async {
        guard rootActive == true else {
            stage = .failed("Turn on root and reboot once before setting a device profile.")
            return
        }
        stage = .installing
        status = "Applying \(profile.name)…"
        do {
            let zip = try buildProfileModule(profile)
            let remote = "/data/local/tmp/\(zip.lastPathComponent)"
            _ = await Engine.offPool { Engine.adbSync(["-s", serial, "push", zip.path, remote]) }
            let install = await Engine.offPool {
                Engine.adbSync(["-s", serial, "shell", "su", "-c", "/data/adb/ksud module install \(remote)"])
            }
            guard install.lowercased().contains("success") || install.contains("Installing") else {
                throw RootError.moduleInstall(install.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            status = "\(profile.name) applied — reboot to take effect"
            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Writes a minimal KernelSU/Magisk module (`module.prop` + `system.prop`) and
    /// zips it. `system.prop` is resetprop'd automatically at boot.
    private func buildProfileModule(_ profile: DeviceProfile) throws -> URL {
        let dir = Paths.rootKit.appendingPathComponent("profile-module", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let moduleProp = """
        id=nunu_device_profile
        name=nunu Device Profile (\(profile.name))
        version=1
        versionCode=1
        author=nunu
        description=Spoofs the device build fingerprint to \(profile.name) so root stays hidden.
        """
        try moduleProp.write(to: dir.appendingPathComponent("module.prop"), atomically: true, encoding: .utf8)

        let systemProp = profile.props.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        try systemProp.write(to: dir.appendingPathComponent("system.prop"), atomically: true, encoding: .utf8)

        let zip = Paths.rootKit.appendingPathComponent("nunu_device_profile.zip")
        try? FileManager.default.removeItem(at: zip)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-r", zip.path, "."]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw RootError.zip }
        return zip
    }

    // MARK: GitHub + download helpers

    private struct GHRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let assets: [Asset]
    }

    /// Newest release asset of `repo` whose name satisfies `match`.
    private static func latestAsset(repo: String, match: (String) -> Bool) async throws -> URL {
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=5")!
        var req = URLRequest(url: api)
        req.setValue("nunu", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        let releases = try JSONDecoder().decode([GHRelease].self, from: data)
        for release in releases {
            if let asset = release.assets.first(where: { match($0.name) }) {
                return asset.browser_download_url
            }
        }
        throw RootError.assetMissing(repo)
    }

    private func download(_ url: URL, to dest: URL, onProgress: @escaping @MainActor (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: dest)
        let delegate = DownloadDelegate(destination: dest) { frac in Task { @MainActor in onProgress(frac) } }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            delegate.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let onProgress: (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?

        init(destination: URL, onProgress: @escaping (Double) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite total: Int64) {
            if total > 0 { onProgress(Double(totalBytesWritten) / Double(total)) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            do {
                guard status == 200 else { throw RootError.http(status) }
                try FileManager.default.moveItem(at: location, to: destination)
                continuation?.resume(returning: destination)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    enum RootError: LocalizedError {
        case assetMissing(String), http(Int), zip, moduleInstall(String)
        var errorDescription: String? {
            switch self {
            case .assetMissing(let repo): return "No matching release asset in \(repo). Has the kernel build published yet?"
            case .http(let code): return "Download failed (HTTP \(code))."
            case .zip: return "Couldn't package the device-profile module."
            case .moduleInstall(let out): return "Module install failed: \(out)"
            }
        }
    }
}
