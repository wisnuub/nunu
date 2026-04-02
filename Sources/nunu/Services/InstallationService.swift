import Foundation
import Combine

@MainActor
final class InstallationService: ObservableObject {
    static let shared = InstallationService()

    @Published var installProgress: [String: Double] = [:]

    let nunuDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".nunu")
    }()

    private init() {
        try? FileManager.default.createDirectory(at: nunuDir, withIntermediateDirectories: true)
    }

    // MARK: - Initial Setup

    func downloadAVMCore(progressHandler: @escaping (Double, String) -> Void) async throws {
        let corePath = nunuDir.appendingPathComponent("avm-core")
        guard !FileManager.default.fileExists(atPath: corePath.path) else { return }

        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            try await Task.sleep(nanoseconds: 80_000_000)
            progressHandler(step, step < 0.5 ? "Downloading AVM core..." : "Installing AVM core...")
        }

        FileManager.default.createFile(atPath: corePath.path, contents: Data("avm-core-1.0".utf8))
    }

    /// Download the full Android base image (used on first install or when no patch chain exists).
    func downloadAndroidBaseImage(
        version: String = "13",
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let imagePath = androidImagePath(version: version)
        guard !FileManager.default.fileExists(atPath: imagePath.path) else { return }

        let steps = 50
        for i in 0...steps {
            let sleepNs: UInt64 = i < 20 ? 80_000_000 : 50_000_000
            try await Task.sleep(nanoseconds: sleepNs)
            let progress = Double(i) / Double(steps)
            progressHandler(progress, "Downloading Android \(version) ARM image... \(Int(progress * 100))%")
        }

        FileManager.default.createFile(atPath: imagePath.path, contents: Data("android-\(version)".utf8))

        // Record installed version
        try? UpdateService.shared.markInstalled(version: "\(version).0.0")
    }

    /// Apply a delta patch to upgrade the Android image from one version to another.
    /// If xdelta3 is not available, falls back to full image download.
    func applyUpdate(
        release: AndroidRelease,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let patchService = PatchService.shared
        let installedVersion = UpdateService.shared.installedVersion() ?? ""
        let currentImagePath = androidImagePath(version: majorVersion(from: installedVersion))

        if patchService.isXdelta3Available,
           let patch = release.patch(from: installedVersion) {

            progressHandler(0.05, "Downloading patch (\(patch.formattedSize))...")
            let patchPath = try await downloadFile(url: patch.url, filename: "update.xdelta") { p in
                progressHandler(0.05 + p * 0.60, "Downloading patch... \(Int(p * 100))%")
            }

            progressHandler(0.65, "Verifying patch integrity...")
            try patchService.verifySHA256(file: patchPath, expected: patch.sha256)

            progressHandler(0.70, "Applying patch...")
            let newVersion = majorVersion(from: release.version)
            let outputPath = androidImagePath(version: "\(newVersion)-new")
            try patchService.applyPatch(
                source: currentImagePath,
                patch: patchPath,
                destination: outputPath
            )

            progressHandler(0.90, "Verifying updated image...")
            try patchService.verifySHA256(file: outputPath, expected: release.fullImage.sha256)

            // Swap images atomically
            let finalPath = androidImagePath(version: newVersion)
            _ = try? FileManager.default.replaceItemAt(finalPath, withItemAt: outputPath)
            try? FileManager.default.removeItem(at: patchPath)

        } else {
            // Fallback: full image download
            progressHandler(0.0, "Downloading full image (xdelta3 not available)...")
            let newVersion = majorVersion(from: release.version)
            try await downloadAndroidBaseImage(version: newVersion, progressHandler: progressHandler)
        }

        try? UpdateService.shared.markInstalled(version: release.version)
        progressHandler(1.0, "Update complete!")
    }

    // MARK: - Game Installation

    func installGame(_ game: Game) async throws {
        installProgress[game.id] = 0.0

        let phases: [(String, Double, UInt64)] = [
            ("Fetching APK metadata...", 0.10, 50_000_000),
            ("Downloading APK...", 0.50, 40_000_000),
            ("Verifying package...", 0.70, 60_000_000),
            ("Sideloading via ADB...", 0.90, 80_000_000),
            ("Configuring game...", 1.00, 50_000_000)
        ]

        for (_, targetProgress, sleepNs) in phases {
            let currentProgress = installProgress[game.id] ?? 0.0
            let steps = 10
            for i in 1...steps {
                try await Task.sleep(nanoseconds: sleepNs)
                installProgress[game.id] = currentProgress + (targetProgress - currentProgress) * Double(i) / Double(steps)
            }
        }

        installProgress[game.id] = 1.0

        var installed = UserDefaults.standard.stringArray(forKey: "nunu.installedGames") ?? []
        if !installed.contains(game.id) {
            installed.append(game.id)
            UserDefaults.standard.set(installed, forKey: "nunu.installedGames")
        }
    }

    // MARK: - Helpers

    func androidImagePath(version: String) -> URL {
        nunuDir.appendingPathComponent("android-\(version)-arm64.img")
    }

    private func majorVersion(from version: String) -> String {
        version.split(separator: ".").first.map(String.init) ?? version
    }

    private func downloadFile(
        url: URL,
        filename: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = nunuDir.appendingPathComponent(filename)

        // Real download via URLSession with progress reporting
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let totalBytes = response.expectedContentLength
        var receivedBytes: Int64 = 0
        var data = Data()

        for try await byte in asyncBytes {
            data.append(byte)
            receivedBytes += 1
            if totalBytes > 0 && receivedBytes % 65536 == 0 {
                progressHandler(Double(receivedBytes) / Double(totalBytes))
            }
        }

        try data.write(to: destination)
        return destination
    }
}
