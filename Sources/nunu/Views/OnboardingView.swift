import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color(hex: "#0D0F14").ignoresSafeArea()

            Group {
                switch appState.onboardingStep {
                case .welcome:
                    WelcomeStep()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .downloading:
                    DownloadStep()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .signIn:
                    SignInStep()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .complete:
                    CompleteStep()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appState.onboardingStep)
        }
    }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
    @EnvironmentObject var appState: AppState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Color(hex: "#5B6EF5").opacity(0.5), radius: 24, x: 0, y: 8)

                Image(systemName: "android")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1.0 : 0.7)
            .opacity(appeared ? 1.0 : 0.0)

            Spacer().frame(height: 40)

            Text("nunu")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared ? 0 : 16)

            Spacer().frame(height: 12)

            Text("Android without compromise")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared ? 0 : 12)

            Spacer().frame(height: 24)

            Text("Run Android games natively on your Mac M1.\nFull performance. Zero emulation overhead.")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared ? 0 : 8)

            Spacer().frame(height: 52)

            Button(action: {
                appState.onboardingStep = .downloading
                Task { await appState.startDownload() }
            }) {
                Text("Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 220, height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color(hex: "#5B6EF5").opacity(0.4), radius: 16, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 12)

            Spacer()
        }
        .padding(.horizontal, 80)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Download Step

private struct DownloadStep: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseScale: CGFloat = 1.0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(hex: "#5B6EF5").opacity(0.15), lineWidth: 1)
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulseScale)

                Circle()
                    .stroke(Color(hex: "#5B6EF5").opacity(0.25), lineWidth: 1.5)
                    .frame(width: 108, height: 108)
                    .scaleEffect(pulseScale * 0.95)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(0.15), value: pulseScale)

                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                    .frame(width: 88, height: 88)

                Circle()
                    .trim(from: 0, to: appState.downloadProgress)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: appState.downloadProgress)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)

            Spacer().frame(height: 40)

            Text("Setting up nunu")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 8)

            Text(appState.downloadStatusText)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.55))
                .animation(.easeInOut(duration: 0.3), value: appState.downloadStatusText)
                .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 32)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * appState.downloadProgress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: appState.downloadProgress)
                }
            }
            .frame(height: 6)
            .opacity(appeared ? 1 : 0)
            .padding(.horizontal, 120)

            Spacer().frame(height: 16)

            Text("\(Int(appState.downloadProgress * 100))%")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#5B6EF5"))
                .opacity(appeared ? 1 : 0)

            Spacer()
        }
        .padding(.horizontal, 80)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                appeared = true
            }
            pulseScale = 1.12
        }
    }
}

// MARK: - Sign In Step

private struct SignInStep: View {
    @EnvironmentObject var appState: AppState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            VStack(spacing: 8) {
                Text("Connect your Google Account")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Access your game library and saves across devices")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer().frame(height: 28)

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    GoogleSignInView { email in
                        appState.isSignedIn = true
                        appState.userEmail = email
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            appState.onboardingStep = .complete
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                )
                .frame(height: 340)
                .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 20)

            Button(action: {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    appState.onboardingStep = .complete
                }
            }) {
                Text("Skip for now")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .underline()
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)

            Spacer()
        }
        .padding(.horizontal, 80)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Complete Step

private struct CompleteStep: View {
    @EnvironmentObject var appState: AppState
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var ringTrim: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 3)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: ringTrim)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: ringTrim)

                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

            Spacer().frame(height: 40)

            VStack(spacing: 10) {
                Text("You're all set!")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let email = appState.userEmail {
                    Text("Signed in as \(email)")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.5))
                } else {
                    Text("Ready to play Android games on your Mac")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .opacity(contentOpacity)
            .offset(y: contentOpacity == 0 ? 12 : 0)

            Spacer().frame(height: 52)

            Button(action: {
                appState.isOnboardingDone = true
            }) {
                Text("Launch nunu")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 220, height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#5B6EF5"), Color(hex: "#8B5CF6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color(hex: "#5B6EF5").opacity(0.4), radius: 16, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .opacity(contentOpacity)

            Spacer()
        }
        .padding(.horizontal, 80)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) { ringTrim = 1.0 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.9)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(1.1)) { contentOpacity = 1.0 }
        }
    }
}
