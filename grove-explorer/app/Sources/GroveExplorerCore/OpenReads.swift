import Foundation

/// The reads of the folders open in place in one pane's tab (spec §16):
/// one at a time per folder (`ReadGate`), at most `atOnce` folders being
/// read at once (⌥→ opens hundreds), the rest waiting in order.
///
/// Each read carries a number the caller draws from one counter that only
/// goes up, for every pane, tab and folder: a read is the answer only when
/// it is its folder's latest. A read begun for another tab (the pane
/// showed it before), or before the folder was closed and opened again,
/// never has the number of a read begun since, so its landing can neither
/// be taken nor clear the read that is.
public struct OpenReads: Equatable, Sendable {
    /// Folders read at once.
    public static let atOnce = 8

    private struct Record: Equatable, Sendable {
        var gate = ReadGate()
        /// The latest read of it begun, while it is on its way.
        var number: Int?
    }

    /// By the folder's standardized path.
    private var records: [String: Record] = [:]
    /// Wanted, not begun: the next first.
    private var waiting: [URL] = []

    public init() {}

    /// How many folders are being read now.
    public var reading: Int { records.values.reduce(0) { $0 + ($1.number == nil ? 0 : 1) } }

    /// A read of `folder` is wanted. True: begin it now (`begun`); false:
    /// it waits its turn (`next`). A folder already on its way is read
    /// again at once (the new read supersedes), as for a watcher's tick.
    public mutating func want(_ folder: URL) -> Bool {
        let path = folder.standardizedPath
        if records[path]?.number != nil || reading < Self.atOnce { return true }
        if !waiting.contains(where: { $0.standardizedPath == path }) { waiting.append(folder) }
        return false
    }

    /// The read numbered `number` of `folder` begins now.
    public mutating func begun(_ folder: URL, number: Int) {
        let path = folder.standardizedPath
        waiting.removeAll { $0.standardizedPath == path }
        var record = records[path] ?? Record()
        record.gate.begin(folder)
        record.number = number
        records[path] = record
    }

    /// Whether the read numbered `number` of `folder` is its latest, on its way.
    public func isLatest(_ folder: URL, number: Int) -> Bool {
        records[folder.standardizedPath]?.number == number
    }

    /// Whether `folder` is being read or waits to be.
    public func isWanted(_ folder: URL) -> Bool {
        let path = folder.standardizedPath
        return records[path]?.number != nil || waiting.contains { $0.standardizedPath == path }
    }

    /// The read numbered `number` came back and is taken. True: the folder
    /// changed while it was read, read it once more. A read that is not
    /// the latest changes nothing and says false.
    public mutating func landed(_ folder: URL, number: Int) -> Bool {
        let path = folder.standardizedPath
        guard var record = records[path], record.number == number else { return false }
        record.number = nil
        let again = record.gate.landed(folder)
        records[path] = record
        return again
    }

    /// The read numbered `number` came back and is not the pane's any more
    /// (`PaneRows.isCurrent`): forgotten, if it is the latest; a read
    /// begun since is left alone.
    public mutating func dropped(_ folder: URL, number: Int) {
        let path = folder.standardizedPath
        if records[path]?.number == number { records[path] = nil }
    }

    /// The watcher says `folder` changed. True: read it now; false: a read
    /// of it is on its way, whose landing reads once more.
    public mutating func changed(_ folder: URL) -> Bool {
        let path = folder.standardizedPath
        var record = records[path] ?? Record()
        let now = record.gate.changed(folder)
        if records[path] != nil { records[path] = record }
        return now
    }

    /// The next waiting folder whose turn it is, taken off the queue; nil
    /// while `atOnce` are being read or none waits.
    public mutating func next() -> URL? {
        guard reading < Self.atOnce, !waiting.isEmpty else { return nil }
        return waiting.removeFirst()
    }

    /// Only the reads of `folders` (by standardized path) are kept, on
    /// their way or waiting: the others' folders closed or no longer show.
    public mutating func keep(_ folders: Set<String>) {
        records = records.filter { folders.contains($0.key) }
        waiting.removeAll { !folders.contains($0.standardizedPath) }
    }
}
