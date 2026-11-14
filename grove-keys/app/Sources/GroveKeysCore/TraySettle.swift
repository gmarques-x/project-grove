import Foundation

/// When the tray's watcher lists the menu bar again (spec
/// 2026-11-14-bar-tray-design, "Count freshness"): after an app launches or
/// quits, once things have settled for 2 s; after MenuBarAgent says its
/// bar changed, for half a second. Events that come before the listing
/// push it back, so a burst (a login's launches) is one listing; never more
/// than `longest` after the first event waiting, so a burst that never
/// settles still lists. No timer polls: the watcher sets one for `due`
/// each time an event moves it, and `fire` says whether that timer's time
/// has come. The clock is passed in.
public struct TraySettle: Sendable {
    public enum Event: Sendable {
        case launched, quit, barChanged
    }

    /// The settle after an app launches or quits.
    public static let appDelay: TimeInterval = 2
    /// The settle after MenuBarAgent's bar changes.
    public static let barDelay: TimeInterval = 0.5
    /// The longest a listing waits after the first event it is for.
    public static let longest: TimeInterval = 10

    /// The first event the pending listing is for.
    private var first: Date?
    /// When the pending listing runs; nil when none is pending.
    public private(set) var due: Date?

    public init() {}

    private static func delay(_ event: Event) -> TimeInterval {
        switch event {
        case .launched, .quit: appDelay
        case .barChanged: barDelay
        }
    }

    /// An event at `time`: when the listing now runs. It never comes sooner
    /// than before (a short settle doesn't cut a longer one short).
    @discardableResult
    public mutating func note(_ event: Event, at time: Date) -> Date {
        let first = self.first ?? time
        self.first = first
        let settled = max(due ?? time, time.addingTimeInterval(Self.delay(event)))
        let next = min(settled, first.addingTimeInterval(Self.longest))
        due = next
        return next
    }

    /// A timer set for an earlier `due` went off at `time`: true when the
    /// listing is due now (it is no longer pending); false when nothing is
    /// pending or a later event moved it on.
    public mutating func fire(at time: Date) -> Bool {
        guard let due, time >= due else { return false }
        listed()
        return true
    }

    /// The bar was listed for another reason (the panel opened): what was
    /// pending is covered.
    public mutating func listed() {
        first = nil
        due = nil
    }

    /// The times `events` (in time order) list at, as a watcher whose timer
    /// goes off exactly at `due` would.
    public static func listings(_ events: [(Event, Date)]) -> [Date] {
        var settle = TraySettle()
        var times: [Date] = []
        for (event, time) in events {
            if let due = settle.due, due <= time, settle.fire(at: due) { times.append(due) }
            settle.note(event, at: time)
        }
        if let due = settle.due, settle.fire(at: due) { times.append(due) }
        return times
    }
}
