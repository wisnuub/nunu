import CryptoKit
import Foundation

/// Downloads the Android VM engine, platform-tools and the Google Play system
/// image straight from Google's SDK repository. Replaces sdkmanager, so no Java.
@MainActor
final class SDKInstaller: ObservableObject {
    struct Package: Identifiable {
        let id: String          // SDK path, e.g. "emulator"
        let name: String
        let url: URL
        let size: Int64
        let sha1: String
        let license: String
        /// Directory inside the zip that holds the package, and where it goes.
        let zipRoot: String
        let destination: URL
    }

    enum Stage: Equatable {
        case idle, fetchingCatalog, ready, installing, done
        case failed(String)
    }

    @Published var stage: Stage = .idle
    @Published var packages: [Package] = []
    @Published var licenses: [(id: String, text: String)] = []
    @Published var progress: [String: Double] = [:]
    @Published var status = ""

    static let repo = URL(string: "https://dl.google.com/android/repository/")!
    static let systemImageRepo = URL(string: "https://dl.google.com/android/repository/sys-img/google_apis_playstore/")!
    static let systemImagePath = "system-images;android-34;google_apis_playstore;arm64-v8a"

    static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: Paths.emulator.path)
            && fm.isExecutableFile(atPath: Paths.adb.path)
            && fm.fileExists(atPath: Paths.sdk.appendingPathComponent(AVD.systemImage + "system.img").path)
    }

    var totalBytes: Int64 { packages.reduce(0) { $0 + $1.size } }

    // MARK: Catalog

    func fetchCatalog() async {
        stage = .fetchingCatalog
        do {
            async let main = Self.document(Self.repo.appendingPathComponent("repository2-3.xml"))
            async let images = Self.document(Self.systemImageRepo.appendingPathComponent("sys-img2-3.xml"))
            let (repoDoc, imageDoc) = try await (main, images)

            var found: [Package] = []
            var licenseIDs: [String] = []
            func add(_ pkg: (Package, String)?) throws {
                guard let (p, lic) = pkg else { throw InstallError.missing }
                found.append(p)
                if !licenseIDs.contains(lic) { licenseIDs.append(lic) }
            }
            try add(Self.pick(repoDoc, path: "emulator", base: Self.repo, name: "Android VM engine",
                              zipRoot: "emulator", into: Paths.sdk.appendingPathComponent("emulator"),
                              arch: "aarch64"))
            try add(Self.pick(repoDoc, path: "platform-tools", base: Self.repo, name: "Android platform tools",
                              zipRoot: "platform-tools", into: Paths.sdk.appendingPathComponent("platform-tools")))
            try add(Self.pick(imageDoc, path: Self.systemImagePath, base: Self.systemImageRepo,
                              name: "Android 14 with Google Play", zipRoot: "arm64-v8a",
                              into: Paths.sdk.appendingPathComponent(AVD.systemImage)))

            licenses = licenseIDs.compactMap { id in
                let text = Self.licenseText(id, in: [repoDoc, imageDoc])
                return text.map { (id, $0) }
            }
            packages = found
            stage = .ready
        } catch {
            stage = .failed("Couldn't reach Google's Android repository: \(error.localizedDescription)")
        }
    }

    private static func document(_ url: URL) async throws -> XMLDocument {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try XMLDocument(data: data)
    }

    /// Newest stable (channel-0) archive of `path` for this Mac.
    private static func pick(_ doc: XMLDocument, path: String, base: URL, name: String,
                             zipRoot: String, into destination: URL, arch: String? = nil) -> (Package, String)? {
        let nodes = (try? doc.nodes(forXPath: "//*[local-name()='remotePackage'][@path='\(path)']")) ?? []
        var best: (rev: [Int], pkg: Package, license: String)?
        for case let el as XMLElement in nodes {
            guard text(el, "channelRef/@ref") ?? "channel-0" == "channel-0" else { continue }
            let rev = ["major", "minor", "micro"].map { Int(text(el, "revision/\($0)") ?? "0") ?? 0 }
            let archives = (try? el.nodes(forXPath: "*[local-name()='archives']/*[local-name()='archive']")) ?? []
            for case let a as XMLElement in archives {
                let os = text(a, "host-os")
                let hostArch = text(a, "host-arch")
                guard os == nil || os == "macosx" else { continue }
                if let arch, let hostArch, hostArch != arch { continue }
                guard let file = text(a, "complete/url"), let sha = text(a, "complete/checksum"),
                      let size = Int64(text(a, "complete/size") ?? "") else { continue }
                let license = text(el, "uses-license/@ref") ?? "android-sdk-license"
                let pkg = Package(id: path, name: name, url: base.appendingPathComponent(file), size: size,
                                  sha1: sha, license: license, zipRoot: zipRoot, destination: destination)
                if best == nil || rev.lexicographicallyPrecedes(best!.rev) == false {
                    best = (rev, pkg, license)
                }
            }
        }
        return best.map { ($0.pkg, $0.license) }
    }

    private static func text(_ el: XMLElement, _ path: String) -> String? {
        // local-name() so the repository's namespace prefixes don't matter
        let xp = path.split(separator: "/").map { step in
            step.hasPrefix("@") ? String(step) : "*[local-name()='\(step)']"
        }.joined(separator: "/")
        return (try? el.nodes(forXPath: xp))?.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func licenseText(_ id: String, in docs: [XMLDocument]) -> String? {
        for doc in docs {
            if let node = (try? doc.nodes(forXPath: "//*[local-name()='license'][@id='\(id)']"))?.first {
                return node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: Install

    func install() async {
        stage = .installing
        let staging = Paths.sdk.appendingPathComponent(".staging", isDirectory: true)
        Paths.ensure(Paths.sdk, staging)
        do {
            let free = (try? Paths.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage ?? .max
            // zips + unpacked images + an 8 GB data partition headroom
            let needed = totalBytes * 3 + 10 * (1 << 30)
            if free < needed {
                throw InstallError.disk(needed: needed, free: free)
            }
            for pkg in packages {
                // unpack() moves the finished directory into place in one step,
                // so an existing source.properties means a complete package.
                let marker = pkg.destination.appendingPathComponent("source.properties")
                if FileManager.default.fileExists(atPath: marker.path) {
                    progress[pkg.id] = 1
                    continue
                }
                status = "Downloading \(pkg.name)…"
                let zip = try await download(pkg, to: staging)
                status = "Verifying \(pkg.name)…"
                try await Self.verify(zip, sha1: pkg.sha1)
                status = "Unpacking \(pkg.name)…"
                try await Self.unpack(zip, root: pkg.zipRoot, to: pkg.destination, staging: staging)
                try? FileManager.default.removeItem(at: zip)
                progress[pkg.id] = 1
            }
            try? FileManager.default.removeItem(at: staging)
            status = "Ready"
            stage = .done
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func download(_ pkg: Package, to dir: URL) async throws -> URL {
        let target = dir.appendingPathComponent(pkg.url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        let id = pkg.id
        let size = pkg.size
        let delegate = DownloadDelegate(destination: target) { [weak self] written in
            Task { @MainActor in self?.progress[id] = Double(written) / Double(max(size, 1)) * 0.95 }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { cont in
            delegate.continuation = cont
            session.downloadTask(with: pkg.url).resume()
        }
    }

    nonisolated private static func verify(_ file: URL, sha1 expected: String) async throws {
        try await Task.detached {
            let h = try FileHandle(forReadingFrom: file)
            defer { try? h.close() }
            var sha = Insecure.SHA1()
            while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty {
                sha.update(data: chunk)
            }
            let hex = sha.finalize().map { String(format: "%02x", $0) }.joined()
            guard hex == expected.lowercased() else { throw InstallError.checksum }
        }.value
    }

    nonisolated private static func unpack(_ zip: URL, root: String, to destination: URL, staging: URL) async throws {
        try await Task.detached {
            let out = staging.appendingPathComponent("unpack-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: out) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, out.path]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw InstallError.unpack }
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: out.appendingPathComponent(root), to: destination)
        }.value
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let onProgress: (Int64) -> Void
        var continuation: CheckedContinuation<URL, Error>?

        init(destination: URL, onProgress: @escaping (Int64) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
            onProgress(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            do {
                guard status == 200 else { throw InstallError.http }
                // `location` is deleted when this returns, so move it now.
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

    enum InstallError: LocalizedError {
        case missing, http, checksum, unpack
        case disk(needed: Int64, free: Int64)

        var errorDescription: String? {
            switch self {
            case .missing: return "Google's repository doesn't list a package nunu needs."
            case .http: return "The download failed. Check your connection and try again."
            case .checksum: return "A download was corrupted (checksum mismatch). Try again."
            case .unpack: return "Couldn't unpack a downloaded package."
            case .disk(let needed, let free):
                let f = ByteCountFormatter()
                return "Not enough disk space: nunu needs about \(f.string(fromByteCount: needed)), "
                    + "\(f.string(fromByteCount: free)) is free."
            }
        }
    }
}
