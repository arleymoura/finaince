import Foundation
import LocalAuthentication
import SwiftUI

// MARK: - AppLockManager

@Observable
final class AppLockManager {

    // MARK: - Singleton

    static let shared = AppLockManager()

    // MARK: - State

    /// Whether the user has enabled app lock (persisted)
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "app.lockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "app.lockEnabled") }
    }

    /// Whether the app is currently showing the lock screen
    private(set) var isLocked: Bool = false

    /// Privacy veil shown while app is in background / app switcher
    private(set) var isObscured: Bool = false

    /// Biometry type available on the device (face, touch or none)
    var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Lock the app if the feature is enabled.
    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
    }

    /// Show the privacy veil (hides content in app switcher).
    func obscure() {
        guard isEnabled else { return }
        isObscured = true
    }

    /// Remove the privacy veil (app came back to foreground).
    func reveal() {
        isObscured = false
    }

    /// Attempt biometric / passcode authentication.
    /// On success, clears `isLocked`.
    @MainActor
    func authenticate() async {
        let context = LAContext()
        var error: NSError?

        // Prefer biometry + passcode fallback (.deviceOwnerAuthentication)
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Biometry not available — clear lock so the user isn't permanently blocked
            isLocked = false
            return
        }

        let reason = t("lock.reason")

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: reason)
            if success {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLocked = false
                }
            }
        } catch {
            // User cancelled or failed — keep locked
        }
    }
}
