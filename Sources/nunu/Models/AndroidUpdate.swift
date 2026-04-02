import Foundation

/// Decoded from AVM's update-manifest.json in GitHub releases
struct UpdateManifest: Decodable {
    let schema: Int
    let android: AndroidManifest
    let avm: AVMManifest

    struct AndroidManifest: Decodable {
        let latest: String
        let releases: [AndroidRelease]
    }

    struct AVMManifest: Decodable {
        let latest: String
    }
}

struct AndroidRelease: Decodable {
    let version: String
    let releaseNotes: String
    let fullImage: ImageAsset
    let patches: [ImagePatch]

    /// Returns the best patch to apply from `currentVersion`, or nil if none exists
    func patch(from currentVersion: String) -> ImagePatch? {
        patches.first { $0.from == currentVersion && $0.to == version }
    }

    struct ImageAsset: Decodable {
        let url: URL
        let size: Int64
        let sha256: String
    }
}

struct ImagePatch: Decodable {
    let from: String
    let to: String
    let url: URL
    let size: Int64
    let sha256: String

    /// Human-readable download size
    var formattedSize: String {
        let mb = Double(size) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        }
        return String(format: "%.0f MB", mb)
    }
}

/// Represents what nunu has locally
struct InstalledAndroid {
    let version: String
    let imagePath: URL
}
