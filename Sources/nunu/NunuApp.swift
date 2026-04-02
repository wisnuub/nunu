import SwiftUI

@main
struct NunuApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .background(Color(hex: "#0D0F14"))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About nunu") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "nunu",
                            .applicationVersion: "1.0.0",
                            .credits: NSAttributedString(string: "Android without compromise")
                        ]
                    )
                }
            }
        }
    }
}

struct ContentRootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isOnboardingDone {
                MainLauncherView()
                    .frame(minWidth: 1280, minHeight: 800)
            } else {
                OnboardingView()
                    .frame(width: 900, height: 620)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.isOnboardingDone)
    }
}
