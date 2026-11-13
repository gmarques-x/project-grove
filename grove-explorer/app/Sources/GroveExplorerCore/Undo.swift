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
/// - `.created`: the item goes to the Trash (as a `.trash` of the runner).
/// - `.moved`: the item goes back to the folder and the name it had.
/// - `.trashed`, `.replaced`: the item comes out of the Trash, to the place
///   and the name it had; for a replace, after the newcomer has left it.
///
/// Nothing is removed, and nothing is written over: an item only ever goes
/// to the Trash or is moved, by the runner's worker, to a name nothing has.
///
/// **An undo is one turn of the runner's queue** (`OperationRunner.turn`):
/// it waits for the run in hand, then checks every change and takes them
/// back with no other run in between. It is about the operation that was
/// the latest when it was asked for.
///
/// **Before anything is touched, every change is checked**, and one that
/// can't be taken back refuses the whole undo ("Can't undo: …"). What is
/// checked, for the item each change left behind (the copy, the moved item
/// where it now is, the item in the Trash):
/// - its disk is still attached;
/// - it is still there, and of the same kind (file, folder, link);
/// - a file or a link has the size and the modification date, to the
///   nanosecond, that it had when the outcome was recorded. A folder's are
///   not compared: its date changes whenever anything is added to it or
///   taken out, by this stack's own later operations too. A folder is the
///   same folder instead: the volume and the file number (`st_dev`,
///   `st_ino`) it had then, so an unrelated folder that has since taken
///   its name at the path is never trashed or moved in its place. (FAT and
///   ExFAT make their file numbers up, and one may differ after the disk
///   was attached again: that can only refuse an undo.)
/// - a folder that a new-folder operation made is empty;
/// - where it goes back to: that disk is attached, the folder is there, and
///   nothing has the name (but the newcomer of a replace, which leaves first).
///
/// Only the item itself is looked at, never what is in it: a copied or
/// moved folder whose contents were changed since goes to the Trash, or
/// back, whole. From the Trash it can be had again.
///
/// What a refusal leaves: when the user can put the world right (something
/// is at the old place, the new folder is no longer empty, a disk or a
/// folder is not there), the entry stays and the undo works once that is
/// done. When nobody can (the item has changed, is gone, is no longer in
/// the Trash), the entry is dropped, the sentence says so ("… It can no
/// longer be undone."), and the next undo is about the operation before.
///
/// Each change is checked once more just before it is taken back. **If a
/// step fails all the same** (the file system refuses, another program got
/// in between), the undo stops there: what was taken back stays so, the
/// rest stays as it is, and the sentence thrown says which ("Undo stopped:
/// …"). The entry is then dropped, with no redo: half of it is undone, and
/// neither doing the rest later nor doing the whole again would be what
/// was recorded.
///
/// **Redo** runs the operation again, in one turn of the runner, with the
/// answers it had. It is refused, before anything is written, unless the
/// names that exist at the target now are exactly the ones that were
/// answered about then: one more would be a question nobody can be asked
/// from here, one fewer would let an item arrive that was skipped, or
/// under another name. An operation that was cancelled or had failures is
/// not offered for redo at all: run again, it would do more than it did.
///
/// The app must not offer undo or redo between its own `existingNames` and
/// the `run` that follows: a turn makes the runner forget what was asked.
public actor UndoStack {
    private let runner: OperationRunner
    private var undos: [Entry] = []
    private var redos: [Again] = []
    /// An undo or a redo is in hand, waiting for its turn or in it:
    /// another one must not start meanwhile.
    private var working = false
    /// How many outcomes were recorded, ever.
    private var recorded = 0

    public init(runner: OperationRunner) {
        self.runner = runner
    }

    /// The items the last undo put back where they were, or the last redo
    /// made or moved, for the window to select; empty when it was refused
    /// and for what an undo sent to the Trash.
    public private(set) var restored: [URL] = []

    /// An item moved or renamed by an undo or a redo: from where to where.
    public struct Move: Equatable, Sendable {
        public let from: URL
        public let to: URL
    }

    /// What the last undo or redo moved or renamed (a rename taken back is
    /// the new name to the old), for the window to follow: a folder open
    /// in place stays open under its name. Empty when it was refused.
    public private(set) var moved: [Move] = []

    public var canUndo: Bool { !working && !undos.isEmpty }
    public var canRedo: Bool { !working && !redos.isEmpty }

    /// Remembers what a finished run did, to be undone. `words` say what
    /// that was, as the outcome's summary does ("Moved 3 items to
    /// Downloads"): undo answers "Undid: moved 3 items to Downloads".
    ///
    /// To be called as soon as the run ends: the items are looked at now,
    /// and an undo is refused when a file is no longer as it is now.
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
        recorded += 1
    }

    /// Takes back the latest operation and says so: "Undid: moved 3 items
    /// to Downloads". See the type for what is checked first and what a
    /// refusal leaves.
    public func undo() async throws(UndoRefusal) -> String {
        guard !working else { throw UndoRefusal(sentence: "Can't undo: another undo or redo is still going on") }
        restored = []
        moved = []
        guard let entry = undos.last else { throw UndoRefusal(sentence: "There is nothing to undo") }
        working = true
        defer { working = false }
        let before = recorded
        let steps = entry.steps

        let result = await runner.turn { turn in Self.takeBack(steps, in: turn) }

        switch result {
        case .done:
            undos.removeAll { $0.id == entry.id }
            // An operation recorded meanwhile has cleared redo: it stays so.
            if let again = entry.again, recorded == before { redos.append(again) }
            restored = steps.compactMap(\.place)
            moved = steps.compactMap { step in
                if case let .moved(from, to) = step.change { Move(from: to, to: from) } else { nil }
            }
            return "Undid: \(Self.lowered(entry.words))"
        case let .refused(problem):
            guard !problem.heals else { throw UndoRefusal(sentence: "Can't undo: \(problem.words)") }
            undos.removeAll { $0.id == entry.id }
            throw UndoRefusal(sentence: "Can't undo: \(problem.words). It can no longer be undone.")
        case let .stopped(sentence):
            undos.removeAll { $0.id == entry.id }
            throw UndoRefusal(sentence: sentence)
        }
    }

    /// Does the latest undone operation again and says so: "Redid: moved 3
    /// items to Downloads". Refused, with nothing written, when an item of
    /// the operation is gone or the names that exist at its target are not
    /// the ones answered about the first time.
    public func redo() async throws(UndoRefusal) -> String {
        guard !working else { throw UndoRefusal(sentence: "Can't redo: another undo or redo is still going on") }
        restored = []
        moved = []
        guard let again = redos.last else { throw UndoRefusal(sentence: "There is nothing to redo") }
        working = true
        defer { working = false }
        let operation = again.operation
        // By the key the runner compares targets by.
        let answers = Dictionary(
            again.answers.map { (OperationRunner.key($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })

        let result = await runner.turn { turn in Self.doAgain(operation, answers: answers, in: turn) }

        let outcome: Outcome
        switch result {
        case let .refused(why): throw UndoRefusal(sentence: "Can't redo: \(why)")
        case let .ran(ran): outcome = ran
        }
        let complete = outcome.failures.isEmpty && !outcome.cancelled
        let words = complete ? again.words : outcome.summary
        guard let entry = Self.entry(for: outcome, words: words, operation: operation, answers: again.answers)
        else {
            let why = outcome.failures.first.map { "\($0.url.lastPathComponent): \($0.reason)" }
            throw UndoRefusal(sentence: "Can't redo: \(why ?? Self.lowered(outcome.summary))")
        }
        // By its own mark: an operation recorded meanwhile has cleared redo.
        redos.removeAll { $0.id == again.id }
        undos.append(entry)
        restored = AfterOperation.newItems(of: outcome)
        moved = outcome.changes.compactMap { change in
            if case let .moved(from, to) = change { Move(from: from, to: to) } else { nil }
        }
        return "Redid: \(Self.lowered(words))"
    }

    // MARK: Inside the runner's turn

    private enum Undone: Sendable {
        case done
        /// Nothing was touched.
        case refused(Problem)
        /// Stopped in the middle, with the sentence that says where.
        case stopped(String)
    }

    private enum Redone: Sendable {
        /// Nothing was written; the words after "Can't redo: ".
        case refused(String)
        case ran(Outcome)
    }

    /// Checks all the changes, then takes them back, the last first.
    private static func takeBack(_ steps: [Step], in turn: OperationRunner.Turn) -> Undone {
        for (index, step) in steps.enumerated() {
            if let problem = step.problem(expectingNewcomer: newcomerFollows(index, in: steps)) {
                return .refused(problem)
            }
        }
        var undone: [String] = []
        for step in steps.reversed() {
            // Once more, now: another program may have been at it since.
            if let words = step.problem(expectingNewcomer: false)?.words ?? takeBack(step, in: turn) {
                return .stopped(stopped(by: words, after: undone))
            }
            undone.append(step.name)
        }
        return .done
    }

    /// Takes one change back. Nil when done, otherwise what went wrong, as
    /// the words after "Undo stopped: ".
    private static func takeBack(_ step: Step, in turn: OperationRunner.Turn) -> String? {
        let outcome: Outcome
        let done: Bool
        let what: String
        switch step.change {
        case let .created(url):
            what = "moved to the Trash"
            outcome = turn.run(.trash(items: [url]))
            if case .trashed? = outcome.changes.first { done = true } else { done = false }
        case .moved, .trashed, .replaced:
            guard let place = step.place else { return "\(step.name) has no place to go back to" }
            if case .moved = step.change {
                what = "moved back"
            } else {
                what = "put back"
            }
            if case .moved = step.change, isSameFolder(step.item, place) {
                // A rename, which the worker knows how to do when the two
                // names are one to the volume ("Notes.md", "notes.md").
                outcome = turn.run(.rename(item: step.item, to: place.lastPathComponent))
            } else {
                outcome = turn.put(step.item, at: place)
            }
            // A `.created` instead: copied to the other disk, but still
            // where it was too.
            if outcome.changes.count == 1, case .moved? = outcome.changes.first { done = true } else { done = false }
        }
        if done { return nil }
        let reason = outcome.failures.first?.reason ?? lowered(outcome.summary)
        return "\(step.name) could not be \(what) (\(reason))"
    }

    /// Runs the operation again, when the names at its target are the
    /// ones in `answers` (by the runner's key) and its items are there.
    private static func doAgain(
        _ operation: Operation, answers: [String: Conflict.Choice], in turn: OperationRunner.Turn
    ) -> Redone {
        if let gone = items(of: operation).first(where: { !OperationRunner.exists($0) }) {
            return .refused("\(gone.lastPathComponent) is no longer there")
        }
        let existing = turn.existing(for: operation)
        if let unasked = existing.first(where: { answers[OperationRunner.key($0)] == nil }) {
            return .refused("\(unasked.lastPathComponent) is now in the way")
        }
        let there = Set(existing.map(OperationRunner.key))
        if let missing = answers.keys.sorted().first(where: { !there.contains($0) }) {
            return .refused("\((missing as NSString).lastPathComponent) is no longer there")
        }
        // Only the names just seen are asked about; one that appears from
        // here on fails its item. Were another asked about all the same,
        // the answer that loses nothing is given.
        return .ran(turn.run(operation, asked: existing) { answers[OperationRunner.key($0)] ?? .skip })
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
        let id = UUID()
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
        var isNewFolder = false
        if case .newFolder? = operation { isNewFolder = true }
        let steps = outcome.changes.map { Step($0, ofNewFolder: isNewFolder, operationKnown: operation != nil) }
        return Entry(steps: steps, words: words, again: again)
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

/// Why a change can't be taken back as things are.
private struct Problem: Sendable {
    /// The words after "Can't undo: ".
    var words: String
    /// Whether the user can put it right, so that the undo works later.
    var heals: Bool
}

// MARK: - One change, and what it left

/// One change of an outcome with what is needed to tell, later, whether it
/// can still be taken back.
private struct Step: Sendable {
    let change: Change
    /// Where the item the change left is: the copy, the moved item, the
    /// item in the Trash.
    let item: URL
    /// Where it goes back to; nil for an item that goes to the Trash.
    let place: URL?
    /// The item as it was when the outcome was recorded; nil when it was
    /// not there even then.
    let stamp: Stamp?
    /// A folder the operation made new: taken back only while it is empty.
    /// (Recorded without its operation: a created folder that was empty.)
    let mustBeEmpty: Bool
    let disk: Disk?
    /// The disk `place` is on.
    let home: Disk?

    init(_ change: Change, ofNewFolder: Bool, operationKnown: Bool) {
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
            mustBeEmpty = ofNewFolder || (!operationKnown && TreeCopier.names(in: item.path) == [])
        } else {
            mustBeEmpty = false
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

    /// Why the change can't be taken back as things are now; nil when it
    /// can. With `expectingNewcomer`,
    /// the item at `place` is the one that replaced this one, which is
    /// taken back first.
    func problem(expectingNewcomer: Bool) -> Problem? {
        if let disk, !disk.isThere { return Problem(words: "the disk \(disk.name) is no longer there", heals: true) }
        guard let now = Stamp.of(item) else {
            let gone = isInTrash ? "in the Trash" : "there"
            return Problem(words: "\(name) is no longer \(gone)", heals: false)
        }
        guard let stamp, now.isSameItem(as: stamp) else { return Problem(words: "\(name) has changed", heals: false) }
        if mustBeEmpty, TreeCopier.names(in: item.path) != [] {
            return Problem(words: "\(name) is no longer empty", heals: true)
        }

        guard let place else { return nil }
        if let home, !home.isThere { return Problem(words: "the disk \(home.name) is no longer there", heals: true) }
        let folder = place.deletingLastPathComponent()
        guard let (_, kind) = FileIdentity.of(folder.path, followingLinks: true), kind == S_IFDIR else {
            return Problem(words: "the folder \(folder.lastPathComponent) is no longer there", heals: true)
        }
        if !expectingNewcomer, let there = FileIdentity.of(place.path)?.identity, !isItself(there, at: place) {
            return Problem(words: "another item is now where \(name) was", heals: true)
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

/// What tells that an item is still as an operation left it: its kind
/// and, for a file or a link, its size and its modification date; for a
/// folder, which volume's which folder it is. Of the item itself: a link
/// is not followed.
private struct Stamp: Equatable, Sendable {
    var kind: mode_t
    var size: Int64
    var seconds: Int
    var nanoseconds: Int
    /// The volume and the item's number on it.
    var device: dev_t
    var inode: ino_t

    /// A folder's size and date change with everything put in it or taken
    /// out: it is the same while it is the same folder to its volume. A
    /// file or a link is the same by its size and date, as before.
    func isSameItem(as other: Stamp) -> Bool {
        if kind == S_IFDIR { return other.kind == S_IFDIR && device == other.device && inode == other.inode }
        return kind == other.kind && size == other.size && seconds == other.seconds
            && nanoseconds == other.nanoseconds
    }

    static func of(_ url: URL) -> Stamp? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Stamp(
            kind: info.st_mode & S_IFMT, size: Int64(info.st_size),
            seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec,
            device: info.st_dev, inode: info.st_ino)
    }
}

/// A disk as it was attached when an outcome was recorded.
private struct Disk: Sendable {
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
