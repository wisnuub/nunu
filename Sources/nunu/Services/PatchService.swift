import Foundation

/// Applies xdelta3 binary patches to Android disk images.
///
/// Patch workflow:
///   1. Download the delta patch file from AVM releases
///   2. Call `xdelta3 -d -s <source> <patch> <output>` via Process()
///   3. Verify SHA-256 of the output matches the manifest
///   4. Atomically replace the old image with the patched image
///
/// If xdelta3 is not available, the caller should fall back to a full image download.
final class PatchService {
    static let shared = PatchService()
    private init() {}

    /// Returns true if xdelta3 is available on PATH or in known Homebrew locations.
    var isXdelta3Available: Bool {
        let candidates = [
            "/opt/homebrew/bin/xdelta3",
            "/usr/local/bin/xdelta3",
            "/usr/bin/xdelta3"
        ]
        if candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return true
        }
        // Check PATH via `which`
        let result = runCommand("/usr/bin/which", args: ["xdelta3"])
        return result.exitCode == 0
    }

    /// Apply `patch` to `source`, writing result to `destination`.
    /// Throws `PatchError.xdelta3NotFound` if xdelta3 is unavailable.
    func applyPatch(source: URL, patch: URL, destination: URL) throws {
        guard let xdelta = findXdelta3() else {
            throw PatchError.xdelta3NotFound
        }

        let result = runCommand(xdelta, args: [
            "-d",           // decode (apply patch)
            "-s", source.path,
            patch.path,
            destination.path
        ])

        guard result.exitCode == 0 else {
            throw PatchError.patchFailed(result.stderr)
        }
    }

    /// Verify SHA-256 of a file against an expected hex string.
    func verifySHA256(file: URL, expected: String) throws {
        let result = runCommand("/usr/bin/shasum", args: ["-a", "256", file.path])
        guard result.exitCode == 0 else {
            throw PatchError.verificationFailed
        }
        let computed = result.stdout.split(separator: " ").first.map(String.init) ?? ""
        guard computed.lowercased() == expected.lowercased() else {
            throw PatchError.checksumMismatch(expected: expected, got: computed)
        }
    }

    // MARK: - Private

    private func findXdelta3() -> String? {
        let candidates = [
            "/opt/homebrew/bin/xdelta3",
            "/usr/local/bin/xdelta3",
            "/usr/bin/xdelta3"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        let result = runCommand("/usr/bin/which", args: ["xdelta3"])
        if result.exitCode == 0 {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private struct CommandResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runCommand(_ executable: String, args: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    enum PatchError: LocalizedError {
        case xdelta3NotFound
        case patchFailed(String)
        case verificationFailed
        case checksumMismatch(expected: String, got: String)

        var errorDescription: String? {
            switch self {
            case .xdelta3NotFound:
                return "xdelta3 not found. Install via Homebrew: brew install xdelta"
            case .patchFailed(let msg):
                return "Patch failed: \(msg)"
            case .verificationFailed:
                return "Could not verify file integrity"
            case .checksumMismatch(let expected, let got):
                return "Checksum mismatch — expected \(expected.prefix(12))… got \(got.prefix(12))…"
            }
        }
    }
}
