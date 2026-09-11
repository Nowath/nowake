import Foundation
import LocalAuthentication

enum TouchIDError: LocalizedError {
    /// Someone else's PAM config lives at the path — not ours to delete.
    case foreignConfig
    /// The write was authorized and still refused. See `enable()`.
    case blockedByPrivacy

    var errorDescription: String? {
        switch self {
        case .foreignConfig:
            return """
                \(TouchID.pamPath) wasn't written by nowake — you or Apple's own \
                instructions put it there — so it has been left alone rather than \
                deleted out from under whatever else may rely on it.

                To turn Touch ID for sudo off, run:

                sudo rm \(TouchID.pamPath)
                """
        case .blockedByPrivacy:
            return """
                macOS refused the write. Editing PAM configuration is gated behind Full Disk \
                Access, which nowake deliberately doesn't ask for — root alone isn't enough.

                Run these two lines in Terminal instead, then flip the switch again:

                \(TouchID.terminalCommands)
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

    /// Apple's own documented steps, used both in the alert and on the clipboard
    /// so the text the user reads is the text they paste.
    static var terminalCommands: String {
        """
        sudo cp \(pamPath).template \(pamPath)
        sudo sed -i '' 's/^#auth/auth/' \(pamPath)
        """
    }

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
    static var isEnabledForSudo: Bool { isEnabled(at: pamPath) }

    /// Path-injectable so the parse can be exercised against a real file.
    static func isEnabled(at path: String) -> Bool {
        activeLines(at: path).contains { $0.contains("pam_tid.so") }
    }

    private static func activeLines(at path: String) -> [String] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
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
        //
        // This can be authorized and still fail: /etc/pam.d is not SIP-restricted
        // (it isn't in rootless.conf) but it is privacy-gated, so a process
        // without Full Disk Access gets EPERM even as root. /etc/sudoers.d has no
        // such gate, which is why the other rule installs from here happily.
        do {
            try SleepBlocker.authorize(
                "/usr/bin/install -m 0444 -o root -g wheel '\(temporary.path)' \(pamPath)"
            )
        } catch SleepBlockerError.scriptFailed(let message)
                    where message.localizedCaseInsensitiveContains("not permitted") {
            throw TouchIDError.blockedByPrivacy
        }

        // The command can report success and still not have landed, so confirm
        // against the file rather than against an exit code.
        guard isEnabledForSudo else { throw TouchIDError.blockedByPrivacy }
    }

    static func disable() throws {
        // sudo_local is a shared file that survives system updates, and a user
        // may keep their own modules in it. Only ever remove one we wrote.
        guard isOurs else { throw TouchIDError.foreignConfig }
        try SleepBlocker.authorize("/bin/rm -f \(pamPath)")
    }
}
