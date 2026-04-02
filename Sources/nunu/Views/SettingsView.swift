import SwiftUI

struct SettingsView: View {
    @AppStorage("nunu.settings.launchOnLogin") private var launchOnLogin = false
    @AppStorage("nunu.settings.androidVersion") private var androidVersion = "13"
    @AppStorage("nunu.settings.ramGB") private var ramGB: Double = 4.0
    @AppStorage("nunu.settings.cpuCores") private var cpuCores: Int = 4
    @AppStorage("nunu.settings.resolution") private var resolution = "1280x720"
    @AppStorage("nunu.settings.fpsCap") private var fpsCap = true

    @EnvironmentObject var appState: AppState
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                PageHeader(title: "Settings", subtitle: "Configure your nunu experience")

                // Updates
                SettingsSection(title: "Android Engine") {
                    UpdateRow()
                }

                // General
                SettingsSection(title: "General") {
                    SettingsToggleRow(
                        icon: "power",
                        title: "Launch on login",
                        subtitle: "Start nunu automatically when you log in",
                        isOn: $launchOnLogin
                    )

                    Divider().background(Color.white.opacity(0.06))

                    SettingsPickerRow(
                        icon: "android",
                        title: "Default Android version",
                        subtitle: "System image used for new instances",
                        selection: $androidVersion,
                        options: [
                            ("Android 11", "11"),
                            ("Android 12", "12"),
                            ("Android 13", "13")
                        ]
                    )
                }

                // Performance
                SettingsSection(title: "Performance") {
                    SettingsSliderRow(
                        icon: "memorychip",
                        title: "RAM allocation",
                        subtitle: "Memory available to the Android environment",
                        value: $ramGB,
                        range: 2...16,
                        step: 1,
                        displayValue: "\(Int(ramGB)) GB"
                    )

                    Divider().background(Color.white.opacity(0.06))

                    SettingsStepperRow(
                        icon: "cpu",
                        title: "CPU cores",
                        subtitle: "Virtual CPUs allocated to the Android environment",
                        value: $cpuCores,
                        range: 1...8
                    )
                }

                // Display
                SettingsSection(title: "Display") {
                    SettingsPickerRow(
                        icon: "display",
                        title: "Resolution",
                        subtitle: "Android display resolution",
                        selection: $resolution,
                        options: [
                            ("720p (1280×720)", "1280x720"),
                            ("1080p (1920×1080)", "1920x1080"),
                            ("1440p (2560×1440)", "2560x1440"),
                            ("Native", "native")
                        ]
                    )

                    Divider().background(Color.white.opacity(0.06))

                    SettingsToggleRow(
                        icon: "speedometer",
                        title: "FPS cap (60 fps)",
                        subtitle: "Limit frame rate to reduce power consumption",
                        isOn: $fpsCap
                    )
                }

                // About
                SettingsSection(title: "About") {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                            Image(systemName: "android")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("nunu")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Android without compromise")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }

                        Spacer()

                        Text("v1.0.0")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(4)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Update Row

private struct UpdateRow: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updateService = UpdateService.shared

    var installedVersion: String {
        updateService.installedVersion() ?? "13.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#5B6EF5"))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: "#5B6EF5").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Android Engine")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Installed: \(installedVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }

                Spacer()

                if updateService.isChecking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(Color(hex: "#5B6EF5"))
                } else if appState.isUpdateAvailable, let release = appState.pendingUpdate {
                    Text("v\(release.version) available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "#F59E0B"))
                } else {
                    Text("Up to date")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.3))
                }

                Button(appState.isUpdateAvailable ? "Update" : "Check") {
                    if appState.isUpdateAvailable {
                        Task { await appState.applyUpdate() }
                    } else {
                        Task { await appState.checkForUpdatesQuietly() }
                    }
                }
                .buttonStyle(AccentButtonStyle(color: appState.isUpdateAvailable ? "#F59E0B" : "#5B6EF5"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Update progress bar
            if appState.isUpdating {
                VStack(spacing: 6) {
                    Divider().background(Color.white.opacity(0.06))

                    HStack {
                        Text(appState.updateStatusText)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(appState.updateProgress * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "#5B6EF5"))
                    }
                    .padding(.horizontal, 16)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * appState.updateProgress, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: appState.updateProgress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct AccentButtonStyle: ButtonStyle {
    let color: String

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: color).opacity(configuration.isPressed ? 0.7 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Settings Components

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .tracking(1.2)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "#5B6EF5"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "#5B6EF5").opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4))
            }

            Spacer()

            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Color(hex: "#5B6EF5"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsPickerRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var selection: String
    let options: [(String, String)]

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "#8B5CF6"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "#8B5CF6").opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4))
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.1) { label, value in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsSliderRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#5B6EF5"))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: "#5B6EF5").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4))
                }

                Spacer()

                Text(displayValue)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#5B6EF5"))
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 42)
                Text("\(Int(range.lowerBound)) GB").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.3))
                Slider(value: $value, in: range, step: step).tint(Color(hex: "#5B6EF5"))
                Text("\(Int(range.upperBound)) GB").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsStepperRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "#8B5CF6"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "#8B5CF6").opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.4))
            }

            Spacer()

            HStack(spacing: 12) {
                Text("\(value) cores")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#8B5CF6"))
                    .frame(width: 72, alignment: .trailing)
                Stepper("", value: $value, in: range).labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
