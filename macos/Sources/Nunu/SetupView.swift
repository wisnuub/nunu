import SwiftUI

/// First run: explain, show Google's licenses, download the engine and image.
struct SetupView: View {
    @ObservedObject var installer: SDKInstaller
    var onDone: () -> Void
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to nunu").font(.largeTitle.bold())
                Text("Android runs directly on your Mac's Apple silicon: native ARM code under Apple's "
                     + "Hypervisor.framework, with games drawn by the Mac's GPU through Metal.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch installer.stage {
            case .idle, .fetchingCatalog:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking Google's Android repository…")
                }
                Spacer()
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack {
                    Spacer()
                    Button("Try Again") { Task { await retry() } }.keyboardShortcut(.defaultAction)
                }
            case .ready:
                packageList
                licenseBox
                Toggle("I accept the license agreements above", isOn: $accepted)
                HStack {
                    Text("Download size: \(ByteCountFormatter.string(fromByteCount: installer.totalBytes, countStyle: .file))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Install") { Task { await installer.install() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!accepted)
                }
            case .installing, .done:
                packageList
                Text(installer.status).foregroundStyle(.secondary)
                Spacer()
                if installer.stage == .done {
                    HStack {
                        Spacer()
                        Button("Start Android") { onDone() }.keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 620, height: 560)
        .task { if installer.stage == .idle { await installer.fetchCatalog() } }
    }

    private var packageList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(installer.packages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pkg.name)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: pkg.size, countStyle: .file))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    if installer.stage != .ready {
                        ProgressView(value: installer.progress[pkg.id] ?? 0)
                    }
                }
            }
        }
    }

    private var licenseBox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(installer.licenses, id: \.id) { lic in
                    Text(lic.id).font(.headline)
                    Text(lic.text).font(.system(size: 11)).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func retry() async {
        if installer.packages.isEmpty { await installer.fetchCatalog() } else { await installer.install() }
    }
}
