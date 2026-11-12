import Foundation

/// One read of a pane's folder at a time. Every tick of the folder's
/// watcher used to start a read, and a newer read makes the older one's
/// answer void: in a folder written to without a pause (a build), whose
/// read takes longer than the watcher's latency, none ever landed until
/// the writing stopped. So a tick that comes while a read is in flight
/// only says the folder changed, and the read's landing starts one more,
/// once, for everything that changed meanwhile.
public struct ReadGate: Equatable, Sendable {
    /// The folder being read, by its standardized path; nil when none is.
    public private(set) var inFlight: String?
    /// The folder in flight changed since its read began.
    public private(set) var isDirty = false

    public init() {}

    /// A read of `folder` begins now, whatever was in flight: the pane
    /// went to it (a navigation supersedes at once), or reads it again
    /// itself. Nothing is owed for what changed before.
    public mutating func begin(_ folder: URL) {
        inFlight = folder.standardizedFileURL.path
        isDirty = false
    }

    /// The watcher says `folder` changed. True: begin a read of it now.
    /// False: one is in flight; its landing will ask for the next.
    public mutating func changed(_ folder: URL) -> Bool {
        guard inFlight == folder.standardizedFileURL.path else { return true }
        isDirty = true
        return false
    }

    /// The read of `folder` came back and was not superseded. True: the
    /// folder changed while it was read, begin exactly one more. A read
    /// of another folder than the one in flight is not this gate's: false,
    /// and nothing changes.
    public mutating func landed(_ folder: URL) -> Bool {
        guard inFlight == folder.standardizedFileURL.path else { return false }
        let again = isDirty
        inFlight = nil
        isDirty = false
        return again
    }
}
