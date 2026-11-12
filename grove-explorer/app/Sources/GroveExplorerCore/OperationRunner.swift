import Foundation

/// Runs operations on the user's files, one after the other.
///
/// What it never does:
/// - remove a user's item. An item goes to the Trash (`FileManager.trashItem`)
///   or stays. The two direct removals are of the app's own half-written
///   copies, and of the source of a move to another volume once its copy is
///   whole (`TreeCopier.isWhole`, `TreeCopier.removeSource`).
/// - write over an item. Every item gets its final name by a rename that
///   fails when the name is taken (`renamex_np` with `RENAME_EXCL`), a new
///   folder by `mkdir`, which fails the same way. An item that is to be
///   replaced is put in the Trash first; a name taken by something nobody
///   was asked about is a failed item, never an overwrite.
/// - leave half an item under its final name. A copy is written beside its
///   target as `.<name>.grove-partial-<uuid>` and renamed when complete.
public actor OperationRunner {
    /// Where the work is, for tests: a file or link written into a partial
    /// copy; how many bytes of the file in hand are written; an item about
    /// to be given its final name.
    enum Stage: Sendable {
        case fileCopied(String)
        case copying(Int64)
        case placing(URL)
    }

    /// `FileManager` is safe to use from any thread; the type doesn't say so.
    private struct Files: @unchecked Sendable {
        let manager: FileManager
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

    public init(fileManager: FileManager = .default) {
        files = Files(manager: fileManager)
        watching = nil
    }

    /// `watching` is told each stage of the work, on the thread doing it.
    init(fileManager: FileManager = .default, watching: @escaping @Sendable (Stage) -> Void) {
        files = Files(manager: fileManager)
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

        if busy {
            // Resumed by the run before this one, which leaves `busy` set.
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        let flag = CancelFlag()
        current = flag
        let outcome = await Self.work(
            operation, known: known, files: files, flag: flag, watching: watching,
            resolve: resolve, progress: progress)
        current = nil
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        return outcome
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
                    operation: operation, known: known, files: files.manager, flag: flag,
                    watching: watching, resolve: resolve, progress: progress
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
            guard let there = FileIdentity.of(target.path)?.identity,
                there != FileIdentity.of(item.path)?.identity
            else { return [] }
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
    fileprivate static func target(for item: URL, in folder: URL, named name: String? = nil) -> URL {
        folder.appendingPathComponent(
            name ?? item.lastPathComponent, isDirectory: FileIdentity.of(item.path)?.kind == S_IFDIR)
    }

    /// Something is at the URL: a file, a folder, or a link, even to nothing.
    fileprivate static func exists(_ url: URL) -> Bool {
        FileIdentity.of(url.path) != nil
    }

    /// A URL as a key: URLs are kept as given, so two of one place are
    /// compared by their standardized paths.
    fileprivate static func key(_ url: URL) -> String {
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
    fileprivate static func isInside(_ folder: URL, of item: URL) -> Bool {
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

// MARK: - One run

/// How giving an item its final name went.
private enum Placed {
    case at(URL)
    /// The name is taken.
    case taken
    /// The volume has no rename that refuses to replace.
    case unsafe
    /// The name is on another volume than the item.
    case otherVolume
    case failed(Int32)
}

/// One run of one operation, on the thread it was started on.
private final class Worker {
    private let operation: Operation
    private let known: Set<String>
    private let files: FileManager
    private let flag: CancelFlag
    private let watching: (@Sendable (OperationRunner.Stage) -> Void)?
    private let resolve: (URL) -> Conflict.Choice
    private let reporter: Reporter
    private let copier: TreeCopier

    private var changes: [Change] = []
    private var failures: [ItemFailure] = []
    private var done = 0
    private var skipped = 0
    private var cancelled = false
    private var shortage: Shortage?

    init(
        operation: Operation, known: Set<String>, files: FileManager, flag: CancelFlag,
        watching: (@Sendable (OperationRunner.Stage) -> Void)?,
        resolve: @escaping (URL) -> Conflict.Choice, progress: @escaping (Progress) -> Void
    ) {
        self.operation = operation
        self.known = known
        self.files = files
        self.flag = flag
        self.watching = watching
        self.resolve = resolve
        reporter = Reporter(send: progress, watching: watching)
        copier = TreeCopier(flag: flag, reporter: reporter, watching: watching)
    }

    func run() -> Outcome {
        switch operation {
        case let .copy(items, folder): transfer(items, to: folder, moving: false)
        case let .move(items, folder): transfer(items, to: folder, moving: true)
        case let .duplicate(items): duplicate(items)
        case let .rename(item, name): rename(item, to: name)
        case let .newFolder(folder, name): makeFolder(in: folder, name: name)
        case let .trash(items): trash(items)
        }
        reporter.finish()
        return Outcome(
            changes: changes, failures: failures, cancelled: cancelled,
            summary: Wording.summary(
                of: operation, done: done, skipped: skipped, failed: failures.count,
                cancelled: cancelled, shortage: shortage))
    }

    // MARK: Copy and move

    private func transfer(_ items: [URL], to folder: URL, moving: Bool) {
        // The volume the target folder is on; nil when there is no such folder.
        var volume: dev_t?
        if let (identity, kind) = FileIdentity.of(folder.path, followingLinks: true), kind == S_IFDIR {
            volume = identity.device
        }
        // Bytes are copied for a copy, and for a move to another volume.
        let sizes = items.map { item -> Int64 in
            guard let volume else { return 0 }
            if moving, FileIdentity.of(item.path)?.identity.device == volume { return 0 }
            return copier.size(of: item.path)
        }
        let bytes = sizes.reduce(0, +)
        reporter.begin(bytes: bytes > 0 ? bytes : nil, items: items.count)

        for (item, size) in zip(items, sizes) {
            if flag.isCancelled {
                cancelled = true
                break
            }
            if let volume {
                transfer(item, to: folder, on: volume, moving: moving)
            } else {
                fail(item, "the folder “\(folder.lastPathComponent)” is not there")
            }
            if cancelled || shortage != nil { break }
            reporter.itemFinished(bytes: size)
        }
    }

    private func transfer(_ item: URL, to folder: URL, on volume: dev_t, moving: Bool) {
        guard let (source, kind) = FileIdentity.of(item.path) else {
            fail(item, code: errno)
            return
        }
        var target = OperationRunner.target(for: item, in: folder)
        var replacing = false
        var nextFree: (() -> URL?)?

        if OperationRunner.exists(target) {
            // Not there when the names were looked up: nobody was asked
            // about it, so no answer is about it.
            guard known.contains(OperationRunner.key(target)) else {
                fail(item, Self.appeared)
                return
            }
            switch resolve(target) {
            case .skip:
                skipped += 1
                return
            case .keepBoth:
                let taken = target
                let next = { Self.freeName(beside: taken, folder: kind == S_IFDIR) }
                guard let free = next() else {
                    fail(item, "no free name was found for it")
                    return
                }
                target = free
                nextFree = next
            case .replace:
                // Either would send the item itself to the Trash.
                guard FileIdentity.of(target.path)?.identity != source else {
                    fail(item, "it can't replace itself")
                    return
                }
                guard !OperationRunner.isInside(item.deletingLastPathComponent(), of: target) else {
                    fail(item, "it is inside the item it would replace")
                    return
                }
                replacing = true
            }
        }

        // Where the replaced item is in the Trash, once it is there.
        var replaced: URL?

        // On one volume a move is one rename.
        if moving, source.device == volume {
            if replacing {
                guard let inTrash = moveToTrash(target, for: item) else { return }
                replaced = inTrash
            }
            switch place(item.path, at: target, orAt: nextFree) {
            case let .at(final):
                if let replaced { changes.append(.replaced(original: target, inTrash: replaced)) }
                changes.append(.moved(from: item, to: final))
                done += 1
                return
            case .otherVolume:
                break  // Not one volume after all: copied, below.
            case let other:
                if let replaced { changes.append(.trashed(original: target, inTrash: replaced)) }
                fail(item, placed: other)
                return
            }
        }

        // Copied whole under a partial name; only then is the old one put
        // in the Trash, and the copy given its name.
        guard let partial = copyToPartial(item, for: target, on: folder) else {
            if let replaced { changes.append(.trashed(original: target, inTrash: replaced)) }
            return
        }
        if replacing, replaced == nil {
            guard let inTrash = moveToTrash(target, for: item) else {
                TreeCopier.removeTemporary(partial.path)
                return
            }
            replaced = inTrash
        }
        switch place(partial.path, at: target, orAt: nextFree) {
        case let .at(final):
            if let replaced { changes.append(.replaced(original: target, inTrash: replaced)) }
            guard moving else {
                changes.append(.created(final))
                done += 1
                return
            }
            // The source goes only when the copy is all of it.
            if !TreeCopier.isWhole(final.path, of: item.path) {
                changes.append(.created(final))
                fail(item, "it changed while it was copied: the copy is there, and it was left where it is")
            } else if !TreeCopier.removeSource(item.path, copiedTo: final.path) {
                changes.append(.created(final))
                fail(item, "it was copied, but could not be removed from where it was")
            } else {
                changes.append(.moved(from: item, to: final))
                done += 1
            }
        case let other:
            TreeCopier.removeTemporary(partial.path)
            if let replaced { changes.append(.trashed(original: target, inTrash: replaced)) }
            fail(item, placed: other)
        }
    }

    // MARK: Duplicate

    private func duplicate(_ items: [URL]) {
        let sizes = items.map { copier.size(of: $0.path) }
        let bytes = sizes.reduce(0, +)
        reporter.begin(bytes: bytes > 0 ? bytes : nil, items: items.count)

        for (item, size) in zip(items, sizes) {
            if flag.isCancelled {
                cancelled = true
                break
            }
            duplicate(item)
            if cancelled || shortage != nil { break }
            reporter.itemFinished(bytes: size)
        }
    }

    private func duplicate(_ item: URL) {
        guard let (_, kind) = FileIdentity.of(item.path) else {
            fail(item, code: errno)
            return
        }
        let next = { Self.freeName(beside: item, folder: kind == S_IFDIR, adding: " copy") }
        guard let target = next() else {
            fail(item, "no free name was found for it")
            return
        }
        guard let partial = copyToPartial(item, for: target, on: item.deletingLastPathComponent()) else { return }
        switch place(partial.path, at: target, orAt: next) {
        case let .at(final):
            changes.append(.created(final))
            done += 1
        case let other:
            TreeCopier.removeTemporary(partial.path)
            fail(item, placed: other)
        }
    }

    // MARK: Rename, new folder, trash

    private func rename(_ item: URL, to name: String) {
        reporter.begin(bytes: nil, items: 1)
        defer { reporter.itemFinished(bytes: 0) }
        guard let (source, _) = FileIdentity.of(item.path) else {
            fail(item, code: errno)
            return
        }
        let target = OperationRunner.target(for: item, in: item.deletingLastPathComponent(), named: name)
        // Its own name in other capitals is not another item.
        if let there = FileIdentity.of(target.path)?.identity, there != source {
            fail(item, Self.alreadyThere(name))
            return
        }
        switch place(item.path, at: target, orAt: nil) {
        case let .at(final):
            changes.append(.moved(from: item, to: final))
            done += 1
        case let other:
            fail(item, placed: other)
        }
    }

    private func makeFolder(in folder: URL, name: String) {
        reporter.begin(bytes: nil, items: 1)
        defer { reporter.itemFinished(bytes: 0) }
        let target = folder.appendingPathComponent(name, isDirectory: true)
        // `mkdir` makes it or fails: it never touches what has the name.
        if mkdir(target.path, 0o777) == 0 {
            changes.append(.created(target))
            done += 1
        } else if errno == EEXIST {
            fail(target, Self.alreadyThere(name))
        } else if errno == ENOENT {
            fail(target, "the folder “\(folder.lastPathComponent)” is not there")
        } else {
            fail(target, code: errno)
        }
    }

    private func trash(_ items: [URL]) {
        reporter.begin(bytes: nil, items: items.count)
        for item in items {
            if flag.isCancelled {
                cancelled = true
                break
            }
            if let inTrash = moveToTrash(item, for: item) {
                changes.append(.trashed(original: item, inTrash: inTrash))
                done += 1
            }
            reporter.itemFinished(bytes: 0)
        }
    }

    // MARK: The steps

    /// Copies `item`, whole, to a partial name beside `target`. Nil when
    /// that stopped: the partial copy is removed, and why is recorded (a
    /// cancel, a full disk, or the item's failure).
    private func copyToPartial(_ item: URL, for target: URL, on folder: URL) -> URL? {
        let partial = Self.partial(for: target)
        do throws(CopyStop) {
            try copier.copy(item.path, to: partial.path)
            return partial
        } catch {
            TreeCopier.removeTemporary(partial.path)
            reporter.itemAbandoned()
            switch error {
            case .cancelled:
                cancelled = true
            case let .failed(inner, code):
                if code == ENOSPC || code == EDQUOT { shortage = Self.shortage(on: folder, needing: reporter.bytesLeft) }
                let reason = Self.reason(code)
                fail(item, inner.map { "“\($0)” in it: \(reason)" } ?? reason)
            }
            return nil
        }
    }

    /// Gives the item at `path` its final name, never in place of another
    /// item. When the name is taken and `next` is given (a name that only
    /// has to be free: a duplicate, "keep both"), the next free name is tried.
    private func place(_ path: String, at target: URL, orAt next: (() -> URL?)?) -> Placed {
        var target = target
        for _ in 0..<100 {
            watching?(.placing(target))
            if renamex_np(path, target.path, UInt32(RENAME_EXCL)) == 0 { return .at(target) }
            let code = errno
            switch code {
            case EEXIST, ENOTEMPTY:
                guard let free = next?() else { return .taken }
                target = free
            case ENOTSUP: return .unsafe
            case EXDEV: return .otherVolume
            default: return .failed(code)
            }
        }
        return .taken
    }

    /// Puts `url` in the Trash and tells where it is there. Nil when it
    /// could not be: `item` fails with the reason, and `url` is untouched.
    private func moveToTrash(_ url: URL, for item: URL) -> URL? {
        let replacing = url != item
        func failed(_ reason: String) -> URL? {
            fail(item, replacing ? "“\(url.lastPathComponent)” could not be moved to the Trash: \(reason)" : reason)
            return nil
        }
        guard OperationRunner.exists(url) else { return failed(Self.reason(ENOENT)) }
        do {
            var inTrash: NSURL?
            try files.trashItem(at: url, resultingItemURL: &inTrash)
            guard let inTrash = inTrash as URL? else {
                // Gone to the Trash, but the system didn't say where.
                return failed("it is in the Trash, but where there is not known")
            }
            return inTrash
        } catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain else { return failed(error.localizedDescription) }
            switch error.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return failed(Self.reason(ENOENT))
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return failed(Self.reason(EACCES))
            case NSFeatureUnsupportedError: return failed("its disk has no Trash")
            default: return failed(error.localizedDescription)
            }
        }
    }

    // MARK: Failures

    private func fail(_ item: URL, _ reason: String) {
        failures.append(ItemFailure(url: item, reason: reason))
    }

    private func fail(_ item: URL, code: Int32) {
        fail(item, Self.reason(code))
    }

    private func fail(_ item: URL, placed: Placed) {
        switch placed {
        case .at: break
        case .taken: fail(item, Self.appeared)
        case .unsafe: fail(item, "this disk's format can't add an item without the risk of replacing another")
        case .otherVolume: fail(item, code: EXDEV)
        case let .failed(code): fail(item, code: code)
        }
    }

    private static let appeared = "an item with that name appeared"

    private static func alreadyThere(_ name: String) -> String {
        "an item named “\(name)” is already there"
    }

    /// The system's error number as the end of a sentence about the item.
    private static func reason(_ code: Int32) -> String {
        switch code {
        case EACCES, EPERM: "you don't have permission"
        case ENOENT: "it is no longer there"
        case ENOSPC, EDQUOT: "the disk is full"
        case EEXIST, ENOTEMPTY: appeared
        case ENAMETOOLONG: "its name is too long"
        case EROFS: "the disk can't be written to"
        case EFTYPE: "it is not a file, a folder or a link"
        default: String(cString: strerror(code)).lowercased()
        }
    }

    /// The full volume's name, and how much more room the rest of the
    /// operation needed than the volume has.
    private static func shortage(on folder: URL, needing needed: Int64) -> Shortage {
        let name = (try? folder.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        var volume = statfs()
        var missing: Int64?
        if statfs(folder.path, &volume) == 0 {
            let free = Int64(volume.f_bavail) * Int64(volume.f_bsize)
            if needed > free { missing = needed - free }
        }
        return Shortage(volume: name ?? folder.lastPathComponent, missing: missing)
    }

    // MARK: Names

    /// The name of a copy while it is written: hidden, beside its target,
    /// and like no other. A very long name is cut, to leave room for the rest.
    private static func partial(for target: URL) -> URL {
        var name = target.lastPathComponent
        while name.utf8.count > 180 { name.removeLast() }
        return target.deletingLastPathComponent()
            .appendingPathComponent(".\(name)\(TreeCopier.partialMark)\(UUID().uuidString)", isDirectory: false)
    }

    /// The first name beside `url` that nothing has, counting up: "notes
    /// 2.md", "notes 3.md" (a folder's name is not split: "docs 2"). With
    /// `adding` " copy": "notes copy.md", then "notes copy 2.md".
    ///
    /// Task 9's `Conflict.freeName` takes the place of this.
    private static func freeName(beside url: URL, folder: Bool, adding: String = "") -> URL? {
        let name = url.lastPathComponent
        var stem = name
        var ending = ""
        // An extension: after the last dot, when that isn't the first
        // character, something follows it, and that has no space.
        if !folder, let dot = name.lastIndex(of: "."), dot != name.startIndex,
            name.index(after: dot) != name.endIndex, !name[dot...].contains(where: \.isWhitespace)
        {
            stem = String(name[..<dot])
            ending = String(name[dot...])
        }
        stem += adding
        let parent = url.deletingLastPathComponent()
        for number in (adding.isEmpty ? 2 : 1)...10_000 {
            let candidate = parent.appendingPathComponent(
                (number == 1 ? stem : "\(stem) \(number)") + ending, isDirectory: folder)
            if !OperationRunner.exists(candidate) { return candidate }
        }
        return nil
    }
}
