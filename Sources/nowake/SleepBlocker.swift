import Foundation
import IOKit
import IOKit.pwr_mgt

enum SleepBlockerError: Error {
    /// The user dismissed the macOS password dialog.
    case cancelled
    case scriptFailed(String)
    case didNotApply
}

/// Wraps pmset's official `disablesleep` power-management flag.
///
/// This is the only switch that actually prevents clamshell sleep — `caffeinate`
/// and plain `IOPMAssertion` calls only hold off *idle* sleep, so the Mac still
/// drops off the moment the lid shuts.
enum SleepBlocker {

    // MARK: - Reading the real system state

    /// Read straight from IOPMrootDomain rather than parsing `pmset` output,
    /// which doesn't even print this key on every macOS release.
    static var isSleepDisabled: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.boolValue ?? false
    }

    // MARK: - Changing it (needs root)

    /// - Returns: the state the system actually landed in.
    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) throws -> Bool {

        // Turning the mode ON disables a safety mechanism, so it always asks for
        // a password. Turning it OFF only restores the system default, so the
        // optional sudoers rule may let it through silently — that is what lets
        // the timer and the battery cutoff fire with nobody at the keyboard.
        if disabled {
            try runPrivileged("/usr/bin/pmset -a disablesleep 1")
        } else if Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]) != 0 {
            try runPrivileged("/usr/bin/pmset -a disablesleep 0")
        }
        let applied = isSleepDisabled
        guard applied == disabled else { throw SleepBlockerError.didNotApply }
        return applied
    }

    static func runPrivileged(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else {
            throw SleepBlockerError.scriptFailed("Could not build the authorization script.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return }
        let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -128 { throw SleepBlockerError.cancelled }   // User canceled
        throw SleepBlockerError.scriptFailed((errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error.")
    }

    // MARK: - Belt-and-braces idle-sleep assertion

    private static var assertionID: IOPMAssertionID = 0

    static func holdAssertion() {
        guard assertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "nowake: keeping the Mac awake with the lid closed" as CFString,
            &id
        )
        if result == kIOReturnSuccess { assertionID = id }
    }

    static func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
