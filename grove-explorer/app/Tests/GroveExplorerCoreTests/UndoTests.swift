import Foundation
@testable import GroveExplorerCore
import Testing

// Foundation has an `Operation` too.
private typealias Operation = GroveExplorerCore.Operation

/// A value several threads may touch.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    @discardableResult func change<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&stored) }
    }
}

/// The real file manager, which remembers what it put in the Trash (an undo
/// trashes inside the stack, where a test can't see the address), and
/// refuses to trash the names in `refused`.
private final class WatchedTrash: FileManager, @unchecked Sendable {
    /// Where each item is in the Trash, and which item of the volume it is.
    let taken = Locked<[(url: URL, number: ino_t)]>([])
    let refused = Locked<Set<String>>([])

    override func trashItem(
        at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        if refused.value.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
        var result: NSURL?
        try super.trashItem(at: url, resultingItemURL: &result)
        var info = stat()
        if let result = result as URL?, lstat(result.path, &info) == 0 {
            taken.change { $0.append((result, info.st_ino)) }
        }
        outResultingURL?.pointee = result
    }
}

/// What the tests do to files: everything under one temporary folder,
/// removed when the test ends, passed or failed. What a run or an undo put
/// in the Trash is taken out of it again, by the address the Trash gave and
/// only while it is still that very item: nothing else there is touched.
private final class Sandbox: @unchecked Sendable {
    let root: URL
    let files = FileManager.default
    let trash = WatchedTrash()

    init(_ label: String) throws {
        let made = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-\(label)-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: made, withIntermediateDirectories: true)
        // The address as the system gives it (/private/var/…).
        guard let real = realpath(made.path, nil) else { throw CocoaError(.fileNoSuchFile) }
        defer { free(real) }
        root = URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    /// Call from `deinit`.
    func cleanUp() {
        for (url, number) in trash.taken.value {
            var info = stat()
            if lstat(url.path, &info) == 0, info.st_ino == number { try? files.removeItem(at: url) }
        }
        try? files.removeItem(at: root)
    }

    func path(_ name: String) -> URL { root.appendingPathComponent(name) }

    @discardableResult func makeFolder(_ name: String) throws -> URL {
        let url = path(name)
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult func makeFile(_ name: String, _ text: String = "text") throws -> URL {
        try makeFile(at: path(name), text)
    }

    @discardableResult func makeFile(at url: URL, _ text: String) throws -> URL {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    func names(in folder: URL) -> [String] {
        ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func modified(_ url: URL) -> Date? {
        (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Everything under `folder` (the whole sandbox when nil): each path,
    /// with a file's contents, "/" for a folder and where a link points.
    func listing(_ folder: URL? = nil) -> [String: String] {
        let top = folder ?? root
        var all: [String: String] = [:]
        for inner in (try? files.subpathsOfDirectory(atPath: top.path)) ?? [] {
            let url = top.appendingPathComponent(inner)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: all[inner] = "/"
            case S_IFLNK: all[inner] = "-> " + ((try? files.destinationOfSymbolicLink(atPath: url.path)) ?? "?")
            default: all[inner] = text(url) ?? "?"
            }
        }
        return all
    }

    /// The addresses in the Trash of what was put there, oldest first.
    var inTrash: [URL] { trash.taken.value.map(\.url) }
}

/// Does an operation as the app does: looks the names up, runs it with one
/// answer for every name that exists, and records the outcome with the
/// operation and the answers.
@discardableResult private func perform(
    _ operation: Operation, choice: Conflict.Choice? = nil, on runner: OperationRunner, into stack: UndoStack
) async -> Outcome {
    let existing = await runner.existingNames(for: operation)
    let outcome = await runner.run(
        operation,
        resolve: { url in
            if let choice { return choice }
            Issue.record("asked what to do about \(url.lastPathComponent)")
            return .skip
        },
        progress: { _ in })
    var answers: [URL: Conflict.Choice] = [:]
    if let choice { for url in existing { answers[url] = choice } }
    await stack.record(outcome, words: outcome.summary, operation: operation, answers: answers)
    return outcome
}

/// The sentence an undo or a redo is refused with.
private func refusal(_ body: () async throws -> String) async -> String? {
    do {
        let said = try await body()
        Issue.record("not refused: \(said)")
    } catch let error as UndoRefusal {
        return error.sentence
    } catch {
        Issue.record("another error: \(error)")
    }
    return nil
}

// MARK: - On one volume

/// Undo and redo against real files, in a temporary folder of the test's own.
@Suite(.serialized) final class UndoTests {
    private let box: Sandbox
    private let runner: OperationRunner
    private let stack: UndoStack

    init() throws {
        box = try Sandbox("undo")
        runner = OperationRunner(fileManager: box.trash)
        stack = UndoStack(runner: runner)
        try box.makeFolder("src")
        try box.makeFolder("dest")
    }

    deinit { box.cleanUp() }

    private var src: URL { box.path("src") }
    private var dest: URL { box.path("dest") }

    @discardableResult
    private func perform(_ operation: Operation, choice: Conflict.Choice? = nil) async -> Outcome {
        await GroveExplorerCoreTests.perform(operation, choice: choice, on: runner, into: stack)
    }

    /// Does the operation, undoes it and redoes it: after the undo all is
    /// as it was before, after the redo as it was after the operation.
    private func roundTrip(
        _ operation: Operation, choice: Conflict.Choice? = nil, undid: String, redid: String
    ) async throws {
        let before = box.listing()
        let outcome = await perform(operation, choice: choice)
        #expect(outcome.failures == [])
        #expect(!outcome.changes.isEmpty)
        let after = box.listing()
        #expect(after != before)
        #expect(await stack.canUndo)
        #expect(await stack.canRedo == false)

        #expect(try await stack.undo() == undid)
        #expect(box.listing() == before)
        #expect(await stack.canUndo == false)
        #expect(await stack.canRedo)

        #expect(try await stack.redo() == redid)
        #expect(box.listing() == after)
        #expect(await stack.canUndo)
        #expect(await stack.canRedo == false)

        // And what a redo did can be undone like the first time.
        #expect(try await stack.undo() == undid)
        #expect(box.listing() == before)
    }

    // MARK: Every operation, undone and redone

    @Test func aCopyIsUndoneByPuttingTheCopiesInTheTrash() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        try box.makeFile("src/Tree/one.txt", "one")
        try box.makeFile("src/Tree/deep/two.txt", "two")

        try await roundTrip(
            .copy(items: [file, box.path("src/Tree")], to: dest),
            undid: "Undid: copied 2 items to dest", redid: "Redid: copied 2 items to dest")

        // Not removed: each copy is in the Trash, whole.
        #expect(box.inTrash.count == 4)
        #expect(box.text(box.inTrash[0].appendingPathComponent("deep/two.txt")) == "two")
        #expect(box.text(box.inTrash[1]) == "some notes")
    }

    @Test func aMoveIsUndoneByMovingTheItemsBack() async throws {
        let items = try (1...3).map { try box.makeFile("src/file-\($0).txt", "file \($0)") }
        try box.makeFile("src/Tree/one.txt", "one")

        try await roundTrip(
            .move(items: items + [box.path("src/Tree")], to: dest),
            undid: "Undid: moved 4 items to dest", redid: "Redid: moved 4 items to dest")

        #expect(box.inTrash == [])
    }

    @Test func aDuplicateIsUndoneByPuttingItInTheTrash() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")

        try await roundTrip(
            .duplicate(items: [file]), undid: "Undid: duplicated notes.md", redid: "Redid: duplicated notes.md")

        #expect(box.names(in: src) == ["notes.md"])
        #expect(box.inTrash.map(\.lastPathComponent).allSatisfy { $0.hasPrefix("notes copy") })
    }

    @Test func aRenameIsUndoneByGivingTheOldNameBack() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")

        try await roundTrip(
            .rename(item: file, to: "ideas.md"),
            undid: "Undid: renamed notes.md to ideas.md", redid: "Redid: renamed notes.md to ideas.md")
    }

    @Test func aRenameToOtherCapitalsIsUndone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")

        try await roundTrip(
            .rename(item: file, to: "Notes.md"),
            undid: "Undid: renamed notes.md to Notes.md", redid: "Redid: renamed notes.md to Notes.md")

        #expect(box.names(in: src) == ["notes.md"])
    }

    @Test func aNewFolderIsUndoneByPuttingItInTheTrash() async throws {
        try await roundTrip(
            .newFolder(in: dest, name: "Plans"),
            undid: "Undid: made the folder Plans", redid: "Redid: made the folder Plans")

        #expect(box.inTrash.count == 2)
    }

    @Test func aTrashIsUndoneByPuttingTheItemsBackWhereTheyWere() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        try box.makeFile("src/Tree/deep/two.txt", "two")
        let date = box.modified(file)

        try await roundTrip(
            .trash(items: [file, box.path("src/Tree")]),
            undid: "Undid: moved 2 items to the Trash", redid: "Redid: moved 2 items to the Trash")

        // The very items, not copies of them.
        #expect(box.modified(file) == date)
    }

    @Test func aReplacingCopyIsUndoneByTrashingTheNewcomerAndPuttingTheOldOneBack() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let old = try box.makeFile("dest/notes.md", "old")
        try box.makeFile("src/Tree/new.txt", "new")
        try box.makeFile("dest/Tree/old.txt", "old")

        try await roundTrip(
            .copy(items: [file, box.path("src/Tree")], to: dest), choice: .replace,
            undid: "Undid: copied 2 items to dest", redid: "Redid: copied 2 items to dest")

        #expect(box.text(old) == "old")
        #expect(box.names(in: box.path("dest/Tree")) == ["old.txt"])
    }

    @Test func aReplacingMoveIsUndoneByMovingTheNewcomerBackAndPuttingTheOldOneBack() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let old = try box.makeFile("dest/notes.md", "old")

        try await roundTrip(
            .move(items: [file], to: dest), choice: .replace,
            undid: "Undid: moved notes.md to dest", redid: "Redid: moved notes.md to dest")

        #expect(box.text(file) == "new")
        #expect(box.text(old) == "old")
    }

    @Test func aCopyThatKeptBothIsUndone() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        try box.makeFile("dest/notes.md", "old")

        try await roundTrip(
            .copy(items: [file], to: dest), choice: .keepBoth,
            undid: "Undid: copied notes.md to dest", redid: "Redid: copied notes.md to dest")

        #expect(box.names(in: dest) == ["notes.md"])
    }

    /// The item comes back from another folder and from another name at once.
    @Test func aMoveThatKeptBothIsUndoneToTheOldFolderAndTheOldName() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        try box.makeFile("dest/notes.md", "old")

        try await roundTrip(
            .move(items: [file], to: dest), choice: .keepBoth,
            undid: "Undid: moved notes.md to dest", redid: "Redid: moved notes.md to dest")

        #expect(box.text(file) == "new")
        #expect(box.names(in: dest) == ["notes.md"])
    }

    @Test func aSkippedNameIsSkippedAgainByARedo() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let other = try box.makeFile("src/other.md", "other")
        let old = try box.makeFile("dest/notes.md", "old")

        await perform(.copy(items: [file, other], to: dest), choice: .skip)
        let after = box.listing()
        _ = try await stack.undo()
        #expect(box.names(in: dest) == ["notes.md"])

        _ = try await stack.redo()

        #expect(box.listing() == after)
        #expect(box.text(old) == "old")
    }

    // MARK: The stack

    @Test func undoGoesBackOneOperationAtATimeAndRedoForthAgain() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let start = box.listing()
        await perform(.copy(items: [file], to: dest))
        let copied = box.listing()
        await perform(.rename(item: file, to: "ideas.md"))
        let renamed = box.listing()

        #expect(try await stack.undo() == "Undid: renamed notes.md to ideas.md")
        #expect(box.listing() == copied)
        #expect(try await stack.undo() == "Undid: copied notes.md to dest")
        #expect(box.listing() == start)
        #expect(await stack.canUndo == false)

        #expect(try await stack.redo() == "Redid: copied notes.md to dest")
        #expect(box.listing() == copied)
        #expect(try await stack.redo() == "Redid: renamed notes.md to ideas.md")
        #expect(box.listing() == renamed)
        #expect(await stack.canRedo == false)
    }

    @Test func aNewOperationClearsRedo() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        await perform(.copy(items: [file], to: dest))
        _ = try await stack.undo()
        #expect(await stack.canRedo)

        await perform(.rename(item: file, to: "ideas.md"))

        #expect(await stack.canRedo == false)
        #expect(await refusal { try await stack.redo() } == "There is nothing to redo")
        #expect(box.names(in: dest) == [])
    }

    @Test func anOutcomeWithoutChangesRecordsNothingAndKeepsRedo() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        #expect(await refusal { try await stack.undo() } == "There is nothing to undo")
        await perform(.copy(items: [file], to: dest))
        _ = try await stack.undo()

        // Refused: a move to where it is.
        let outcome = await perform(.move(items: [file], to: src))

        #expect(outcome.changes == [])
        #expect(await stack.canUndo == false)
        #expect(await stack.canRedo)
    }

    @Test func anOutcomeRecordedWithoutItsOperationIsUndoneButNotRedone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let before = box.listing()
        let outcome = await runner.run(.move(items: [file], to: dest), resolve: { _ in .skip }, progress: { _ in })

        await stack.record(outcome, words: outcome.summary)
        #expect(try await stack.undo() == "Undid: moved notes.md to dest")

        #expect(box.listing() == before)
        #expect(await stack.canRedo == false)
    }

    // MARK: After the world moved on (Review Focus 5)

    @Test func aCopyOfAnotherSizeIsNotUndone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let other = try box.makeFile("src/other.md", "other")
        await perform(.copy(items: [file, other], to: dest))
        let copy = dest.appendingPathComponent("notes.md")
        let date = try #require(box.modified(copy))
        try Data("some notes, and more of them".utf8).write(to: copy)
        try box.files.setAttributes([.modificationDate: date], ofItemAtPath: copy.path)
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: notes.md has changed")
        // Nothing is touched: not the copy that didn't change either.
        #expect(box.listing() == after)
        #expect(box.inTrash == [])
        #expect(await stack.canUndo)
        #expect(await stack.canRedo == false)
    }

    @Test func aCopyOfAnotherDateIsNotUndone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        await perform(.copy(items: [file], to: dest))
        let copy = dest.appendingPathComponent("notes.md")
        // The same length, written a minute later.
        try Data("SOME NOTES".utf8).write(to: copy)
        let date = try #require(box.modified(copy))
        try box.files.setAttributes([.modificationDate: date + 60], ofItemAtPath: copy.path)
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: notes.md has changed")
        #expect(box.listing() == after)
        #expect(box.inTrash == [])
    }

    @Test func aCopiedFolderThatGotAnItemIsNotUndone() async throws {
        try box.makeFile("src/Tree/one.txt", "one")
        await perform(.copy(items: [box.path("src/Tree")], to: dest))
        try box.makeFile("dest/Tree/mine.txt", "written since")
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: Tree has changed")
        #expect(box.listing() == after)
        #expect(box.inTrash == [])
    }

    @Test func aCopyThatIsGoneIsNotUndone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let other = try box.makeFile("src/other.md", "other")
        await perform(.copy(items: [file, other], to: dest))
        try box.files.removeItem(at: dest.appendingPathComponent("notes.md"))
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: notes.md is no longer there")
        #expect(box.listing() == after)
        #expect(box.inTrash == [])
    }

    @Test func aNewFolderWithSomethingInItIsNotUndone() async throws {
        await perform(.newFolder(in: dest, name: "Plans"))
        try box.makeFile("dest/Plans/plan.md", "a plan")
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: Plans is no longer empty")
        #expect(box.listing() == after)
        #expect(box.inTrash == [])
    }

    @Test func aTrashedItemGoneFromTheTrashIsNotPutBack() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let other = try box.makeFile("src/other.md", "other")
        await perform(.trash(items: [file, other]))
        // The Trash was emptied: of the test's own item.
        try box.files.removeItem(at: box.inTrash[0])
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: notes.md is no longer in the Trash")
        // The other one stays in the Trash too.
        #expect(box.listing() == after)
        #expect(box.text(box.inTrash[1]) == "other")
    }

    @Test func aMoveIsNotUndoneOntoAnItemNowAtTheOldPlace() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let other = try box.makeFile("src/other.md", "other")
        await perform(.move(items: [file, other], to: dest))
        try box.makeFile("src/notes.md", "written since")
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: another item is now where notes.md was")
        #expect(box.listing() == after)
        #expect(box.text(file) == "written since")
    }

    @Test func aTrashIsNotUndoneOntoAnItemNowAtTheOldPlace() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        await perform(.trash(items: [file]))
        try box.makeFile("src/notes.md", "written since")

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: another item is now where notes.md was")
        #expect(box.text(file) == "written since")
        #expect(box.text(box.inTrash[0]) == "some notes")
    }

    @Test func aMoveIsNotUndoneWhenItsOldFolderIsGone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        await perform(.move(items: [file], to: dest))
        try box.files.removeItem(at: src)
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: the folder src is no longer there")
        #expect(box.listing() == after)
    }

    @Test func aReplaceIsNotUndoneWhenTheOldOneIsGoneFromTheTrash() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        try box.makeFile("dest/notes.md", "old")
        await perform(.copy(items: [file], to: dest), choice: .replace)
        try box.files.removeItem(at: box.inTrash[0])
        let after = box.listing()

        let said = await refusal { try await stack.undo() }

        #expect(said == "Can't undo: notes.md is no longer in the Trash")
        // The newcomer stays where it is: it is not trashed for nothing.
        #expect(box.listing() == after)
        #expect(box.inTrash.count == 1)
    }

    @Test func aRefusedUndoWorksOnceTheWorldIsAsItWas() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let before = box.listing()
        await perform(.move(items: [file], to: dest))
        try box.makeFile("src/notes.md", "in the way")
        #expect(await refusal { try await stack.undo() } != nil)

        try box.files.removeItem(at: file)

        #expect(try await stack.undo() == "Undid: moved notes.md to dest")
        #expect(box.listing() == before)
    }

    @Test func aPartlyCancelledMoveUndoesOnlyWhatItDid() async throws {
        let items = try (0..<4).map { try box.makeFile("src/file-\($0).txt", "file \($0)") }
        let before = box.listing()
        let placed = Locked(0)
        let itself = Locked<OperationRunner?>(nil)
        let runner = OperationRunner(fileManager: box.trash, watching: { stage in
            guard case .placing = stage, placed.change({ $0 += 1; return $0 }) == 2, let runner = itself.value
            else { return }
            let done = DispatchSemaphore(value: 0)
            Task {
                await runner.cancel()
                done.signal()
            }
            done.wait()
        })
        itself.value = runner
        let stack = UndoStack(runner: runner)

        let outcome = await GroveExplorerCoreTests.perform(.move(items: items, to: dest), on: runner, into: stack)
        #expect(outcome.cancelled)
        #expect(outcome.changes.count == 2)
        #expect(box.names(in: src).count == 2)

        #expect(try await stack.undo() == "Undid: moved 2 of 4 items (cancelled)")

        #expect(box.listing() == before)
        // Doing it again would do more than it did.
        #expect(await stack.canRedo == false)
    }

    /// The outcome of a replace whose newcomer didn't come and whose old
    /// item could not get its name back: one `.trashed`, beside a failure.
    @Test func anItemLeftInTheTrashByAFailedReplaceIsPutBack() async throws {
        let old = try box.makeFile("dest/notes.md", "old")
        let before = box.listing()
        let trashed = await runner.run(.trash(items: [old]), resolve: { _ in .skip }, progress: { _ in })
        guard case let .trashed(_, inTrash)? = trashed.changes.first else {
            Issue.record("not trashed")
            return
        }
        let outcome = Outcome(
            changes: [.trashed(original: old, inTrash: inTrash)],
            failures: [ItemFailure(url: box.path("src/notes.md"), reason: "you don't have permission")],
            cancelled: false, summary: "Nothing copied (1 failed)")

        await stack.record(
            outcome, words: outcome.summary, operation: .copy(items: [box.path("src/notes.md")], to: dest))
        #expect(try await stack.undo() == "Undid: nothing copied (1 failed)")

        #expect(box.listing() == before)
        #expect(await stack.canRedo == false)
    }

    // MARK: A failure in the middle

    @Test func anUndoThatFailsInTheMiddleStopsAndSaysWhatWasUndone() async throws {
        let files = try ["a.txt", "b.txt", "c.txt"].map { try box.makeFile("src/\($0)", $0) }
        await perform(.copy(items: files, to: dest))
        box.trash.refused.value = ["a.txt"]

        let said = await refusal { try await stack.undo() }

        // The last change is undone first.
        #expect(said == "Undo stopped: a.txt could not be moved to the Trash (you don't have permission). "
            + "Already undone: c.txt, b.txt; the rest is as it was.")
        #expect(box.names(in: dest) == ["a.txt"])
        #expect(box.names(in: src) == ["a.txt", "b.txt", "c.txt"])
        // It can't be tried again, nor redone.
        #expect(await stack.canUndo == false)
        #expect(await stack.canRedo == false)
    }

    @Test func anUndoThatFailsAtOnceSaysNothingWasUndone() async throws {
        let file = try box.makeFile("src/a.txt", "a")
        await perform(.copy(items: [file], to: dest))
        box.trash.refused.value = ["a.txt"]

        let said = await refusal { try await stack.undo() }

        #expect(said == "Undo stopped: a.txt could not be moved to the Trash (you don't have permission). "
            + "Nothing was undone.")
        #expect(box.names(in: dest) == ["a.txt"])
        #expect(await stack.canUndo == false)
    }

    /// Between the checks and the second step, an item takes the place.
    @Test func anItemThatAppearsWhileAnUndoRunsStopsItAndIsNotWrittenOver() async throws {
        let files = try ["a.txt", "b.txt"].map { try box.makeFile("src/\($0)", $0) }
        let box = box
        let undoing = Locked(false)
        let runner = OperationRunner(fileManager: box.trash, watching: { stage in
            // b.txt goes back first: as it does, something is written at a.txt's place.
            guard undoing.value, case let .placing(url) = stage, url.lastPathComponent == "b.txt" else { return }
            _ = try? box.makeFile("src/a.txt", "written since")
        })
        let stack = UndoStack(runner: runner)
        await GroveExplorerCoreTests.perform(.move(items: files, to: dest), on: runner, into: stack)
        undoing.value = true

        let said = await refusal { try await stack.undo() }

        #expect(said == "Undo stopped: another item is now where a.txt was. "
            + "Already undone: b.txt; the rest is as it was.")
        #expect(box.text(box.path("src/a.txt")) == "written since")
        #expect(box.text(box.path("src/b.txt")) == "b.txt")
        #expect(box.text(dest.appendingPathComponent("a.txt")) == "a.txt")
        #expect(box.names(in: dest) == ["a.txt"])
        #expect(await stack.canUndo == false)
        #expect(await stack.canRedo == false)
    }

    // MARK: Putting back, the runner's part

    @Test func putMovesAnItemToExactlyThePlaceAndTheName() async throws {
        let file = try box.makeFile("dest/notes 2.md", "some notes")
        let place = box.path("src/notes.md")

        let outcome = await runner.put(file, at: place)

        #expect(outcome.changes == [.moved(from: file, to: place)])
        #expect(outcome.failures == [])
        #expect(box.text(place) == "some notes")
        #expect(box.names(in: dest) == [])
    }

    @Test func putNeverTakesAPlaceThatIsTaken() async throws {
        let file = try box.makeFile("dest/notes 2.md", "some notes")
        let tree = try box.makeFolder("dest/Tree 2")
        let place = try box.makeFile("src/notes.md", "there already")
        try box.makeFile("src/Tree/mine.txt", "there already")
        let before = box.listing()

        let outcome = await runner.put(file, at: place)
        let folder = await runner.put(tree, at: box.path("src/Tree"))

        #expect(outcome.changes == [])
        #expect(outcome.failures == [ItemFailure(url: file, reason: "an item with that name appeared")])
        #expect(folder.changes == [])
        #expect(folder.failures == [ItemFailure(url: tree, reason: "an item with that name appeared")])
        #expect(box.listing() == before)
    }

    @Test func putFailsWhenTheFolderIsNotThere() async throws {
        let file = try box.makeFile("dest/notes.md", "some notes")

        let outcome = await runner.put(file, at: box.path("gone/notes.md"))

        #expect(outcome.changes == [])
        #expect(outcome.failures == [ItemFailure(url: file, reason: "the folder “gone” is not there")])
        #expect(box.text(file) == "some notes")
    }

    // MARK: Redo after the world moved on

    @Test func aRedoIsRefusedWhenANameIsNowInTheWay() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let other = try box.makeFile("src/other.md", "other")
        await perform(.copy(items: [file, other], to: dest))
        _ = try await stack.undo()
        let mine = try box.makeFile("dest/notes.md", "written since")
        let after = box.listing()

        let said = await refusal { try await stack.redo() }

        #expect(said == "Can't redo: notes.md is now in the way")
        // Nothing is asked, replaced or copied: not the other file either.
        #expect(box.listing() == after)
        #expect(box.text(mine) == "written since")
        #expect(await stack.canRedo)
    }

    @Test func aRedoIsRefusedWhenAnAnsweredNameIsNoLongerThere() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let old = try box.makeFile("dest/notes.md", "old")
        await perform(.copy(items: [file], to: dest), choice: .keepBoth)
        _ = try await stack.undo()
        try box.files.removeItem(at: old)

        let said = await refusal { try await stack.redo() }

        // It would now arrive as notes.md, not as notes 2.md.
        #expect(said == "Can't redo: notes.md is no longer there")
        #expect(box.names(in: dest) == [])
    }

    @Test func aRedoIsRefusedWhenAnItemOfTheOperationIsGone() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        let other = try box.makeFile("src/other.md", "other")
        await perform(.copy(items: [file, other], to: dest))
        _ = try await stack.undo()
        try box.files.removeItem(at: other)

        let said = await refusal { try await stack.redo() }

        #expect(said == "Can't redo: other.md is no longer there")
        #expect(box.names(in: dest) == [])
        #expect(await stack.canRedo)
    }
}

// MARK: - Across volumes

/// Undo with a disk image, attached under the test's own temporary folder
/// and out of Finder's sight, and detached when the test ends. Skipped,
/// with the reason, on a Mac where `hdiutil` can't make or attach an image.
@Suite(.serialized) final class UndoVolumeTests {
    private let box: Sandbox
    private let runner: OperationRunner
    private let stack: UndoStack
    private let attached = Locked<[URL]>([])

    init() throws {
        box = try Sandbox("undo-volumes")
        runner = OperationRunner(fileManager: box.trash)
        stack = UndoStack(runner: runner)
    }

    deinit {
        for volume in attached.value.reversed() { _ = try? Self.hdiutil(["detach", volume.path, "-force"]) }
        box.cleanUp()
    }

    private struct ToolFailure: Error, CustomStringConvertible {
        let description: String
    }

    private static func hdiutil(_ arguments: [String]) throws {
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        tool.arguments = arguments
        let errors = Pipe()
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = errors
        try tool.run()
        let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        tool.waitUntilExit()
        guard tool.terminationStatus == 0 else {
            throw ToolFailure(description: "hdiutil \(arguments.first ?? "") failed: \(said)")
        }
    }

    /// A new, empty volume of 20 MB, attached at a folder under the test's own.
    private func volume(_ name: String) throws -> URL {
        let image = box.path("\(name).dmg")
        let mountPoint = box.path("mnt-\(name)")
        do {
            try Self.hdiutil(["create", "-size", "20m", "-fs", "APFS", "-volname", name, image.path])
            try box.files.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            try Self.hdiutil(["attach", image.path, "-mountpoint", mountPoint.path, "-nobrowse"])
        } catch {
            try Test.cancel("skipped: no disk image to test with (\(error))")
        }
        attached.change { $0.append(mountPoint) }
        return mountPoint
    }

    private func detach(_ volume: URL) throws {
        try Self.hdiutil(["detach", volume.path, "-force"])
        attached.change { $0.removeAll { $0 == volume } }
    }

    @Test func aMoveToAnotherVolumeIsUndoneAndRedone() async throws {
        let disk = try volume("GroveUndo")
        let home = try box.makeFolder("home")
        let file = try box.makeFile("home/notes.md", "some notes")
        try box.makeFile("home/Tree/deep/two.txt", "two")
        let before = box.listing(home)

        let moved = await perform(.move(items: [file, box.path("home/Tree")], to: disk), on: runner, into: stack)
        #expect(moved.failures == [])
        #expect(box.names(in: home) == [])

        #expect(try await stack.undo() == "Undid: moved 2 items to mnt-GroveUndo")
        #expect(box.listing(home) == before)
        #expect(box.names(in: disk).filter { !$0.hasPrefix(".") } == [])

        #expect(try await stack.redo() == "Redid: moved 2 items to mnt-GroveUndo")
        #expect(box.names(in: home) == [])
        #expect(box.text(disk.appendingPathComponent("Tree/deep/two.txt")) == "two")
    }

    @Test func nothingIsUndoneOnADiskThatIsNoLongerThere() async throws {
        let disk = try volume("GroveGone")
        let home = try box.makeFolder("home")
        let other = try box.makeFile("home/other.md", "other")
        let onDisk = try box.makeFile(at: disk.appendingPathComponent("notes.md"), "from the disk")
        // One operation's item came from the disk, the other's is on it.
        let fromTheDisk = UndoStack(runner: runner)
        await perform(.move(items: [onDisk], to: home), on: runner, into: fromTheDisk)
        await perform(.copy(items: [other], to: disk), on: runner, into: stack)
        try detach(disk)
        let after = box.listing(home)
        #expect(after.count == 2)

        // The copy on the disk can't be trashed, and nothing can go back to it.
        #expect(await refusal { try await stack.undo() } == "Can't undo: the disk GroveGone is no longer there")
        #expect(await refusal { try await fromTheDisk.undo() } == "Can't undo: the disk GroveGone is no longer there")

        #expect(box.listing(home) == after)
        #expect(box.inTrash == [])
        #expect(await stack.canUndo)
        #expect(await fromTheDisk.canUndo)
    }
}
