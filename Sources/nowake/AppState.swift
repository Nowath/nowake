import AppKit
import Combine

// MARK: - Settings

enum AutoOff: Int, CaseIterable, Identifiable {
    case never = 0
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never:         return "Never"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour:       return "1 hour"
        case .twoHours:      return "2 hours"
        case .fourHours:     return "4 hours"
        }
    }

    var interval: TimeInterval { TimeInterval(rawValue) * 60 }
}

/// Battery level at which the mode switches itself back off.
enum BatteryLimit: Int, CaseIterable, Identifiable {
    case off = 0
    case ten = 10
    case fifteen = 15
    case twenty = 20
    case twentyFive = 25
    case thirty = 30
    case forty = 40
    case fifty = 50
    case sixty = 60
    case seventy = 70

    var id: Int { rawValue }
    var label: String { self == .off ? "Never" : "\(rawValue)%" }
    var percentage: Int? { self == .off ? nil : rawValue }
}

enum BatteryWarning: Equatable {
    case none
    case low(Int)
    case critical(Int)

    var message: String? {
        switch self {
        case .none:                return nil
        case .low(let p):          return "Battery at \(p)% and unplugged."
        case .critical(let p):     return "Battery at \(p)% — plug in or turn this off."
        }
    }
}

// MARK: - State

final class AppState: ObservableObject {

    private let lowThreshold = 20
    private let criticalThreshold = 10

    @Published private(set) var isActive = false
    @Published private(set) var isLidClosed = false
    @Published private(set) var power = PowerState.unknown
    @Published private(set) var warning = BatteryWarning.none

    /// When this session was switched on. `nil` when the flag was already set
    /// before launch — we won't invent a start time we don't know.
    @Published private(set) var activatedAt: Date?
    @Published private(set) var expiresAt: Date?

    @Published var autoOff: AutoOff = .never {
        didSet {
            UserDefaults.standard.set(autoOff.rawValue, forKey: Keys.autoOff)
            rearmAutoOff()
        }
    }

    @Published var batteryLimit: BatteryLimit = .off {
        didSet {
            UserDefaults.standard.set(batteryLimit.rawValue, forKey: Keys.batteryLimit)
            batteryCutoffAttempted = false
            onStateChange?()
        }
    }

    /// Whether the sudoers rule that lets turn-off skip the prompt is present.
    @Published private(set) var passwordlessOff = false

    /// Whether sudo is wired to accept a fingerprint, and whether this Mac has
    /// one to offer. The hardware answer can't change while the app runs, so it
    /// is read once rather than on every probe.
    @Published private(set) var touchIDEnabled = false
    let touchIDAvailable = TouchID.isAvailable

    /// Per-second labels live on their own object so ticking them doesn't
    /// invalidate the whole panel. See Ticker.
    let ticker = Ticker()

    var onStateChange: (() -> Void)?

    /// `sudo -n -l` costs ~24 ms and spawns a process, so it never runs on the
    /// main thread — a click used to pay for it before the panel could draw.
    private let probeQueue = DispatchQueue(label: "com.nowath.nowake.privilege", qos: .utility)

    private enum Keys {
        static let autoOff = "autoOffMinutes"
        static let batteryLimit = "batteryLimitPercent"
    }

    private let clamshell = ClamshellMonitor()
    private var tickTimer: Timer?
    private var lowWarned = false
    private var criticalWarned = false
    private var batteryCutoffAttempted = false

    // MARK: - Derived labels

    private func updateTicker() {
        let now = Date()
        ticker.update(
            elapsed: isActive && activatedAt != nil
                ? "Active for " + Ticker.format(now.timeIntervalSince(activatedAt!))
                : nil,
            remaining: isActive && expiresAt != nil
                ? Ticker.format(expiresAt!.timeIntervalSince(now)) + " left"
                : nil
        )
    }

    // MARK: - Lifecycle

    func start() {
        let defaults = UserDefaults.standard
        autoOff = AutoOff(rawValue: defaults.integer(forKey: Keys.autoOff)) ?? .never
        batteryLimit = BatteryLimit(rawValue: defaults.integer(forKey: Keys.batteryLimit)) ?? .off

        // Reflect reality: the flag may already be set from a previous run.
        isActive = SleepBlocker.isSleepDisabled
        if isActive { SleepBlocker.holdAssertion() }

        clamshell.onChange = { [weak self] closed in
            guard let self else { return }
            self.isLidClosed = closed
            self.refresh()
        }
        clamshell.start()
        isLidClosed = clamshell.isLidClosed

        refreshPrivilegeStatus()
        refresh()
        restartTicker()
    }

    /// Probes off the main thread and publishes only on a real change, so
    /// opening the panel never waits on it.
    func refreshPrivilegeStatus() {
        probeQueue.async { [weak self] in
            let installed = SudoersRule.isInstalled
            let touchID = TouchID.isEnabledForSudo
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.passwordlessOff != installed || self.touchIDEnabled != touchID else { return }
                self.passwordlessOff = installed
                self.touchIDEnabled = touchID
                self.onStateChange?()
            }
        }
    }

    func setPasswordlessOff(_ enabled: Bool) {
        do {
            if enabled {
                guard Alerts.confirmInstallSudoers() else { return }
                try SudoersRule.install()
            } else {
                try SudoersRule.remove()
            }
        } catch SleepBlockerError.cancelled {
            // Prompt dismissed; leave things exactly as they were.
        } catch {
            Alerts.present(error)
        }
        refreshPrivilegeStatus()
        // A declined prompt changes nothing, so the change-guarded publishing
        // stays silent — nudge SwiftUI to re-read the switch binding.
        objectWillChange.send()
    }

    func setTouchID(_ enabled: Bool) {
        do {
            if enabled {
                guard Alerts.confirmEnableTouchID() else { return }
                try TouchID.enable()
            } else {
                try TouchID.disable()
            }
        } catch SleepBlockerError.cancelled {
            // Prompt dismissed; leave things exactly as they were.
        } catch {
            Alerts.present(error)
        }
        refreshPrivilegeStatus()
        objectWillChange.send()
    }

    /// Re-read everything the system owns. Cheap enough to run on every tick.
    func refresh() {
        let active = SleepBlocker.isSleepDisabled
        let lidClosed = ClamshellMonitor.readLidClosed()
        let currentPower = PowerMonitor.current()

        var changed = false
        if isActive != active { isActive = active; changed = true }
        if isLidClosed != lidClosed { isLidClosed = lidClosed; changed = true }
        if power != currentPower { power = currentPower; changed = true }

        if isActive {
            let level = evaluateWarning()
            if warning != level { warning = level; changed = true }
        } else {
            if activatedAt != nil { activatedAt = nil; changed = true }
            if expiresAt != nil { expiresAt = nil; changed = true }
            if warning != .none { warning = .none; changed = true }
            lowWarned = false
            criticalWarned = false
            batteryCutoffAttempted = false
        }

        updateTicker()
        if changed { onStateChange?() }
    }

    // MARK: - Ticking

    /// One second while active, since elapsed time and the countdown are on
    /// screen; lazily otherwise — no reason to poke the CPU while idle.
    private func restartTicker() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: isActive ? 1 : 20, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        let wasActive = isActive
        refresh()
        if isActive != wasActive { restartTicker() }
        guard isActive else { return }

        if enforceBatteryLimit() { return }

        if let expiresAt, Date() >= expiresAt {
            self.expiresAt = nil
            requestToggle(to: false, reason: .autoOff)
            return
        }

        announceWarningIfNeeded()
    }

    // MARK: - Battery cutoff

    /// - Returns: `true` if a cutoff was attempted, so the caller stops here.
    private func enforceBatteryLimit() -> Bool {
        guard let limit = batteryLimit.percentage,
              power.hasBattery, !power.isPluggedIn,
              let percentage = power.percentage
        else {
            batteryCutoffAttempted = false
            return false
        }

        guard percentage <= limit else {
            batteryCutoffAttempted = false
            return false
        }

        // Only try once per dip below the line, or a declined prompt would
        // reappear every second.
        guard !batteryCutoffAttempted else { return false }
        batteryCutoffAttempted = true
        requestToggle(to: false, reason: .batteryLimit(percentage))
        return true
    }

    // MARK: - Toggling

    enum ToggleReason: Equatable {
        case user
        case autoOff
        case batteryLimit(Int)
    }

    func requestToggle() {
        requestToggle(to: !isActive, reason: .user)
    }

    func requestToggle(to target: Bool, reason: ToggleReason) {
        if target, reason == .user, !power.isPluggedIn, !Alerts.confirmUnplugged() {
            return
        }

        do {
            try SleepBlocker.setSleepDisabled(target)
            if target {
                SleepBlocker.holdAssertion()
                activatedAt = Date()
                rearmAutoOff()
            } else {
                SleepBlocker.releaseAssertion()
                activatedAt = nil
                expiresAt = nil
            }
            lowWarned = false
            criticalWarned = false
        } catch SleepBlockerError.cancelled {
            switch reason {
            case .autoOff:                 Alerts.autoOffDeclined()
            case .batteryLimit(let level): Alerts.batteryCutoffDeclined(level)
            case .user:                    break
            }
        } catch {
            Alerts.present(error)
        }

        refresh()
        restartTicker()

        // Same as above: if authorization was declined nothing changed, and the
        // switch would otherwise stay stuck where the user dragged it.
        objectWillChange.send()
    }

    private func rearmAutoOff() {
        guard isActive, autoOff != .never else {
            expiresAt = nil
            onStateChange?()
            return
        }
        expiresAt = Date().addingTimeInterval(autoOff.interval)
        onStateChange?()
    }

    // MARK: - Battery warnings

    private func evaluateWarning() -> BatteryWarning {
        guard power.hasBattery, !power.isPluggedIn, let percentage = power.percentage else { return .none }
        if percentage <= criticalThreshold { return .critical(percentage) }
        if percentage <= lowThreshold { return .low(percentage) }
        return .none
    }

    private func announceWarningIfNeeded() {
        switch warning {
        case .none:
            lowWarned = false
            criticalWarned = false
        case .critical(let percentage):
            guard !criticalWarned else { return }
            criticalWarned = true
            lowWarned = true
            if Alerts.batteryCritical(percentage) { requestToggle(to: false, reason: .user) }
        case .low(let percentage):
            guard !lowWarned else { return }
            lowWarned = true
            if Alerts.batteryLow(percentage) { requestToggle(to: false, reason: .user) }
        }
    }

    // MARK: - Quitting

    /// Restores the flag before exiting so it can't linger machine-wide.
    func quit() {
        if SleepBlocker.isSleepDisabled {
            do {
                try SleepBlocker.setSleepDisabled(false)
            } catch SleepBlockerError.cancelled {
                guard Alerts.confirmQuitWhileActive() else { refresh(); return }
            } catch {
                Alerts.present(error)
                refresh()
                return
            }
        }
        SleepBlocker.releaseAssertion()
        NSApp.terminate(nil)
    }
}
