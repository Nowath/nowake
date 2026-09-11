import Foundation
import IOKit

/// Tracks whether the laptop lid is open or shut.
///
/// Closing the lid fires no display-sleep notification — macOS simply drops the
/// built-in display — so the only reliable signal is IOPMrootDomain's
/// `AppleClamshellState`, polled on a short interval.
final class ClamshellMonitor {

    private(set) var isLidClosed = false
    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    private let interval: TimeInterval = 2.0

    static func readLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.boolValue ?? false
    }

    func start() {
        isLidClosed = Self.readLidClosed()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = Self.readLidClosed()
            guard current != self.isLidClosed else { return }
            self.isLidClosed = current
            self.onChange?(current)
        }
        // .common so it keeps ticking while the popover is up
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
