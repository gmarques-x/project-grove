import Foundation

/// A line a panel shows after a fallback (the VPN's "WireGuard's menu
/// didn't open", OneDrive's "Open OneDrive's settings from its activity
/// window"). It outlives the panel closing (the fallback brings the app
/// forward, which puts the panel away): the next opening shows it, the one
/// after clears it, and so does a new click on the button.
public struct FallbackHint<Reason: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var reason: Reason?
    private var seen = false

    public init() {}

    public mutating func set(_ reason: Reason) {
        self.reason = reason
        seen = false
    }

    public mutating func clear() {
        reason = nil
        seen = false
    }

    /// The panel opened.
    public mutating func opened() {
        guard reason != nil else { return }
        if seen { clear() } else { seen = true }
    }
}
