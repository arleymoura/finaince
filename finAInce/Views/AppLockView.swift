import SwiftUI
import LocalAuthentication

// MARK: - AppLockView

struct AppLockView: View {
    @State private var lockManager = AppLockManager.shared
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.92),
                    Color.accentColor.opacity(0.60),
                    Color(.systemBackground).opacity(0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle pattern overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // App icon area
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 110, height: 110)

                        Circle()
                            .fill(Color.accentColor.opacity(0.10))
                            .frame(width: 90, height: 90)

                        Image(systemName: biometryIcon)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: 8) {
                        Text(t("lock.title"))
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text(t("lock.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }

                Spacer()

                // Unlock button
                Button {
                    Task { await triggerAuth() }
                } label: {
                    HStack(spacing: 12) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: biometryIcon)
                                .font(.body.weight(.semibold))
                        }
                        Text(unlockLabel)
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.40), radius: 16, y: 6)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 32)
                .padding(.bottom, 56)
            }
        }
        .onAppear {
            Task {
                // Small delay so the view is fully on screen before the auth prompt appears
                try? await Task.sleep(for: .milliseconds(350))
                await triggerAuth()
            }
        }
    }

    // MARK: - Helpers

    private var biometryIcon: String {
        switch lockManager.biometryType {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        default:        return "lock.fill"
        }
    }

    private var unlockLabel: String {
        switch lockManager.biometryType {
        case .faceID:   return t("lock.unlockFaceID")
        case .touchID:  return t("lock.unlockTouchID")
        default:        return t("lock.unlockPasscode")
        }
    }

    @MainActor
    private func triggerAuth() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        await lockManager.authenticate()
        isAuthenticating = false
    }
}

// MARK: - Privacy Veil

/// Shown while the app is in background / app switcher to hide sensitive content.
struct PrivacyVeilView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.55))

                Text("finAInce")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
