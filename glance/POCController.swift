//
//  POCController.swift
//  glance
//
//  Orchestration for credential storage: wires SecureCredentialManager to
//  KeystrokeInjector and exposes session/password status for Settings.
//

import Foundation
import Observation

@Observable
@MainActor
final class POCController {
    var accessibilityGranted: Bool = KeystrokeInjector.isAccessibilityTrusted()

    var hasStoredPassword: Bool = SecureCredentialManager.hasStoredPassword()
    var isSessionUnlocked: Bool = SecureCredentialManager.isSessionUnlocked
    var sessionError: String? = nil

    /// Bound to the setup SecureField. Cleared immediately after a successful save.
    var passwordInput: String = ""

    var statusMessage: String = "Idle"

    func refreshAccessibilityStatus() {
        accessibilityGranted = KeystrokeInjector.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        KeystrokeInjector.promptForAccessibility()
    }

    func refreshCredentialStatus() {
        hasStoredPassword = SecureCredentialManager.hasStoredPassword()
        isSessionUnlocked = SecureCredentialManager.isSessionUnlocked
    }

    // MARK: - Session (Touch ID gate)

    /// Must succeed before `savePassword()` or `injectStoredPassword()` will do anything.
    func unlockSession() async {
        sessionError = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try await SecureCredentialManager.unlockSession(reason: "Authenticate to set up or use Peek")
            }.value
            isSessionUnlocked = true
        } catch {
            isSessionUnlocked = false
            sessionError = error.localizedDescription
        }
    }

    func lockSession() {
        SecureCredentialManager.lockSession()
        isSessionUnlocked = false
    }

    // MARK: - Setup flow

    /// Encrypts and stores `passwordInput`. Requires the session to already
    /// be unlocked (Touch ID happens in `unlockSession()`, not here).
    func savePassword() async {
        guard !passwordInput.isEmpty else {
            statusMessage = "Enter a password first."
            return
        }
        let plaintext = passwordInput
        passwordInput = ""

        do {
            try await Task.detached(priority: .userInitiated) {
                guard var bytes = plaintext.data(using: .utf8) else {
                    throw SecureCredentialError.emptyPassword
                }
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try SecureCredentialManager.savePassword(bytes)
            }.value
            statusMessage = "Password saved and encrypted."
            hasStoredPassword = true
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Injection

    /// Reads + decrypts + injects the stored password, zeroing the plaintext
    /// buffer before returning. When `requireAuthoritativeLock` is true (the
    /// auto-trigger path), refuses to inject unless the CGSession dictionary
    /// confirms the screen is actually locked.
    /// Returns `true` only when keystrokes were posted successfully.
    @discardableResult
    func injectStoredPassword(requireAuthoritativeLock: Bool = false, attempts: Int = 1) async -> Bool {
        guard KeystrokeInjector.isAccessibilityTrusted() else {
            // Request the system Accessibility permission the same way Glance does
            // during setup — so unlock isn't a silent no-op after a face match.
            KeystrokeInjector.promptForAccessibility()
            statusMessage = "Accessibility not granted — enable Peek in System Settings, then relaunch."
            UnlockDiagnostics.log("inject blocked: Accessibility not trusted (prompted)")
            return false
        }
        guard SecureCredentialManager.isSessionUnlocked else {
            statusMessage = "Session locked — authenticate with Touch ID first."
            return false
        }

        if requireAuthoritativeLock {
            guard LockMonitor.isScreenActuallyLocked() else {
                statusMessage = "Skipped: CGSession reports screen is not actually locked."
                return false
            }
        }

        let tries = max(1, attempts)
        for attempt in 1...tries {
            statusMessage = tries > 1 ? "Injecting… (\(attempt)/\(tries))" : "Injecting…"
            do {
                try await Task.detached(priority: .userInitiated) {
                    var bytes = try SecureCredentialManager.readPassword()
                    defer { bytes.resetBytes(in: 0..<bytes.count) }
                    try KeystrokeInjector.typeAndReturn(bytes)
                }.value
                statusMessage = "Injected stored password + Return at \(Date().formatted(date: .omitted, time: .standard))"
                return true
            } catch {
                statusMessage = "Injection failed: \(error.localizedDescription)"
                if attempt < tries {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                }
            }
        }
        return false
    }
}
