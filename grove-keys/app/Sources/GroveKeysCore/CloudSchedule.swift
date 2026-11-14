import Foundation

/// When the cloud tracker's thread has something to do, and which passes it
/// should start: re-walks after the cap and retries of a refused provider.
/// One rule decides both what is due and the deadline the thread sleeps
/// until, so the deadline is never in the past while nothing is due (the
/// thread would spin). The clock is passed in.
public struct CloudSchedule: Sendable {
    /// The longest the thread sleeps (the 30 minutes are checked, the roots re-read).
    public static let tick: TimeInterval = 60
    /// A provider that refused its files is tried again this rarely.
    public static let refusedRetry: TimeInterval = 600
    /// A root's re-walk after the cap is not repeated sooner than this.
    public static let rescanGap: TimeInterval = 60

    /// A walk waiting or under way, as far as the schedule cares.
    public struct Walk: Equatable, Sendable {
        public let root: URL
        public let isWholeRoot: Bool
        /// It doesn't start before (events asked for it and settle first).
        public let notBefore: Date

        public init(root: URL, isWholeRoot: Bool, notBefore: Date) {
            self.root = root
            self.isWholeRoot = isWholeRoot
            self.notBefore = notBefore
        }
    }

    /// Refused roots (by path): when refused, or last tried again.
    private var refused: [String: Date] = [:]
    private var lastRescan: [String: Date] = [:]
    /// When the roots are next re-read.
    public var nextRootsCheck = Date.distantPast

    public init() {}

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    public func isRefused(_ root: URL) -> Bool { refused[Self.key(root)] != nil }

    /// macOS refused the root's files (again): tried in ten minutes, counted
    /// from the first refusal.
    public mutating func refuse(_ root: URL, at now: Date) {
        if refused[Self.key(root)] == nil { refused[Self.key(root)] = now }
    }

    public mutating func clearRefusal(_ root: URL) { refused[Self.key(root)] = nil }

    /// The root went: nothing about it is kept.
    public mutating func forget(_ root: URL) {
        refused[Self.key(root)] = nil
        lastRescan[Self.key(root)] = nil
    }

    public mutating func started(rescan root: URL, at now: Date) { lastRescan[Self.key(root)] = now }
    /// A retry started: the next is ten minutes on (it stays refused until a walk gets in).
    public mutating func started(retry root: URL, at now: Date) { refused[Self.key(root)] = now }

    /// Each re-walk after the cap that can happen, and when: there's room,
    /// the root isn't refused, no whole-root walk of it is waiting or under
    /// way, a minute after the last.
    private func rescans(pending: CloudPending, walks: [Walk]) -> [(URL, Date)] {
        guard pending.hasRoom else { return [] }
        return pending.rootsNeedingRescan.compactMap { root in
            let key = Self.key(root)
            guard refused[key] == nil,
                  !walks.contains(where: { $0.isWholeRoot && Self.key($0.root) == key })
            else { return nil }
            return (root, (lastRescan[key] ?? .distantPast) + Self.rescanGap)
        }
    }

    /// Each retry of a refused root still followed, with no walk of it, and when.
    private func retries(roots: [URL], walks: [Walk]) -> [(URL, Date)] {
        roots.compactMap { root in
            let key = Self.key(root)
            guard let at = refused[key], !walks.contains(where: { Self.key($0.root) == key }) else { return nil }
            return (root, at + Self.refusedRetry)
        }
    }

    public func rescansDue(at now: Date, pending: CloudPending, walks: [Walk]) -> [URL] {
        rescans(pending: pending, walks: walks).filter { $0.1 <= now }.map(\.0)
    }

    public func retriesDue(at now: Date, roots: [URL], walks: [Walk]) -> [URL] {
        retries(roots: roots, walks: walks).filter { $0.1 <= now }.map(\.0)
    }

    /// The soonest of: a minute on, the roots' check, the next re-read, a
    /// walk's start, a re-walk or a retry (by the same rules as their `…Due`).
    public func deadline(at now: Date, pending: CloudPending, walks: [Walk], roots: [URL]) -> Date {
        var next = min(now + Self.tick, nextRootsCheck)
        if let read = pending.nextRead { next = min(next, read) }
        for walk in walks { next = min(next, walk.notBefore) }
        for (_, at) in rescans(pending: pending, walks: walks) { next = min(next, at) }
        for (_, at) in retries(roots: roots, walks: walks) { next = min(next, at) }
        return next
    }
}

/// Values sent on at most once per `interval`: the first at once, then
/// those offered meanwhile folded into one send at the interval's end, the
/// latest kept (the cloud summary to the main thread, twice a second).
public struct CloudThrottle<Value: Sendable>: Sendable {
    public static var summaryInterval: TimeInterval { 0.5 }

    public let interval: TimeInterval
    private var latest: Value?
    private var scheduled = false
    private var lastSent = Date.distantPast

    public init(interval: TimeInterval) { self.interval = interval }

    /// Keeps `value`; the delay after which to `flush`, or nil when a
    /// flush is already coming (it will send this value).
    public mutating func offer(_ value: Value, at now: Date) -> TimeInterval? {
        latest = value
        guard !scheduled else { return nil }
        scheduled = true
        return max(0, lastSent.timeIntervalSince(now) + interval)
    }

    /// The value to send now (nil: nothing new).
    public mutating func flush(at now: Date) -> Value? {
        scheduled = false
        guard let value = latest else { return nil }
        latest = nil
        lastSent = now
        return value
    }
}
