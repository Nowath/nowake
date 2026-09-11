import AppKit

/// Every modal the app can raise. Kept together so the wording stays consistent.
enum Alerts {

    private static func run(
        style: NSAlert.Style,
        title: String,
        body: String,
        primary: String,
        secondary: String?
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: primary)
        if let secondary { alert.addButton(withTitle: secondary) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// - Returns: `true` if the user wants to switch on anyway.
    static func confirmUnplugged() -> Bool {
        run(
            style: .warning,
            title: "You're running on battery",
            body: """
                Keeping your Mac awake with the lid closed drains the battery continuously, \
                and a closed Mac can't shed heat well — don't put it in a bag like this.

                Turn it on anyway?
                """,
            primary: "Turn On",
            secondary: "Cancel"
        )
    }

    /// - Returns: `true` if the user chose to turn the mode off.
    static func batteryLow(_ percentage: Int) -> Bool {
        NSSound.beep()
        return !run(
            style: .warning,
            title: "Battery at \(percentage)%",
            body: "nowake is still keeping this Mac awake and you're on battery power.",
            primary: "Keep It On",
            secondary: "Turn Off"
        )
    }

    /// - Returns: `true` if the user chose to turn the mode off.
    static func batteryCritical(_ percentage: Int) -> Bool {
        NSSound.beep()
        NSApp.requestUserAttention(.criticalRequest)
        return !run(
            style: .critical,
            title: "Battery critically low — \(percentage)%",
            body: """
                nowake is preventing sleep and you're unplugged. If the battery runs out \
                while the lid is closed, unsaved work can be lost.
                """,
            primary: "Keep It On",
            secondary: "Turn Off"
        )
    }

    static func batteryCutoffDeclined(_ percentage: Int) {
        _ = run(
            style: .critical,
            title: "Battery cutoff needs your password",
            body: """
                Battery hit \(percentage)%, but switching sleep back on requires admin \
                authorization and the prompt was dismissed. nowake is still active.
                """,
            primary: "OK",
            secondary: nil
        )
    }

    /// - Returns: `true` if the user consents to installing the sudoers rule.
    static func confirmInstallSudoers() -> Bool {
        run(
            style: .informational,
            title: "Turn off without a password?",
            body: """
                This writes one line to \(SudoersRule.path):

                \(SudoersRule.grantDescription)

                That grants exactly one command as root — the one that restores macOS's \
                default sleep behaviour. Turning nowake on will still ask you to authorize.

                Without this, the auto-off timer and the battery cutoff can only raise a \
                dialog and wait for you to come back.
                """,
            primary: "Install Rule",
            secondary: "Cancel"
        )
    }

    /// - Returns: `true` if the user consents to enabling Touch ID for sudo.
    static func confirmEnableTouchID() -> Bool {
        run(
            style: .informational,
            title: "Use Touch ID instead of typing your password?",
            body: """
                This writes \(TouchID.pamPath):

                \(TouchID.pamLine)

                /etc/pam.d/sudo already includes that file, so sudo starts accepting your \
                fingerprint everywhere — in nowake and in Terminal alike. Authorization is \
                still required every single time; it just stops being a typed password.

                Writing the file needs your password once, now.
                """,
            primary: "Enable Touch ID",
            secondary: "Cancel"
        )
    }

    /// The one failure the user can still fix themselves, so it hands over the
    /// fix rather than only reporting the refusal.
    static func touchIDBlocked() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "macOS won't let nowake write PAM configuration"
        alert.informativeText = """
            Editing PAM configuration is gated behind Full Disk Access, which nowake \
            deliberately doesn't ask for — being root isn't enough on its own.

            Run these two lines in Terminal, then flip the switch again:

            \(TouchID.terminalCommands)
            """
        alert.addButton(withTitle: "Copy Commands")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TouchID.terminalCommands, forType: .string)
    }

    static func autoOffDeclined() {
        _ = run(
            style: .warning,
            title: "Auto-off needs your password",
            body: """
                The timer elapsed, but turning sleep back on requires authorization \
                and the prompt was dismissed. nowake is still active.
                """,
            primary: "OK",
            secondary: nil
        )
    }

    /// - Returns: `true` if the user wants to quit regardless.
    static func confirmQuitWhileActive() -> Bool {
        run(
            style: .warning,
            title: "Sleep is still disabled",
            body: """
                The authorization prompt was dismissed, so this Mac will keep ignoring the lid \
                even after nowake quits.

                To undo it later, run in Terminal:
                sudo pmset -a disablesleep 0
                """,
            primary: "Quit Anyway",
            secondary: "Cancel"
        )
    }

    static func present(_ error: Error) {
        let detail: String
        switch error {
        case SleepBlockerError.scriptFailed(let message):
            detail = message
        case SleepBlockerError.didNotApply:
            detail = "pmset ran, but the system didn't report the new state."
        case let localized as LocalizedError where localized.errorDescription != nil:
            detail = localized.errorDescription!
        default:
            detail = String(describing: error)
        }
        _ = run(style: .critical, title: "Couldn't change the setting", body: detail, primary: "OK", secondary: nil)
    }
}
