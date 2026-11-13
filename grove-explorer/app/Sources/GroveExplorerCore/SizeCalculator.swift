import Foundation

/// A folder's total size: the lengths of all the files in it, at any depth,
/// as the list shows a file's own. A package is summed like any folder. A
/// link counts nothing and is never followed, so a loop of links can't keep
/// a walk going.
///
/// A size is kept until `invalidate` says the folder changed. At most two
/// folders are walked at once; the others wait their turn, in the order asked.
public actor SizeCalculator {
    /// What a walk came back with.
    public enum Answer: Equatable, Sendable {
        case total(Int64)
        /// Not a folder that can be read (a link to one included): no size
        /// will come for it as it is ("--").
        case unreadable
        /// The walk was cancelled on its way (the folder changed, or its
        /// size is no longer wanted): its size is still to come.
        case cancelled

        public var total: Int64? {
            if case .total(let total) = self { total } else { nil }
        }
    }

    /// A walk asked for and not yet answered. The number tells this walk
    /// from a later one of the same folder.
    private struct Walk {
        let number: Int
        let task: Task<Answer, Never>
    }

    private static let limit = 2

    /// By standardized path, as `walks` is.
    private var cache: [String: Int64] = [:]
    private var walks: [String: Walk] = [:]
    private var lastNumber = 0
    private var running = 0
    /// Walks waiting for a turn, oldest first. Each is resumed with whether
    /// it got one: a walk cancelled while waiting is told no at once.
    private var waiting: [(number: Int, resume: CheckedContinuation<Bool, Never>)] = []
    private let total: @Sendable (String) -> Int64?

    public init() {
        total = Self.total(of:)
    }

    /// `total` is the walk itself; tests put their own.
    init(total: @escaping @Sendable (String) -> Int64?) {
        self.total = total
    }

    /// Nil when the walk was cancelled, and when `folder` is not a folder
    /// that can be read (a link to one included): `answer(for:)` tells the two apart.
    public func size(of folder: URL) async -> Int64? {
        await answer(for: folder).total
    }

    /// The folder's total, or why there is none.
    public func answer(for folder: URL) async -> Answer {
        let path = Self.key(folder)
        if let known = cache[path] { return .total(known) }
        // Asked for again before the answer: the one walk answers both.
        if let walk = walks[path] { return await walk.task.value }
        lastNumber += 1
        let number = lastNumber
        let task = Task { await walk(path, number: number) }
        walks[path] = Walk(number: number, task: task)
        return await task.value
    }

    /// The folder changed: its size is forgotten, and that of every folder
    /// it is in. A walk of one of them on its way is cancelled (its number
    /// would be an old one): who asked gets `.cancelled` and asks again.
    public func invalidate(_ folder: URL) {
        var path = Self.key(folder)
        while true {
            cache[path] = nil
            if let walk = walks.removeValue(forKey: path) { cancel(walk) }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty { return }
            path = parent
        }
    }

    /// The folder's size is no longer wanted (its row is not shown any
    /// more): a walk of it on its way is cancelled and who asked gets `.cancelled`.
    /// Nothing is forgotten, and no other walk is touched; asked for again,
    /// it is walked from the start.
    public func cancel(_ folder: URL) {
        if let walk = walks.removeValue(forKey: Self.key(folder)) { cancel(walk) }
    }

    /// Every size being waited for is answered `.cancelled`. Sizes already
    /// known are kept.
    public func cancelAll() {
        for walk in walks.values { cancel(walk) }
        walks.removeAll()
    }

    /// A running walk stops at its next item; a waiting one leaves the
    /// queue now rather than when a turn comes free.
    private func cancel(_ walk: Walk) {
        walk.task.cancel()
        if let place = waiting.firstIndex(where: { $0.number == walk.number }) {
            waiting.remove(at: place).resume.resume(returning: false)
        }
    }

    /// How many folders were asked for and not yet answered.
    var unanswered: Int { walks.count }

    private static func key(_ folder: URL) -> String { folder.standardizedFileURL.path }

    private func walk(_ path: String, number: Int) async -> Answer {
        guard await takeTurn(number) else { return .cancelled }
        let measured = await measure(path)
        giveTurn()
        // Cancelled (also by `invalidate`), the walk is no longer in the
        // books and its number, if it got to one, is not given: whatever
        // the walk came back with, nothing is known of the folder.
        guard !Task.isCancelled, walks[path]?.number == number else { return .cancelled }
        walks[path] = nil
        guard let measured else { return .unreadable }
        cache[path] = measured
        return .total(measured)
    }

    /// Off the actor, so sizes already known are answered during a walk.
    private nonisolated func measure(_ path: String) async -> Int64? {
        total(path)
    }

    /// False when the walk was cancelled before its turn came.
    private func takeTurn(_ number: Int) async -> Bool {
        if Task.isCancelled { return false }
        if running < Self.limit {
            running += 1
            return true
        }
        return await withCheckedContinuation { waiting.append((number, $0)) }
    }

    /// The turn goes straight to the one waiting longest, if any.
    private func giveTurn() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume.resume(returning: true)
        }
    }

    private static let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileSizeKey, .fileSizeKey]
    private static let keySet = Set(keys)

    /// The walk. Nil when cancelled, or when `path` is not a readable folder.
    private static func total(of path: String) -> Int64? {
        // Asked once, before the walk: the enumerator reports a folder that
        // is missing, closed or a link only as one more error on the way.
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        close(descriptor)
        // It goes into packages and hidden folders, and not through links.
        // What can't be read inside is left out and the walk goes on.
        guard let items = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return nil }

        var total: Int64 = 0
        var more = true
        while more {
            if Task.isCancelled { return nil }
            // The pool: a walk of a million items would otherwise keep
            // every URL until its end.
            more = autoreleasepool {
                guard let item = items.nextObject() as? URL else { return false }
                // Files only: a folder counts through its items, and a
                // link's own length is that of the path written in it.
                if let values = try? item.resourceValues(forKeys: keySet), values.isRegularFile == true {
                    total += Int64(values.totalFileSize ?? values.fileSize ?? 0)
                }
                return true
            }
        }
        return total
    }
}
