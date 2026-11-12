import Foundation

/// A folder's total size: the space on the disk of everything in it, at any
/// depth. A package is summed like any folder. A link is counted as the link
/// it is and never followed, so a loop of links can't keep a walk going.
///
/// A size is kept until `invalidate` says the folder changed. At most two
/// folders are walked at once; the others wait their turn, in the order asked.
public actor SizeCalculator {
    /// A walk asked for and not yet answered. The number tells this walk
    /// from a later one of the same folder.
    private struct Walk {
        let number: Int
        let task: Task<Int64?, Never>
    }

    private static let limit = 2

    /// By standardized path, as `walks` is.
    private var cache: [String: Int64] = [:]
    private var walks: [String: Walk] = [:]
    private var lastNumber = 0
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let total: @Sendable (String) -> Int64?

    public init() {
        total = Self.total(of:)
    }

    /// `total` is the walk itself; tests put their own.
    init(total: @escaping @Sendable (String) -> Int64?) {
        self.total = total
    }

    /// Nil when the walk was cancelled, and when `folder` is not a folder
    /// that can be read (a link to one included).
    public func size(of folder: URL) async -> Int64? {
        let path = Self.key(folder)
        if let known = cache[path] { return known }
        // Asked for again before the answer: the one walk answers both.
        if let walk = walks[path] { return await walk.task.value }
        lastNumber += 1
        let number = lastNumber
        let task = Task { await walk(path, number: number) }
        walks[path] = Walk(number: number, task: task)
        return await task.value
    }

    /// The folder changed: its size is forgotten, and that of every folder
    /// it is in. A walk of one of them on its way still answers who asked,
    /// but its number is not kept.
    public func invalidate(_ folder: URL) {
        var path = Self.key(folder)
        while true {
            cache[path] = nil
            walks[path] = nil
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty { return }
            path = parent
        }
    }

    /// Every size being waited for is answered with nil. Sizes already
    /// known are kept.
    public func cancelAll() {
        for walk in walks.values { walk.task.cancel() }
        walks.removeAll()
    }

    /// How many folders were asked for and not yet answered.
    var unanswered: Int { walks.count }

    private static func key(_ folder: URL) -> String { folder.standardizedFileURL.path }

    private func walk(_ path: String, number: Int) async -> Int64? {
        await takeTurn()
        let size = Task.isCancelled ? nil : await measure(path)
        giveTurn()
        // Invalidated or cancelled meanwhile, the walk is no longer the
        // folder's: its number may be an old one.
        if walks[path]?.number == number {
            walks[path] = nil
            if let size { cache[path] = size }
        }
        return size
    }

    /// Off the actor, so sizes already known are answered during a walk.
    private nonisolated func measure(_ path: String) async -> Int64? {
        total(path)
    }

    private func takeTurn() async {
        if running < Self.limit {
            running += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    /// The turn goes straight to the one waiting longest, if any.
    private func giveTurn() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    private static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
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
                // A folder has neither value: it counts through its items.
                if let values = try? item.resourceValues(forKeys: keySet) {
                    total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                }
                return true
            }
        }
        return total
    }
}
