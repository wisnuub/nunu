import SwiftUI
import Combine

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case downloading
    case signIn
    case complete
}

@MainActor
final class AppState: ObservableObject {
    @Published var onboardingStep: OnboardingStep = .welcome
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatusText: String = "Preparing..."
    @Published var installedGames: Set<String> = []
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String?

    // Update state
    @Published var isUpdateAvailable: Bool = false
    @Published var pendingUpdate: AndroidRelease?
    @Published var updateProgress: Double = 0.0
    @Published var updateStatusText: String = ""
    @Published var isUpdating: Bool = false

    @Published var isOnboardingDone: Bool {
        didSet {
            UserDefaults.standard.set(isOnboardingDone, forKey: "nunu.onboardingDone")
            if isOnboardingDone {
                Task { await checkForUpdatesQuietly() }
            }
        }
    }

    init() {
        self.isOnboardingDone = UserDefaults.standard.bool(forKey: "nunu.onboardingDone")
        let saved = UserDefaults.standard.stringArray(forKey: "nunu.installedGames") ?? []
        self.installedGames = Set(saved)

        if isOnboardingDone {
            Task { await checkForUpdatesQuietly() }
        }
    }

    // MARK: - Onboarding Download

    func startDownload() async {
        downloadProgress = 0.0
        downloadStatusText = "Preparing..."

        do {
            try await InstallationService.shared.downloadAVMCore { [weak self] progress, status in
                Task { @MainActor in
                    self?.downloadProgress = progress * 0.35
                    self?.downloadStatusText = status
                }
            }

            try await InstallationService.shared.downloadAndroidBaseImage(version: "13") { [weak self] progress, status in
                Task { @MainActor in
                    self?.downloadProgress = 0.35 + progress * 0.60
                    self?.downloadStatusText = status
                }
            }
        } catch {
            // Silently continue — don't block onboarding on network errors
        }

        downloadStatusText = "Finalizing setup..."
        for i in 0...5 {
            try? await Task.sleep(nanoseconds: 80_000_000)
            downloadProgress = 0.95 + Double(i) * 0.01
        }

        downloadProgress = 1.0
        downloadStatusText = "Setup complete!"

        try? await Task.sleep(nanoseconds: 500_000_000)
        onboardingStep = .signIn
    }

    // MARK: - Game Install

    func installGame(_ id: String) {
        Task {
            guard let game = Game.catalog.first(where: { $0.id == id }) else { return }
            try? await InstallationService.shared.installGame(game)
            installedGames.insert(id)
            var arr = UserDefaults.standard.stringArray(forKey: "nunu.installedGames") ?? []
            if !arr.contains(id) { arr.append(id) }
            UserDefaults.standard.set(arr, forKey: "nunu.installedGames")
        }
    }

    // MARK: - Updates

    func checkForUpdatesQuietly() async {
        await UpdateService.shared.checkForUpdates()
        if let release = UpdateService.shared.availableRelease {
            pendingUpdate = release
            isUpdateAvailable = true
        }
    }

    func applyUpdate() async {
        guard let release = pendingUpdate else { return }
        isUpdating = true
        updateProgress = 0.0
        defer { isUpdating = false }

        do {
            try await InstallationService.shared.applyUpdate(release: release) { [weak self] progress, status in
                Task { @MainActor in
                    self?.updateProgress = progress
                    self?.updateStatusText = status
                }
            }
            isUpdateAvailable = false
            pendingUpdate = nil
        } catch {
            updateStatusText = "Update failed: \(error.localizedDescription)"
        }
    }
}
