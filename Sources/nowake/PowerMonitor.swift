import Foundation
import IOKit.ps
import IOKit.pwr_mgt

struct PowerState: Equatable {
    var hasBattery: Bool
    var isPluggedIn: Bool
    var isCharging: Bool
    var percentage: Int?

    static let unknown = PowerState(hasBattery: false, isPluggedIn: true, isCharging: false, percentage: nil)

    var summary: String {
        guard hasBattery else { return "Plugged in" }
        guard let percentage else { return isPluggedIn ? "Plugged in" : "On battery" }
        if isPluggedIn { return isCharging ? "Charging \(percentage)%" : "Plugged in \(percentage)%" }
        return "On battery \(percentage)%"
    }

    /// SF Symbol matching the current charge level.
    var symbolName: String {
        guard hasBattery, let percentage else { return "powerplug.fill" }
        if isPluggedIn && isCharging { return "battery.100.bolt" }
        switch percentage {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

enum PowerMonitor {

    static func current() -> PowerState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .unknown }

        let providing = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String
        let pluggedIn = providing != kIOPMBatteryPowerKey

        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerState(hasBattery: false, isPluggedIn: pluggedIn, isCharging: false, percentage: nil)
        }

        for source in list {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType,
                  let capacity = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }

            return PowerState(
                hasBattery: true,
                isPluggedIn: pluggedIn,
                isCharging: (info[kIOPSIsChargingKey] as? Bool) ?? false,
                percentage: Int((Double(capacity) / Double(maximum) * 100).rounded())
            )
        }

        return PowerState(hasBattery: false, isPluggedIn: pluggedIn, isCharging: false, percentage: nil)
    }
}
