import Foundation

/// Checks AVM's GitHub releases for Android image updates.
/// AVM publishes an `update-manifest.json` asset in each release.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var isChecking = false
    @Published var availableRelease: AndroidRelease?
    @Published var checkError: String?
    @Published var lastChecked: Date?

    private let avmReleasesAPI = URL(string: "https://api.github.com/repos/wisnuub/AVM/releases/latest")!
    private let nunuDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nunu")

    private init() {}

    /// Fetch the manifest from AVM's latest GitHub release.
    func checkForUpdates() async {
        isChecking = true
        checkError = nil
        defer {
            isChecking = false
            lastChecked = Date()
        }

        do {
            let manifest = try await fetchManifest()
            let installed = installedVersion()

            if installed == nil || manifest.android.latest != installed {
                availableRelease = manifest.android.releases.first {
                    $0.version == manifest.android.latest
                }
            } else {
                availableRelease = nil
            }
        } catch {
            checkError = error.localizedDescription
        }
    }

    /// Returns the currently installed Android version string, or nil if not installed.
    func installedVersion() -> String? {
        let versionFile = nunuDir.appendingPathComponent("android-version.txt")
        return try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves the installed version marker.
    func markInstalled(version: String) throws {
        let versionFile = nunuDir.appendingPathComponent("android-version.txt")
        try version.write(to: versionFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func fetchManifest() async throws -> UpdateManifest {
        var request = URLRequest(url: avmReleasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.networkFailure
        }

        // Find the update-manifest.json asset URL
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let assets = json["assets"] as? [[String: Any]],
            let manifestAsset = assets.first(where: { ($0["name"] as? String) == "update-manifest.json" }),
            let urlString = manifestAsset["browser_download_url"] as? String,
            let manifestURL = URL(string: urlString)
        else {
            throw UpdateError.manifestNotFound
        }

        let (manifestData, _) = try await URLSession.shared.data(from: manifestURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(UpdateManifest.self, from: manifestData)
    }

    enum UpdateError: LocalizedError {
        case networkFailure
        case manifestNotFound
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .networkFailure: return "Could not reach update server"
            case .manifestNotFound: return "Update manifest not found in release"
            case .checksumMismatch: return "Downloaded file is corrupt — checksum mismatch"
            }
        }
    }
}
