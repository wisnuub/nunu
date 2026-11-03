import AppKit
import Metal
import SwiftUI

/// Tabbed settings in the spirit of BlueStacks / MuMu. Device changes need an
/// Android restart; everything else applies live.
struct SettingsView: View {
    @State var settings: DeviceSettings
    let running: DeviceSettings
    let adbAddress: String
    @ObservedObject var root: RootManager
    /// adb serial of the running engine, or nil when Android isn't up.
    let serial: String?
    var onApply: (DeviceSettings, _ restart: Bool) -> Void
    var onCancel: () -> Void
    var onReset: () -> Void
    var onEditControls: () -> Void
    var onSetUpFingerprint: () -> Void

    @State private var confirmReset = false
    @State private var showAllApps = false
    private let versions = Engine.versions
    private let gpuName = MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU"

    private var needsRestart: Bool { settings.needsRestart(comparedTo: running) }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                performance.tabItem { Label("Performance", systemImage: "speedometer") }
                display.tabItem { Label("Display", systemImage: "display") }
                graphics.tabItem { Label("Graphics", systemImage: "cpu") }
                apps.tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                controls.tabItem { Label("Controls", systemImage: "gamecontroller") }
                rootTab.tabItem { Label("Root", systemImage: "lock.shield") }
                advanced.tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            }
            .padding([.horizontal, .top], 12)

            Divider()
            HStack {
                if needsRestart {
                    Label("Android restarts to apply these changes.", systemImage: "arrow.clockwise")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(needsRestart ? "Apply & Restart" : "Apply") {
                    settings.save()
                    onApply(settings, needsRestart)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 620, height: 600)
        .alert("Reset Android?", isPresented: $confirmReset) {
            Button("Erase Everything", role: .destructive, action: onReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases every app, game, account and setting inside Android, like a factory reset. Your nunu settings and controls stay.")
        }
    }

    // MARK: Tabs

    private var performance: some View {
        Form {
            Section {
                Picker("Profile", selection: profileBinding) {
                    Text("Low").tag(DeviceSettings.Profile.low)
                    Text("Balanced").tag(DeviceSettings.Profile.balanced)
                    Text("High").tag(DeviceSettings.Profile.high)
                    Text("Custom").tag(DeviceSettings.Profile.custom)
                }
                .pickerStyle(.segmented)
                Picker("CPU cores", selection: $settings.cores) {
                    ForEach(1...DeviceSettings.hostCores, id: \.self) { Text("\($0) cores").tag($0) }
                }
                Picker("Memory", selection: $settings.ramMB) {
                    ForEach(DeviceSettings.ramChoices, id: \.self) { Text("\($0 / 1024) GB").tag($0) }
                }
            } footer: {
                Text("This Mac: \(DeviceSettings.hostCores) cores (\(DeviceSettings.perfCores) performance), \(DeviceSettings.hostGB) GB memory. Giving Android more than macOS can spare makes everything swap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Frame rate", selection: $settings.refreshRate) {
                    ForEach(DeviceSettings.refreshRates, id: \.self) { Text("\($0) FPS").tag($0) }
                }
                Toggle("High-priority engine", isOn: $settings.highPriority)
                Toggle("Performance game mode", isOn: $settings.gameMode)
                Toggle("Lighter animations", isOn: $settings.reduceAnimations)
            } footer: {
                Text("Frame rate sets Android's display refresh, so games can unlock 90 or 120 FPS modes. High priority keeps Android on the performance cores and stops App Nap. Game mode asks Android to run installed games in performance mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var display: some View {
        Form {
            Section {
                Picker("Orientation", selection: orientationBinding) {
                    Text("Landscape").tag(true)
                    Text("Portrait").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("Resolution", selection: resolutionBinding) {
                    ForEach(DeviceSettings.resolutions.filter { ($0.width >= $0.height) == settings.isLandscape }, id: \.label) {
                        Text($0.label).tag($0.label)
                    }
                }
                Picker("Pixel density", selection: $settings.density) {
                    ForEach(DeviceSettings.densities, id: \.self) { Text("\($0) DPI").tag($0) }
                }
            } footer: {
                Text("Most games are landscape. Higher DPI makes Android's interface bigger; lower fits more on screen."
                     + (DeviceSettings.hostGB <= 8 ? " On an \(DeviceSettings.hostGB) GB Mac, 1280 × 720 leaves the most memory for the game itself." : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show frame rate counter", isOn: $settings.showFPS)
            }
        }
        .formStyle(.grouped)
    }

    private var graphics: some View {
        Form {
            Section {
                Picker("Renderer", selection: $settings.renderer) {
                    Text("Metal GPU (recommended)").tag(DeviceSettings.Renderer.metal)
                    Text("Software (compatibility)").tag(DeviceSettings.Renderer.software)
                }
                Toggle("Vulkan for games", isOn: $settings.vulkan)
            } footer: {
                Text("Metal: games draw on your Mac's GPU. Software draws on the CPU, only for a game that shows a black screen. Turn Vulkan off if a game crashes at start; it will fall back to OpenGL ES.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your GPU") {
                LabeledContent("GPU", value: gpuName)
                LabeledContent("Graphics APIs", value: "OpenGL ES 3.0, Vulkan 1.3")
                LabeledContent("Path", value: "gfxstream → Metal")
            }
        }
        .formStyle(.grouped)
    }

    private var apps: some View {
        Form {
            Section {
                ForEach(Debloat.catalog.filter(\.common)) { appToggle($0) }
            } header: {
                HStack {
                    Text("Preinstalled apps")
                    Spacer()
                    Button("Recommended") { settings.disabledApps = Debloat.recommended }
                    Button("Keep all") { settings.disabledApps = [] }
                }
            } footer: {
                Text("Turned-off apps are disabled inside Android so they never run in the background. Nothing is deleted; switch one back on any time. Play Store, Play Services and the keyboard always stay.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Show all (\(Debloat.catalog.filter { !$0.common }.count) system extras)", isExpanded: $showAllApps) {
                    ForEach(Debloat.catalog.filter { !$0.common }) { appToggle($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appToggle(_ app: Debloat.App) -> some View {
        Toggle(app.name, isOn: Binding(
            get: { !settings.disabledApps.contains(app.id) },
            set: { on in
                settings.disabledApps.removeAll { $0 == app.id }
                if !on { settings.disabledApps.append(app.id) }
            }
        ))
    }

    private var controls: some View {
        Form {
            Section {
                Toggle("Show control hints over games", isOn: $settings.showHints)
                LabeledContent("Mouse-look sensitivity") {
                    HStack {
                        Slider(value: $settings.aimSensitivity, in: 0.25...3, step: 0.05)
                        Text(String(format: "%.2f×", settings.aimSensitivity)).monospacedDigit().frame(width: 48)
                    }
                }
                Button("Edit controls for the current game") { onEditControls() }
            } footer: {
                Text("⌘K opens the controls editor in any game: add tap keys, a W A S D stick, an aim area with its own mouse-lock key, and a fire button for left click. ⌃⌥ always releases a locked mouse. Each game keeps its own keys, overlay visibility and lock-on-open setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var rootBusy: Bool {
        root.stage == .downloading || root.stage == .installing
    }

    private var rootTab: some View {
        Form {
            Section {
                Toggle("KernelSU root", isOn: $settings.rootEnabled)
                    .disabled(!root.kernelReady)
            } header: {
                Text("Root")
            } footer: {
                Text(root.kernelReady
                     ? "Boots a KernelSU + SUSFS kernel so apps can get root. SUSFS hides root from detection (Play Integrity, anti-cheat). Turning this off boots the stock kernel, leaving no trace. Changing it restarts Android."
                     : "Download the KernelSU kernel below first.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Status") {
                statusRow("KernelSU kernel", ok: root.kernelReady,
                          okText: "Downloaded", noText: "Not downloaded")
                statusRow("Manager app", ok: root.managerInstalled == true,
                          okText: "Installed", noText: root.managerInstalled == nil ? "Checking…" : "Not installed")
                statusRow("Root active", ok: root.rootActive == true,
                          okText: "Granted (uid 0)", noText: root.rootActive == nil ? "Checking…" : "Not rooted — enable root and restart")
            }

            Section {
                Picker("Device profile", selection: $settings.deviceProfile) {
                    ForEach(DeviceProfile.all) { Text($0.name).tag($0.id) }
                }
                .disabled(!settings.rootEnabled)
                Button("Apply profile now") {
                    if let serial { Task { await root.applyProfile(.named(settings.deviceProfile), serial: serial) } }
                }
                .disabled(root.rootActive != true || serial == nil || rootBusy)
            } header: {
                Text("Device profile")
            } footer: {
                Text("Spoofs the build fingerprint to a real phone so root and the emulator stay hidden. Applied as a KernelSU module; takes effect after a restart. Needs root already active.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if rootBusy {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: root.progress)
                        Text(root.status).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Button(root.kernelReady ? "Re-download kit" : "Download kernel + manager") {
                            Task { await root.downloadKit() }
                        }
                        Button("Install manager") {
                            if let serial { Task { await root.installManager(serial: serial) } }
                        }
                        .disabled(!root.kernelReady || serial == nil)
                    }
                    if case .failed(let msg) = root.stage {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    } else if !root.status.isEmpty {
                        Text(root.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("The kernel comes from the nunu-kernel build; the manager is KernelSU-Next. Grant or deny each app's root from the manager app inside Android.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            if let serial { await root.refreshStatus(serial: serial) }
        }
    }

    private func statusRow(_ label: String, ok: Bool, okText: String, noText: String) -> some View {
        LabeledContent(label) {
            Label(ok ? okText : noText, systemImage: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    private var advanced: some View {
        Form {
            Section {
                Toggle("Quick boot", isOn: $settings.quickBoot)
                Toggle("Sound", isOn: $settings.audio)
                Picker("Storage for apps", selection: $settings.dataSizeGB) {
                    ForEach(DeviceSettings.dataSizes.filter { $0 >= running.dataSizeGB }, id: \.self) {
                        Text("\($0) GB").tag($0)
                    }
                }
            } footer: {
                Text("Quick boot saves Android's state on quit so it resumes in seconds. Storage can grow but not shrink.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Use Touch ID as Android's fingerprint", isOn: $settings.touchID)
                Button("Set up fingerprint in Android…") { onSetUpFingerprint() }
            } header: {
                Text("Fingerprint")
            } footer: {
                Text("When an app, a Play Store purchase or the lock screen asks for a fingerprint, your Mac asks for Touch ID and passes the match to Android. Android needs a screen lock (PIN, pattern or password) first; during setup nunu asks for Touch ID once and does all the sensor touches for you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Developer") {
                LabeledContent("ADB address") {
                    HStack {
                        Text(adbAddress).textSelection(.enabled).monospaced()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("adb connect \(adbAddress)", forType: .string)
                        }
                    }
                }
                LabeledContent("Engine", value: versions.engine)
                LabeledContent("Android image", value: "Android 14, Google Play (r\(versions.image))")
                Button("Open logs folder") { NSWorkspace.shared.open(Paths.logs) }
            }
            Section {
                Button("Reset Android…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Bindings

    private var profileBinding: Binding<DeviceSettings.Profile> {
        Binding(get: { settings.profile }, set: { settings = settings.applying($0) })
    }

    private var orientationBinding: Binding<Bool> {
        Binding(
            get: { settings.isLandscape },
            set: { landscape in
                guard landscape != settings.isLandscape,
                      let r = DeviceSettings.resolutions.first(where: { ($0.width >= $0.height) == landscape })
                else { return }
                settings.width = r.width
                settings.height = r.height
                settings.density = r.density
            }
        )
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: {
                DeviceSettings.resolutions.first { $0.width == settings.width && $0.height == settings.height }?.label
                    ?? DeviceSettings.resolutions[0].label
            },
            set: { label in
                guard let r = DeviceSettings.resolutions.first(where: { $0.label == label }) else { return }
                settings.width = r.width
                settings.height = r.height
                settings.density = r.density
            }
        )
    }
}
