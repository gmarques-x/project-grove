import Foundation

/// Runs operations on the user's files, one after the other.
///
/// What it never does:
/// - remove a user's item. An item goes to the Trash (`FileManager.trashItem`)
///   or stays. The direct removals are of the app's own: its half-written
///   copies, its empty placeholders (below), and the source of a move to
///   another volume once its copy is whole (`TreeCopier.isWhole`,
///   `TreeCopier.removeSource`).
/// - write over an item. Every item gets its final name by a rename that
///   fails when the name is taken (`renamex_np` with `RENAME_EXCL`), a new
///   folder by `mkdir`, which fails the same way. An item that is to be
///   replaced is put in the Trash first (and gets its name back when the
///   newcomer doesn't come); a name taken by something nobody was asked
///   about is a failed item, never an overwrite.
///   ExFAT and FAT have no such rename. There the name is first taken by an
///   empty placeholder, made by a call that fails when the name exists, and
///   the item is renamed over that: see `Worker.placeOverPlaceholder` for
///   what this keeps and the one thing it doesn't.
/// - leave half an item under its final name. A copy is written beside its
///   target as `.<name>.grove-partial-<uuid>` and renamed when complete.
public actor OperationRunner {
    /// Where the work is, for tests: a file or link written into a partial
    /// copy; how many bytes of the file in hand are written; an item about
    /// to be given its final name (the replaced one too, when it gets its
    /// name back); the placeholder for that name made.
    enum Stage: Sendable {
        case fileCopied(String)
        case copying(Int64)
        case placing(URL)
        /// On a volume without a rename that refuses to replace: the empty
        /// item that holds the name is made, the rename over it is next.
        case placeholder(URL)
    }

    /// `FileManager` is safe to use from any thread; the type doesn't say so.
    /// With it, what a worker needs to put a cloud item in the Trash when
    /// `manager` is refused: Finder, and the home its cloud folders are in.
    fileprivate struct Files: @unchecked Sendable {
        let manager: FileManager
        let finder: (any FinderTrash)?
        let home: URL
    }

    private let files: Files
    private let watching: (@Sendable (Stage) -> Void)?
    /// The last answer of `existingNames`: the targets that were there, by
    /// path, and the operation they were looked up for.
    private var lookedUp: (operation: Operation, targets: Set<String>)?
    private var current: CancelFlag?
    private var busy = false
    /// Runs waiting for the one in hand, oldest first.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// `finder` puts an item in the Trash when `fileManager` is refused it
    /// for want of permission, for items in the cloud folders of `home`
    /// (see `CloudTrash`); with none, such an item fails as any other.
    public init(
        fileManager: FileManager = .default, finder: (any FinderTrash)? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        files = Files(manager: fileManager, finder: finder, home: home)
        watching = nil
    }

    /// `watching` is told each stage of the work, on the thread doing it.
    init(
        fileManager: FileManager = .default, finder: (any FinderTrash)? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        watching: @escaping @Sendable (Stage) -> Void
    ) {
        files = Files(manager: fileManager, finder: finder, home: home)
        self.watching = watching
    }

    /// Throws when the operation makes no sense, before anything is written:
    /// a folder into itself or a folder inside it, an item moved to where
    /// it is, a name no item can have, nothing to do.
    public func validate(_ operation: Operation) throws(OperationRefusal) {
        if let refusal = Self.refusal(of: operation) { throw refusal }
    }

    /// The targets that already exist, in the order of the operation's
    /// items. Whether a name exists is asked of the volume itself, so it
    /// answers as the volume compares names: "notes.md" exists where
    /// "Notes.md" is, on a volume that ignores case.
    ///
    /// The answer is remembered for the run of the same operation: see `run`.
    public func existingNames(for operation: Operation) -> [URL] {
        let existing = Self.existing(for: operation)
        lookedUp = (operation, Set(existing.map(Self.key)))
        return existing
    }

    /// Does the operation and tells what was done. An operation `validate`
    /// refuses changes nothing: the outcome's summary is the refusal's sentence.
    ///
    /// `resolve` is asked what to do about a target that exists, with the
    /// target's URL. It is asked only about the targets `existingNames`
    /// found for this operation (looked up now if it wasn't called): a
    /// target that appeared since is not overwritten, whatever `resolve`
    /// would say, and its item fails with "an item with that name appeared".
    /// A rename and a new folder never ask: a name in use fails them.
    ///
    /// `progress` is called on the thread doing the work, at most ten times
    /// a second, and once more at the end.
    ///
    /// A run started while another is going waits for it.
    public func run(
        _ operation: Operation, resolve: @Sendable (URL) -> Conflict.Choice,
        progress: @Sendable (Progress) -> Void
    ) async -> Outcome {
        let known: Set<String>
        if let lookedUp, lookedUp.operation == operation {
            known = lookedUp.targets
        } else {
            known = Set(Self.existing(for: operation).map(Self.key))
        }
        lookedUp = nil
        if let refusal = Self.refusal(of: operation) {
            return Outcome(changes: [], failures: [], cancelled: false, summary: refusal.sentence)
        }

        return await inTurn { flag in
            await Self.work(
                operation, known: known, files: files, flag: flag, watching: watching,
                resolve: resolve, progress: progress)
        }
    }

    /// Waits for the run in hand, if any, then does `work` as the run in
    /// hand: one turn of the queue.
    private func inTurn<Result: Sendable>(_ work: (CancelFlag) async -> Result) async -> Result {
        if busy {
            // Resumed by the run before this one, which leaves `busy` set.
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        let flag = CancelFlag()
        current = flag
        let result = await work(flag)
        current = nil
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        return result
    }

    // MARK: Several steps in one turn, for Undo

    /// What can be done within one turn of the queue: each call is done at
    /// once, on the thread of the turn, by the same worker as a run.
    struct Turn: Sendable {
        fileprivate let files: Files
        fileprivate let flag: CancelFlag
        fileprivate let watching: (@Sendable (Stage) -> Void)?

        /// The targets of the operation that exist now, as `existingNames` has them.
        func existing(for operation: Operation) -> [URL] {
            OperationRunner.existing(for: operation)
        }

        /// The operation, as `run` does it. `resolve` is asked only about
        /// the targets in `asked`: any other that exists fails its item.
        func run(
            _ operation: Operation, asked: [URL] = [], resolve: @escaping (URL) -> Conflict.Choice = { _ in .skip }
        ) -> Outcome {
            if let refusal = OperationRunner.refusal(of: operation) {
                return Outcome(changes: [], failures: [], cancelled: false, summary: refusal.sentence)
            }
            return Worker(
                operation: operation, known: Set(asked.map(OperationRunner.key)), files: files.manager,
                finder: files.finder, home: files.home, flag: flag, watching: watching, resolve: resolve,
                progress: { _ in }
            ).run()
        }

        /// Moves `item` back to exactly `place`, the folder and the name it
        /// had (out of the Trash, or from where a move left it): by the
        /// steps of a move, so never in place of another item. Nothing is
        /// asked: when something is at `place`, the item stays where it is
        /// and the outcome says so.
        func put(_ item: URL, at place: URL) -> Outcome {
            Worker(
                operation: .move(items: [item], to: place.deletingLastPathComponent()), known: [],
                files: files.manager, finder: files.finder, home: files.home, flag: flag, watching: watching,
                resolve: { _ in .skip }, progress: { _ in }
            ).put(at: place)
        }
    }

    /// For Undo: does `steps` as one turn of the queue, off the actor. No
    /// other run comes between them, and what they look at first is as
    /// fresh as what they then do: the turn waits before `steps` begin,
    /// not inside them. `cancel` stops them as it stops a run.
    ///
    /// What `existingNames` remembered is forgotten, before and after, as a
    /// run forgets it: the turn may change what is at those names. So the
    /// app must not offer undo or redo between its own `existingNames` and
    /// the `run` that follows it.
    func turn<Result: Sendable>(_ steps: @Sendable (Turn) -> Result) async -> Result {
        lookedUp = nil
        let result = await inTurn { flag in
            await Self.taking(Turn(files: files, flag: flag, watching: watching), steps)
        }
        lookedUp = nil
        return result
    }

    @concurrent private static func taking<Result: Sendable>(
        _ turn: Turn, _ steps: @Sendable (Turn) -> Result
    ) async -> Result {
        steps(turn)
    }

    /// Stops the run in hand after the file it is on. What was done stays;
    /// the item it was in the middle of is left as it was. With nothing
    /// running, nothing happens.
    public func cancel() {
        current?.cancel()
    }

    /// The work itself, off the actor, so that `cancel` gets through.
    @concurrent private static func work(
        _ operation: Operation, known: Set<String>, files: Files, flag: CancelFlag,
        watching: (@Sendable (Stage) -> Void)?,
        resolve: @Sendable (URL) -> Conflict.Choice, progress: @Sendable (Progress) -> Void
    ) async -> Outcome {
        withoutActuallyEscaping(resolve) { resolve in
            withoutActuallyEscaping(progress) { progress in
                Worker(
                    operation: operation, known: known, files: files.manager, finder: files.finder,
                    home: files.home, flag: flag, watching: watching, resolve: resolve, progress: progress
                ).run()
            }
        }
    }

    // MARK: Before anything is written

    private static func refusal(of operation: Operation) -> OperationRefusal? {
        switch operation {
        case let .copy(items, folder), let .move(items, folder):
            guard !items.isEmpty else { return .nothingToDo }
            if let item = items.first(where: { isInside(folder, of: $0) }) { return .intoItself(item) }
            if case .move = operation,
                let item = items.first(where: { isSameFolder($0.deletingLastPathComponent(), folder) })
            {
                return .ontoItself(item)
            }
            return nil
        case let .duplicate(items), let .trash(items):
            return items.isEmpty ? .nothingToDo : nil
        case let .rename(item, name):
            if let reason = whyNot(name) { return .badName(name, reason: reason) }
            return item.lastPathComponent == name ? .nothingToDo : nil
        case let .newFolder(_, name):
            if let reason = whyNot(name) { return .badName(name, reason: reason) }
            return nil
        }
    }

    /// Why an item can't have this name, nil when it can.
    private static func whyNot(_ name: String) -> String? {
        if name.isEmpty { return "A name can't be empty." }
        if name.contains("/") { return "A name can't have a “/” in it." }
        if name == "." || name == ".." { return "“\(name)” is not a name an item can have." }
        if name.contains("\0") { return "A name can't have that character in it." }
        if name.utf8.count > 255 { return "That name is too long." }
        return nil
    }

    private static func existing(for operation: Operation) -> [URL] {
        switch operation {
        case let .copy(items, folder), let .move(items, folder):
            return items.map { target(for: $0, in: folder) }.filter(exists)
        case let .rename(item, name):
            let target = target(for: item, in: item.deletingLastPathComponent(), named: name)
            // Its own name in other capitals is not another item's.
            guard let there = FileIdentity.of(target.path)?.identity else { return [] }
            if there == FileIdentity.of(item.path)?.identity, isSameName(item.lastPathComponent, name) {
                return []
            }
            return [target]
        case let .newFolder(folder, name):
            let target = folder.appendingPathComponent(name, isDirectory: true)
            return exists(target) ? [target] : []
        case .duplicate, .trash:
            return []
        }
    }

    // MARK: Paths

    /// Where `item` goes in `folder`, under its own name or `name`. A
    /// folder's URL says it is one, as the URLs of a listing do; nothing
    /// else is read from the disk for it.
    static func target(for item: URL, in folder: URL, named name: String? = nil) -> URL {
        folder.appendingPathComponent(
            name ?? item.lastPathComponent, isDirectory: FileIdentity.of(item.path)?.kind == S_IFDIR)
    }

    /// Whether two names differ at most by capitals or by the way their
    /// accents are written: `Conflict.sameName` as a volume that ignores
    /// case has it. Only ever used together with the volume's own word
    /// that both are the same item: it decides nothing by itself.
    static func isSameName(_ one: String, _ other: String) -> Bool {
        Conflict.sameName(one, other, caseSensitive: false)
    }

    /// Something is at the URL: a file, a folder, or a link, even to nothing.
    static func exists(_ url: URL) -> Bool {
        FileIdentity.of(url.path) != nil
    }

    /// A URL as a key: URLs are kept as given, so two of one place are
    /// compared by their standardized paths.
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// The path with the links in it followed.
    private static func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Whether `folder` is `item` or somewhere inside it. By the paths, with
    /// the links in them followed (those in the item's folder, not the item
    /// itself: a link is its own item, not what it points at); and by what
    /// is on the disk, where a folder is itself under any spelling of its name.
    static func isInside(_ folder: URL, of item: URL) -> Bool {
        let inner = resolved(folder)
        let item = item.standardizedFileURL
        let parent = resolved(item.deletingLastPathComponent())
        let outer = (parent == "/" ? "" : parent) + "/" + item.lastPathComponent
        if inner == outer || inner.hasPrefix(outer + "/") { return true }

        guard let (itself, kind) = FileIdentity.of(outer), kind == S_IFDIR else { return false }
        var path = inner
        while true {
            if FileIdentity.of(path, followingLinks: true)?.identity == itself { return true }
            guard path != "/", !path.isEmpty else { return false }
            path = (path as NSString).deletingLastPathComponent
        }
    }

    private static func isSameFolder(_ one: URL, _ other: URL) -> Bool {
        let (first, second) = (resolved(one), resolved(other))
        if first == second { return true }
        guard let here = FileIdentity.of(first, followingLinks: true)?.identity else { return false }
        return here == FileIdentity.of(second, followingLinks: true)?.identity
    }
}

// MARK: - Cancelling and progress

/// Set by `cancel`, read by the work between two files.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Counts what is done and tells it, no more often than ten times a second.
/// Used by the one thread doing the work.
final class Reporter {
    private static let interval: Duration = .milliseconds(100)

    private let send: (Progress) -> Void
    private let watching: (@Sendable (OperationRunner.Stage) -> Void)?
    /// The bytes to copy, nil when the run is counted in items.
    private var bytes: Int64?
    private var itemsTotal = 0
    private var itemsDone = 0
    /// Bytes of the items done with, of the files written of the item in
    /// hand, and written of the file in hand.
    private var finished: Int64 = 0
    private var inItem: Int64 = 0
    private var inFile: Int64 = 0
    private var last: ContinuousClock.Instant?

    init(send: @escaping (Progress) -> Void, watching: (@Sendable (OperationRunner.Stage) -> Void)?) {
        self.send = send
        self.watching = watching
    }

    /// The bytes of the items not done with.
    var bytesLeft: Int64 { max((bytes ?? 0) - finished, 0) }

    func begin(bytes: Int64?, items: Int) {
        self.bytes = bytes
        itemsTotal = items
        report()
    }

    func fileProgress(bytes copied: Int64) {
        inFile = copied
        watching?(.copying(copied))
        report()
    }

    func fileFinished(bytes: Int64) {
        inFile = 0
        inItem += bytes
        report()
    }

    /// The item is done with, however it went: its bytes are no longer to come.
    func itemFinished(bytes: Int64) {
        itemsDone += 1
        finished += bytes
        inItem = 0
        inFile = 0
        report()
    }

    /// The item in hand was given up: what was written of it is gone.
    func itemAbandoned() {
        inItem = 0
        inFile = 0
    }

    /// The last word, whenever the one before was.
    func finish() {
        report(always: true)
    }

    private func report(always: Bool = false) {
        let now = ContinuousClock.now
        if !always, let last, now - last < Self.interval { return }
        last = now
        if let bytes {
            send(Progress(
                done: min(finished + inItem + inFile, bytes), total: bytes,
                itemsDone: itemsDone, itemsTotal: itemsTotal))
        } else {
            send(Progress(
                done: Int64(itemsDone), total: Int64(itemsTotal),
                itemsDone: itemsDone, itemsTotal: itemsTotal))
        }
    }
}
