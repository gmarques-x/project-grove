import Foundation

/// Why an undo or a redo was not done, as one sentence for the user:
/// "Can't undo: notes.md has changed".
public struct UndoRefusal: Error, Equatable {
    public let sentence: String

    public init(sentence: String) {
        self.sentence = sentence
    }
}

/// The finished operations of one window, latest last, and how to take each
/// back. Not kept across launches.
///
/// **Undo** takes back exactly the changes an outcome lists, the last one
/// first, and nothing it has to infer:
/// - `.created`: the item goes to the Trash (by a `.trash` run of the runner).
/// - `.moved`: the item goes back to the folder and the name it had.
/// - `.trashed`, `.replaced`: the item comes out of the Trash, to the place
///   and the name it had; for a replace, after the newcomer has left it.
///
/// Nothing is removed, and nothing is written over: an item only ever goes
/// to the Trash or is moved, by the runner, to a name nothing has.
///
/// **Before anything is touched, every change is checked**, and one that
/// can't be taken back refuses the whole undo ("Can't undo: …"). The entry
/// stays, so the undo works again once the world is as it was. What is
/// checked, for the item each change left behind (the copy, the moved item
/// where it now is, the item in the Trash):
/// - its disk is still attached;
/// - it is still there;
/// - it is what the operation left: of the same kind (file, folder, link),
///   and with the size and the modification date, to the nanosecond, that
///   it had when the outcome was recorded. Of the item itself only: what
///   is inside a folder is not looked at, but adding, removing or renaming
///   an item directly in it changes the folder's date;
/// - a folder that was made empty (a new folder) is still empty;
/// - where it goes back to: that disk is attached, the folder is there, and
///   nothing has the name (but the newcomer of a replace, which leaves first).
///
/// Each change is checked once more just before it is taken back. **If a
/// step fails all the same** (the file system refuses), the undo stops
/// there: what was taken back stays so, the rest stays as it is, and the
/// sentence thrown says which ("Undo stopped: …"). The entry is then
/// dropped, with no redo: half of it is undone, and neither doing the rest
/// later nor doing the whole again would be what was recorded.
///
/// **Redo** runs the operation again, through the runner, with the answers
/// it had. It is refused, before anything is written, unless the names
/// that exist at the target now are exactly the ones that were answered
/// about then: one more would be a question nobody can be asked from here,
/// one fewer would let an item arrive that was skipped, or under another
/// name. An operation that was cancelled or had failures is not offered for
/// redo at all: run again, it would do more than it did.
public actor UndoStack {
    private let runner: OperationRunner
    private var undos: [Entry] = []
    private var redos: [Again] = []
    /// An undo or a redo is in hand: its steps wait for the runner, and
    /// another one must not start between them.
    private var working = false

    public init(runner: OperationRunner) {
        self.runner = runner
    }

    public var canUndo: Bool { !working && !undos.isEmpty }
    public var canRedo: Bool { !working && !redos.isEmpty }

    /// Remembers what a finished run did, to be undone. `words` say what
    /// that was, as the outcome's summary does ("Moved 3 items to
    /// Downloads"): undo answers "Undid: moved 3 items to Downloads".
    ///
    /// To be called as soon as the run ends: the items are looked at now,
    /// and an undo is refused when they are no longer as they are now.
    ///
    /// With the `operation` that was run and the `answers` given about the
    /// names that existed (by the URL `existingNames` gave for each), the
    /// operation can be redone after an undo; without, only undone.
    ///
    /// A new operation clears redo. An outcome without changes is not
    /// remembered and clears nothing.
    public func record(
        _ outcome: Outcome, words: String, operation: Operation? = nil, answers: [URL: Conflict.Choice] = [:]
    ) {
        guard let entry = Self.entry(for: outcome, words: words, operation: operation, answers: answers) else {
            return
        }
        undos.append(entry)
        redos.removeAll()
    }

    /// Takes back the latest operation and says so: "Undid: moved 3 items
    /// to Downloads". See the type for what is checked first and what a
    /// refusal leaves.
    public func undo() async throws(UndoRefusal) -> String {
        guard !working else { throw UndoRefusal(sentence: "Can't undo: another undo or redo is still going on") }
        guard let entry = undos.last else { throw UndoRefusal(sentence: "There is nothing to undo") }

        // All of it is checked before any of it is done.
        for (index, step) in entry.steps.enumerated() {
            let newcomer = Self.newcomerFollows(index, in: entry.steps)
            if let problem = step.problem(expectingNewcomer: newcomer) {
                throw UndoRefusal(sentence: "Can't undo: \(problem)")
            }
        }

        undos.removeLast()
        working = true
        defer { working = false }
        var undone: [String] = []
        for step in entry.steps.reversed() {
            // Once more, now: other work may have run since the checks.
            var problem = step.problem(expectingNewcomer: false)
            if problem == nil { problem = await takeBack(step) }
            if let problem { throw UndoRefusal(sentence: Self.stopped(by: problem, after: undone)) }
            undone.append(step.name)
        }
        if let again = entry.again { redos.append(again) }
        return "Undid: \(Self.lowered(entry.words))"
    }

    /// Does the latest undone operation again and says so: "Redid: moved 3
    /// items to Downloads". Refused, with nothing written, when an item of
    /// the operation is gone or the names that exist at its target are not
    /// the ones answered about the first time.
    public func redo() async throws(UndoRefusal) -> String {
        guard !working else { throw UndoRefusal(sentence: "Can't redo: another undo or redo is still going on") }
        guard let again = redos.last else { throw UndoRefusal(sentence: "There is nothing to redo") }
        if let gone = Self.items(of: again.operation).first(where: { !OperationRunner.exists($0) }) {
            throw UndoRefusal(sentence: "Can't redo: \(gone.lastPathComponent) is no longer there")
        }

        working = true
        defer { working = false }
        // By the key the runner compares targets by.
        let answers = Dictionary(
            again.answers.map { (OperationRunner.key($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        let existing = await runner.existingNames(for: again.operation)
        if let unasked = existing.first(where: { answers[OperationRunner.key($0)] == nil }) {
            throw UndoRefusal(sentence: "Can't redo: \(unasked.lastPathComponent) is now in the way")
        }
        let there = Set(existing.map(OperationRunner.key))
        if let missing = answers.keys.sorted().first(where: { !there.contains($0) }) {
            throw UndoRefusal(sentence: "Can't redo: \((missing as NSString).lastPathComponent) is no longer there")
        }

        // A name that appears from here on is not one the runner asks
        // about: it fails its item. Were it asked all the same, the answer
        // that loses nothing is given.
        let outcome = await runner.run(
            again.operation, resolve: { answers[OperationRunner.key($0)] ?? .skip }, progress: { _ in })
        let complete = outcome.failures.isEmpty && !outcome.cancelled
        let words = complete ? again.words : outcome.summary
        guard let entry = Self.entry(for: outcome, words: words, operation: again.operation, answers: again.answers)
        else {
            let why = outcome.failures.first.map { "\($0.url.lastPathComponent): \($0.reason)" }
            throw UndoRefusal(sentence: "Can't redo: \(why ?? Self.lowered(outcome.summary))")
        }
        // By its own mark: an operation recorded meanwhile has cleared redo.
        redos.removeAll { $0.id == again.id }
        undos.append(entry)
        return "Redid: \(Self.lowered(words))"
    }

    // MARK: One change taken back

    /// Takes one change back through the runner. Nil when done, otherwise
    /// what went wrong, as the words after "Undo stopped: ".
    private func takeBack(_ step: Step) async -> String? {
        let outcome: Outcome
        let done: Bool
        let what: String
        switch step.change {
        case let .created(url):
            what = "moved to the Trash"
            outcome = await runner.run(.trash(items: [url]), resolve: { _ in .skip }, progress: { _ in })
            if case .trashed? = outcome.changes.first { done = true } else { done = false }
        case .moved, .trashed, .replaced:
            guard let place = step.place else { return "\(step.name) has no place to go back to" }
            if case .moved = step.change {
                what = "moved back"
            } else {
                what = "put back"
            }
            if case .moved = step.change, Self.isSameFolder(step.item, place) {
                // A rename, which the runner knows how to do when the two
                // names are one to the volume ("Notes.md", "notes.md").
                outcome = await runner.run(
                    .rename(item: step.item, to: place.lastPathComponent), resolve: { _ in .skip },
                    progress: { _ in })
            } else {
                outcome = await runner.put(step.item, at: place)
            }
            // A `.created` instead: copied to the other disk, but still
            // where it was too.
            if outcome.changes.count == 1, case .moved? = outcome.changes.first { done = true } else { done = false }
        }
        if done { return nil }
        let reason = outcome.failures.first?.reason ?? Self.lowered(outcome.summary)
        return "\(step.name) could not be \(what) (\(reason))"
    }

    /// Whether the change at `index` is a replace whose newcomer, which
    /// has its place until it is itself taken back, is the next change.
    private static func newcomerFollows(_ index: Int, in steps: [Step]) -> Bool {
        guard case let .replaced(original, _) = steps[index].change, index + 1 < steps.count else { return false }
        switch steps[index + 1].change {
        case let .created(url), let .moved(_, url):
            return OperationRunner.key(url) == OperationRunner.key(original)
        case .trashed, .replaced:
            return false
        }
    }

    private static func isSameFolder(_ one: URL, _ other: URL) -> Bool {
        OperationRunner.key(one.deletingLastPathComponent()) == OperationRunner.key(other.deletingLastPathComponent())
    }

    // MARK: Words

    private static func stopped(by problem: String, after undone: [String]) -> String {
        guard !undone.isEmpty else { return "Undo stopped: \(problem). Nothing was undone." }
        var names = undone.prefix(3).joined(separator: ", ")
        if undone.count > 3 { names += " and \(Wording.grouped(undone.count - 3)) more" }
        return "Undo stopped: \(problem). Already undone: \(names); the rest is as it was."
    }

    /// "Moved 3 items" as it reads after "Undid: ".
    private static func lowered(_ words: String) -> String {
        words.prefix(1).lowercased() + words.dropFirst()
    }

    // MARK: What is remembered

    private struct Entry {
        var steps: [Step]
        var words: String
        /// Nil when it can't be redone.
        var again: Again?
    }

    /// An operation to run again, with the answers it had.
    private struct Again {
        let id = UUID()
        var operation: Operation
        var words: String
        /// About the names that existed, by the URL the runner gave for each.
        var answers: [URL: Conflict.Choice]
    }

    private static func entry(
        for outcome: Outcome, words: String, operation: Operation?, answers: [URL: Conflict.Choice]
    ) -> Entry? {
        guard !outcome.changes.isEmpty else { return nil }
        var again: Again?
        // Run again, a cancelled or failed one would do more than it did.
        if let operation, outcome.failures.isEmpty, !outcome.cancelled {
            again = Again(operation: operation, words: words, answers: answers)
        }
        return Entry(steps: outcome.changes.map(Step.init), words: words, again: again)
    }

    /// The items an operation names, which a redo needs.
    private static func items(of operation: Operation) -> [URL] {
        switch operation {
        case let .copy(items, _), let .move(items, _), let .duplicate(items), let .trash(items): items
        case let .rename(item, _): [item]
        case .newFolder: []
        }
    }
}

// MARK: - One change, and what it left

/// One change of an outcome with what is needed to tell, later, whether it
/// can still be taken back.
private struct Step {
    let change: Change
    /// Where the item the change left is: the copy, the moved item, the
    /// item in the Trash.
    let item: URL
    /// Where it goes back to; nil for an item that goes to the Trash.
    let place: URL?
    /// The item as it was when the outcome was recorded; nil when it was
    /// not there even then.
    let stamp: Stamp?
    /// A folder that was made, and empty when recorded: taken back only
    /// while it is.
    let madeEmpty: Bool
    let disk: Disk?
    /// The disk `place` is on.
    let home: Disk?

    init(_ change: Change) {
        self.change = change
        switch change {
        case let .created(url):
            item = url
            place = nil
        case let .moved(from, to):
            item = to
            place = from
        case let .trashed(original, inTrash), let .replaced(original, inTrash):
            item = inTrash
            place = original
        }
        stamp = Stamp.of(item)
        if case .created = change, stamp?.kind == S_IFDIR {
            madeEmpty = TreeCopier.names(in: item.path) == []
        } else {
            madeEmpty = false
        }
        // By its folder: a link's own path would lead to the disk it points at.
        disk = Disk.holding(item.deletingLastPathComponent().path)
        home = place.flatMap { Disk.holding($0.deletingLastPathComponent().path) }
    }

    /// The item as the user knows it: by the name it had, for one in the Trash.
    var name: String { (place ?? item).lastPathComponent }

    private var isInTrash: Bool {
        switch change {
        case .trashed, .replaced: true
        case .created, .moved: false
        }
    }

    /// Why the change can't be taken back as things are now, as the words
    /// after "Can't undo: "; nil when it can. With `expectingNewcomer`,
    /// the item at `place` is the one that replaced this one, which is
    /// taken back first.
    func problem(expectingNewcomer: Bool) -> String? {
        if let disk, !disk.isThere { return "the disk \(disk.name) is no longer there" }
        guard let now = Stamp.of(item) else {
            return isInTrash ? "\(name) is no longer in the Trash" : "\(name) is no longer there"
        }
        if madeEmpty, now.kind == S_IFDIR, TreeCopier.names(in: item.path) != [] {
            return "\(name) is no longer empty"
        }
        guard now == stamp else { return "\(name) has changed" }

        guard let place else { return nil }
        if let home, !home.isThere { return "the disk \(home.name) is no longer there" }
        let folder = place.deletingLastPathComponent()
        guard let (_, kind) = FileIdentity.of(folder.path, followingLinks: true), kind == S_IFDIR else {
            return "the folder \(folder.lastPathComponent) is no longer there"
        }
        if !expectingNewcomer, let there = FileIdentity.of(place.path)?.identity, !isItself(there, at: place) {
            return "another item is now where \(name) was"
        }
        return nil
    }

    /// Whether what is at `place` is the item itself, renamed only in its
    /// capitals or the form of its accents: the volume says it is the same
    /// item, in the same folder, and the names differ by no more.
    private func isItself(_ there: FileIdentity, at place: URL) -> Bool {
        there == FileIdentity.of(item.path)?.identity
            && OperationRunner.key(item.deletingLastPathComponent())
                == OperationRunner.key(place.deletingLastPathComponent())
            && OperationRunner.isSameName(item.lastPathComponent, place.lastPathComponent)
    }
}

/// What tells that an item is still as an operation left it: its kind, its
/// size and its modification date. Of the item itself: a link is not followed.
private struct Stamp: Equatable {
    var kind: mode_t
    var size: Int64
    var seconds: Int
    var nanoseconds: Int

    static func of(_ url: URL) -> Stamp? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Stamp(
            kind: info.st_mode & S_IFMT, size: Int64(info.st_size),
            seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec)
    }
}

/// A disk as it was attached when an outcome was recorded.
private struct Disk {
    /// The folder it is attached at.
    var root: String
    var device: dev_t
    var name: String

    /// The disk the folder at `path` is on; nil when there is no such folder.
    static func holding(_ path: String) -> Disk? {
        var volume = statfs()
        guard statfs(path, &volume) == 0 else { return nil }
        let root = withUnsafePointer(to: &volume.f_mntonname) {
            String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
        var info = stat()
        guard lstat(root, &info) == 0 else { return nil }
        let url = URL(fileURLWithPath: root, isDirectory: true)
        let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        return Disk(root: root, device: info.st_dev, name: name ?? url.lastPathComponent)
    }

    /// Whether it is still what is attached there.
    var isThere: Bool {
        var info = stat()
        return lstat(root, &info) == 0 && info.st_dev == device
    }
}
