import Foundation

/// The two labels that change every second, split out of `AppState` on purpose.
///
/// If they lived on `AppState`, ticking them would invalidate every view that
/// observes it — the whole panel, pickers included — once a second. Kept here,
/// only the two small views that observe this object redraw.
final class Ticker: ObservableObject {
    @Published private(set) var elapsed: String?
    @Published private(set) var remaining: String?

    func update(elapsed newElapsed: String?, remaining newRemaining: String?) {
        if elapsed != newElapsed { elapsed = newElapsed }
        if remaining != newRemaining { remaining = newRemaining }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
