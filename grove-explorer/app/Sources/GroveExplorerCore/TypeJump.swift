import Foundation

/// The letters typed in a list to jump to a name: they add up while they
/// follow each other, and a second's pause starts again (spec §6).
public struct TypeJump: Sendable {
    public static let pause: TimeInterval = 1

    private var text = ""
    private var last: Date?

    public init() {}

    /// What has been typed, `characters` included: the prefix to look for.
    public mutating func typed(_ characters: String, at now: Date) -> String {
        if let last, now.timeIntervalSince(last) >= Self.pause { text = "" }
        text += characters
        last = now
        return text
    }

    /// Whether letters were typed less than a pause ago: what is typed now
    /// (a space, say) goes on with them.
    public func isUnderWay(at now: Date) -> Bool {
        guard let last, !text.isEmpty else { return false }
        return now.timeIntervalSince(last) < Self.pause
    }

    public mutating func reset() {
        text = ""
        last = nil
    }
}
