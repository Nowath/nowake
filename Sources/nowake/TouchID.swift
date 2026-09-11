import Foundation
import LocalAuthentication

enum TouchIDError: LocalizedError {
    /// Someone else's PAM config lives at the path — not ours to delete.
    case foreignConfig

    var errorDescription: String? {
        switch self {
        case .foreignConfig:
            return """
                \(TouchID.pamPath) wasn't written by nowake, so it has been left alone. \
                Remove the pam_tid.so line by hand to turn Touch ID off.
                """
        }
    }
}

/// Touch ID for the privileged `pmset` calls.
///
/// The fingerprint is checked by `sudo`, not by this app. Enabling writes
/// `auth sufficient pam_tid.so` to /etc/pam.d/sudo_local, which /etc/pam.d/sudo
/// already includes, so the privilege boundary stays exactly where the system
/// enforces it: every escalation still authenticates, it just stops being a
/// typed password.
///
/// Authenticating in-process with `LAContext` instead would be theatre — it
/// grants no rights, so it would still need a NOPASSWD sudoers rule to do the
/// work, and anything else running as this user could skip straight past the
/// prompt to the same rule. `LAContext` is used here only to ask whether a
/// finger is enrolled, which it answers without prompting.
enum TouchID {

    static let pamPath = "/etc/pam.d/sudo_local"
    static let pamLine = "auth       sufficient     pam_tid.so"

    /// The marker is what makes removal safe — see `disable()`.
    private static let marker = "# Installed by nowake — Touch ID for sudo."

    private static var fileContent: String {
        """
        \(marker)
        # Remove with: sudo rm \(pamPath)
        \(pamLine)
        """
    }

    // MARK: - Probing

    /// Whether this Mac has a sensor with a finger actually enrolled.
    /// Evaluating the policy would prompt; asking whether it *can* be does not.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Whether sudo is currently wired to accept a fingerprint. A commented-out
    /// line is the state macOS ships in its own template, so it has to be read
    /// as "off" rather than merely searched for.
    static var isEnabledForSudo: Bool {
        activeLines.contains { $0.contains("pam_tid.so") }
    }

    private static var activeLines: [String] {
        guard let contents = try? String(contentsOfFile: pamPath, encoding: .utf8) else { return [] }
        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
    }

    private static var isOurs: Bool {
        guard let contents = try? String(contentsOfFile: pamPath, encoding: .utf8) else { return false }
        return contents.contains(marker)
    }

    // MARK: - Changing it (needs root)

    static func enable() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("nowake-pam-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try (fileContent + "\n").write(to: temporary, atomically: true, encoding: .utf8)

        // 0444 root:wheel matches what macOS ships for the rest of /etc/pam.d.
        try SleepBlocker.authorize(
            "/usr/bin/install -m 0444 -o root -g wheel '\(temporary.path)' \(pamPath)"
        )
    }

    static func disable() throws {
        // sudo_local is a shared file that survives system updates, and a user
        // may keep their own modules in it. Only ever remove one we wrote.
        guard isOurs else { throw TouchIDError.foreignConfig }
        try SleepBlocker.authorize("/bin/rm -f \(pamPath)")
    }
}
