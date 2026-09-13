import Foundation

/// Passwordless *turn-off*.
///
/// Grants this user exactly one command as root: `pmset -a disablesleep 0`,
/// which restores macOS's default sleep behaviour. Turning the mode *on* is
/// deliberately left out — that's the direction that disables a safety
/// mechanism, so it always goes through a password prompt.
///
/// Without this rule the auto-off timer and the battery cutoff can only raise a
/// dialog and wait, which is useless in the case they exist for: nobody at the
/// keyboard.
enum SudoersRule {

    static let path = "/etc/sudoers.d/nowake"
    static let command = "/usr/bin/pmset -a disablesleep 0"

    private static var fileContent: String {
        """
        # Installed by nowake.
        # Grants only the command that restores default sleep behaviour.
        # Remove with: sudo rm \(path)
        \(NSUserName()) ALL=(root) NOPASSWD: \(command)
        """
    }

    /// Shown to the user verbatim before anything is written.
    static var grantDescription: String {
        "\(NSUserName()) ALL=(root) NOPASSWD: \(command)"
    }

    /// `sudo -n -l` reports whether the command is permitted without running it
    /// and without ever prompting.
    static var isInstalled: Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]) == 0
    }

    static func install() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("nowake-sudoers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try (fileContent + "\n").write(to: temporary, atomically: true, encoding: .utf8)

        // A malformed sudoers file can lock the user out of sudo entirely, so
        // validate first; `&&` keeps install from running if visudo objects.
        try SleepBlocker.authorize(
            "/usr/sbin/visudo -cf '\(temporary.path)' "
            + "&& /usr/bin/install -m 0440 -o root -g wheel '\(temporary.path)' \(path)"
        )
    }

    static func remove() throws {
        try SleepBlocker.authorize("/bin/rm -f \(path)")
    }
}

enum Shell {
    /// Runs a command with no stdin and discarded output. Returns its exit code.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
