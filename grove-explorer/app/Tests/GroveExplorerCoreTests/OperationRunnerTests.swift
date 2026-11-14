import Foundation
@testable import GroveExplorerCore
import Testing

// Foundation has an `Operation` and a `Progress` too.
private typealias Operation = GroveExplorerCore.Operation
private typealias Progress = GroveExplorerCore.Progress

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

/// What the tests of both suites do to files: everything under one
/// temporary folder, removed when the test ends, passed or failed. Whatever
/// a run puts in the Trash is taken out of it again, by the address the
/// Trash gave: nothing else in the Trash is looked at or touched.
private final class Sandbox: @unchecked Sendable {
    let root: URL
    let files = FileManager.default
    let inTrash = Locked<[URL]>([])

    init(_ label: String) throws {
        let made = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-\(label)-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: made, withIntermediateDirectories: true)
        // The address as the system gives it for the folder (/private/var/…),
        // so that an address in a Trash can be compared with it.
        guard let real = realpath(made.path, nil) else { throw CocoaError(.fileNoSuchFile) }
        defer { free(real) }
        root = URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    /// Call from `deinit`.
    func cleanUp() {
        let manager = FileManager.default
        for url in inTrash.value { try? manager.removeItem(at: url) }
        // A folder made read-only by a test would keep its contents.
        if let all = manager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in all {
                var info = stat()
                guard lstat(url.path, &info) == 0 else { continue }
                if info.st_flags != 0 { lchflags(url.path, 0) }
                if info.st_mode & S_IFMT == S_IFDIR { chmod(url.path, 0o700) }
            }
        }
        try? manager.removeItem(at: root)
    }

    func path(_ name: String) -> URL { root.appendingPathComponent(name) }

    @discardableResult func makeFolder(_ name: String) throws -> URL {
        try makeFolder(at: path(name))
    }

    @discardableResult func makeFolder(at url: URL) throws -> URL {
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult func makeFile(_ name: String, _ text: String = "text") throws -> URL {
        try makeFile(at: path(name), Data(text.utf8))
    }

    @discardableResult func makeFile(at url: URL, _ data: Data) throws -> URL {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// There, as a file, a folder or a link (a link to nothing included).
    func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    func names(in folder: URL) -> [String] {
        ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// Every name, as the volume lists them: `names` leaves out the
    /// `._name` files macOS keeps beside files on some volumes.
    func allNames(in folder: URL) -> [String] {
        (TreeCopier.names(in: folder.path) ?? []).sorted()
    }

    /// The names a half-written copy would have.
    func partials(in folder: URL) -> [String] {
        allNames(in: folder).filter { $0.contains(".grove-partial-") }
    }

    func inode(_ url: URL) -> UInt64? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? UInt64(info.st_ino) : nil
    }

    func mode(_ url: URL) -> mode_t? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? info.st_mode & 0o7777 : nil
    }

    func modified(_ url: URL) -> Date? {
        (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func setModified(_ date: Date, _ url: URL) throws {
        try files.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func setAttribute(_ name: String, _ value: String, on url: URL) {
        let bytes = Array(value.utf8)
        #expect(setxattr(url.path, name, bytes, bytes.count, 0, XATTR_NOFOLLOW) == 0)
    }

    func attribute(_ name: String, of url: URL) -> String? {
        var bytes = [UInt8](repeating: 0, count: 256)
        let length = getxattr(url.path, name, &bytes, bytes.count, 0, XATTR_NOFOLLOW)
        return length < 0 ? nil : String(decoding: bytes[..<length], as: UTF8.self)
    }

    func setTags(_ tags: [String], on url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    func tags(of url: URL) -> [String] {
        // A fresh URL: a URL keeps the values it once read.
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// Runs the operation. A name that exists gets `choice`; with none
    /// given, being asked at all is a failure of the test.
    func run(
        _ operation: Operation, on runner: OperationRunner, choice: Conflict.Choice? = nil,
        progress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async -> Outcome {
        let outcome = await runner.run(
            operation,
            resolve: { url in
                if let choice { return choice }
                Issue.record("asked what to do about \(url.lastPathComponent)")
                return .skip
            },
            progress: progress)
        for change in outcome.changes {
            switch change {
            case let .trashed(_, url), let .replaced(_, url): inTrash.change { $0.append(url) }
            case .created, .moved: break
            }
        }
        return outcome
    }
}

// MARK: - On one volume

/// Every operation against real files, in a temporary folder of the test's
/// own. One test at a time: all at once they take every fast core, and the
/// timed tests of other suites then miss their limits.
@Suite(.serialized) final class OperationRunnerTests {
    private let box: Sandbox
    private let runner = OperationRunner()
    private static let aDate = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        box = try Sandbox("operations")
        try box.makeFolder("src")
        try box.makeFolder("dest")
    }

    deinit { box.cleanUp() }

    private var src: URL { box.path("src") }
    private var dest: URL { box.path("dest") }

    // MARK: Every operation

    @Test func aCopiedFileKeepsItsDatesPermissionsAttributesAndTags() async throws {
        let file = try box.makeFile("src/notes.md", "some notes")
        box.setAttribute("com.projectgrove.test", "kept", on: file)
        try box.setTags(["Grove Test"], on: file)
        #expect(chmod(file.path, 0o640) == 0)
        try box.files.setAttributes([.creationDate: Self.aDate - 86_400], ofItemAtPath: file.path)
        try box.setModified(Self.aDate, file)

        let outcome = await box.run(.copy(items: [file], to: dest), on: runner)

        let copy = dest.appendingPathComponent("notes.md")
        #expect(outcome == Outcome(
            changes: [.created(copy)], failures: [], cancelled: false,
            summary: "Copied notes.md to dest"))
        #expect(box.text(copy) == "some notes")
        #expect(box.text(file) == "some notes")
        #expect(box.modified(copy) == Self.aDate)
        let created = try box.files.attributesOfItem(atPath: copy.path)[.creationDate] as? Date
        #expect(created == Self.aDate - 86_400)
        #expect(box.mode(copy) == 0o640)
        #expect(box.attribute("com.projectgrove.test", of: copy) == "kept")
        #expect(box.tags(of: copy) == ["Grove Test"])
        #expect(box.names(in: dest) == ["notes.md"])
    }

    @Test func aCopiedTreeIsWholeAndKeepsWhatItsFoldersAndFilesHad() async throws {
        try box.makeFile("src/Tree/one.txt", "one")
        try box.makeFile("src/Tree/a/two.txt", "two")
        try box.makeFile("src/Tree/a/deep/three.txt", "three")
        try box.makeFile("src/Tree/a/.hidden", "hidden")
        try box.makeFolder("src/Tree/empty")
        try box.makeFolder("src/Tree/locked")
        try box.makeFile("src/Tree/locked/inside.txt", "inside")
        let tree = box.path("src/Tree")
        box.setAttribute("com.projectgrove.test", "a folder's", on: tree.appendingPathComponent("a"))
        try box.setTags(["Grove Test"], on: tree.appendingPathComponent("a/two.txt"))
        #expect(chmod(tree.appendingPathComponent("a/two.txt").path, 0o600) == 0)
        try box.setModified(Self.aDate, tree.appendingPathComponent("a/deep/three.txt"))
        // Last, so that nothing above changes them again: a folder that
        // can't be written to, and the dates of two folders.
        #expect(chmod(tree.appendingPathComponent("locked").path, 0o555) == 0)
        try box.setModified(Self.aDate, tree.appendingPathComponent("a"))
        try box.setModified(Self.aDate, tree)

        let outcome = await box.run(.copy(items: [tree], to: dest), on: runner)

        let copy = dest.appendingPathComponent("Tree")
        #expect(outcome.changes == [.created(copy)])
        #expect(outcome.failures == [])
        #expect(outcome.summary == "Copied Tree to dest")
        #expect(box.names(in: copy) == ["a", "empty", "locked", "one.txt"])
        #expect(box.names(in: copy.appendingPathComponent("a")) == [".hidden", "deep", "two.txt"])
        #expect(box.names(in: copy.appendingPathComponent("empty")) == [])
        #expect(box.text(copy.appendingPathComponent("one.txt")) == "one")
        #expect(box.text(copy.appendingPathComponent("a/two.txt")) == "two")
        #expect(box.text(copy.appendingPathComponent("a/deep/three.txt")) == "three")
        #expect(box.text(copy.appendingPathComponent("a/.hidden")) == "hidden")
        #expect(box.text(copy.appendingPathComponent("locked/inside.txt")) == "inside")
        #expect(box.mode(copy.appendingPathComponent("locked")) == 0o555)
        #expect(box.mode(copy.appendingPathComponent("a/two.txt")) == 0o600)
        #expect(box.attribute("com.projectgrove.test", of: copy.appendingPathComponent("a")) == "a folder's")
        #expect(box.tags(of: copy.appendingPathComponent("a/two.txt")) == ["Grove Test"])
        #expect(box.modified(copy.appendingPathComponent("a/deep/three.txt")) == Self.aDate)
        #expect(box.modified(copy.appendingPathComponent("a")) == Self.aDate)
        #expect(box.modified(copy) == Self.aDate)
        #expect(box.names(in: dest) == ["Tree"])
        // The source is as it was.
        #expect(box.names(in: tree) == ["a", "empty", "locked", "one.txt"])
    }

    @Test func aMoveOnOneVolumeIsOneRename() async throws {
        try box.makeFile("src/Tree/a/two.txt", "two")
        let tree = box.path("src/Tree")
        let file = try box.makeFile("src/notes.md", "notes")
        let treeNumber = try #require(box.inode(tree))
        let innerNumber = try #require(box.inode(tree.appendingPathComponent("a/two.txt")))
        let fileNumber = try #require(box.inode(file))

        let outcome = await box.run(.move(items: [tree, file], to: dest), on: runner)

        let movedTree = dest.appendingPathComponent("Tree")
        let movedFile = dest.appendingPathComponent("notes.md")
        #expect(outcome == Outcome(
            changes: [.moved(from: tree, to: movedTree), .moved(from: file, to: movedFile)],
            failures: [], cancelled: false, summary: "Moved 2 items to dest"))
        // The same items under another name, not copies: their numbers on
        // the volume are the ones they had.
        #expect(box.inode(movedTree) == treeNumber)
        #expect(box.inode(movedTree.appendingPathComponent("a/two.txt")) == innerNumber)
        #expect(box.inode(movedFile) == fileNumber)
        #expect(box.names(in: src) == [])
        #expect(box.names(in: dest) == ["Tree", "notes.md"])
    }

    @Test func duplicatesAreNamedCopyThenCopy2() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let folder = try box.makeFolder("src/docs")
        try box.makeFile("src/docs/inside.txt", "inside")
        let dotFile = try box.makeFile("src/.env", "secret")
        let archive = try box.makeFile("src/archive.tar.gz", "archive")

        let first = await box.run(.duplicate(items: [file, folder, dotFile, archive]), on: runner)
        #expect(first.changes == [
            .created(box.path("src/notes copy.md")), .created(box.path("src/docs copy")),
            .created(box.path("src/.env copy")), .created(box.path("src/archive copy.tar.gz")),
        ])
        #expect(first.summary == "Duplicated 4 items")
        #expect(box.text(box.path("src/notes copy.md")) == "notes")
        #expect(box.text(box.path("src/docs copy/inside.txt")) == "inside")

        let second = await box.run(.duplicate(items: [file, folder]), on: runner)
        #expect(second.changes == [
            .created(box.path("src/notes copy 2.md")), .created(box.path("src/docs copy 2")),
        ])
        let third = await box.run(.duplicate(items: [file]), on: runner)
        #expect(third.changes == [.created(box.path("src/notes copy 3.md"))])
        #expect(third.summary == "Duplicated notes.md")
        #expect(box.names(in: src) == [
            ".env", ".env copy", "archive copy.tar.gz", "archive.tar.gz", "docs", "docs copy",
            "docs copy 2", "notes copy 2.md", "notes copy 3.md", "notes copy.md", "notes.md",
        ])
    }

    @Test func renameGivesTheItemItsNewName() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let number = try #require(box.inode(file))

        let outcome = await box.run(.rename(item: file, to: "ideas.md"), on: runner)

        let renamed = box.path("src/ideas.md")
        #expect(outcome == Outcome(
            changes: [.moved(from: file, to: renamed)], failures: [], cancelled: false,
            summary: "Renamed notes.md to ideas.md"))
        #expect(box.inode(renamed) == number)
        #expect(box.names(in: src) == ["ideas.md"])
    }

    @Test func renameToANameThatDiffersOnlyByCaseWorks() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let renamed = box.path("src/Notes.md")
        #expect(await runner.existingNames(for: .rename(item: file, to: "Notes.md")) == [])

        let outcome = await box.run(.rename(item: file, to: "Notes.md"), on: runner)

        #expect(outcome.changes == [.moved(from: file, to: renamed)])
        #expect(outcome.failures == [])
        #expect(box.names(in: src) == ["Notes.md"])
        #expect(box.text(renamed) == "notes")
    }

    @Test func renameNeverTakesTheNameOfAnotherItem() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let other = try box.makeFile("src/ideas.md", "ideas")
        #expect(await runner.existingNames(for: .rename(item: file, to: "ideas.md")) == [other])

        // Whatever the answer would be, a rename doesn't ask: it fails.
        let outcome = await box.run(.rename(item: file, to: "ideas.md"), on: runner)

        #expect(outcome.changes == [])
        #expect(outcome.failures == [
            ItemFailure(url: file, reason: "an item named “ideas.md” is already there")
        ])
        #expect(outcome.summary == "Nothing renamed (1 failed)")
        #expect(box.text(file) == "notes")
        #expect(box.text(other) == "ideas")
    }

    @Test func newFolderMakesOneAndNeverTakesANameInUse() async throws {
        let operation = Operation.newFolder(in: dest, name: "Projects")
        #expect(await runner.existingNames(for: operation) == [])

        let outcome = await box.run(operation, on: runner)

        let folder = dest.appendingPathComponent("Projects")
        #expect(outcome == Outcome(
            changes: [.created(folder)], failures: [], cancelled: false,
            summary: "Made the folder Projects"))
        var isFolder: ObjCBool = false
        #expect(box.files.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue)

        try box.makeFile(at: folder.appendingPathComponent("kept.txt"), Data("kept".utf8))
        #expect(await runner.existingNames(for: operation) == [folder])
        let again = await box.run(operation, on: runner)
        #expect(again.changes == [])
        #expect(again.failures == [
            ItemFailure(url: folder, reason: "an item named “Projects” is already there")
        ])
        #expect(box.text(folder.appendingPathComponent("kept.txt")) == "kept")
    }

    @Test func trashReturnsWhereTheItemsAreInTheTrash() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        try box.makeFile("src/docs/inside.txt", "inside")
        let folder = box.path("src/docs")

        let outcome = await box.run(.trash(items: [file, folder]), on: runner)

        #expect(outcome.failures == [])
        #expect(outcome.summary == "Moved 2 items to the Trash")
        try #require(outcome.changes.count == 2)
        guard case let .trashed(firstOriginal, fileInTrash) = outcome.changes[0],
            case let .trashed(secondOriginal, folderInTrash) = outcome.changes[1]
        else {
            Issue.record("not two items put in the Trash: \(outcome.changes)")
            return
        }
        #expect(firstOriginal == file)
        #expect(secondOriginal == folder)
        #expect(box.names(in: src) == [])
        // In the Trash, whole, and not anywhere under the test's folder.
        #expect(!fileInTrash.path.hasPrefix(box.root.path))
        #expect(fileInTrash.path.contains("/.Trash"))
        #expect(box.text(fileInTrash) == "notes")
        #expect(box.text(folderInTrash.appendingPathComponent("inside.txt")) == "inside")
    }

    @Test func anItemThatIsNotThereFailsAndTheOthersAreDone() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let missing = box.path("src/missing.md")

        let outcome = await box.run(.trash(items: [missing, file]), on: runner)

        #expect(outcome.failures == [ItemFailure(url: missing, reason: "it is no longer there")])
        #expect(outcome.changes.count == 1)
        #expect(outcome.summary == "Moved 1 of 2 items to the Trash (1 failed)")
        #expect(box.names(in: src) == [])
    }

    // MARK: Refusals (Review Focus 2)

    private func refusal(_ operation: Operation) async -> OperationRefusal? {
        do throws(OperationRefusal) {
            try await runner.validate(operation)
            return nil
        } catch {
            return error
        }
    }

    @Test func aFolderIsNotCopiedOrMovedIntoItself() async throws {
        // By the paths alone: nothing of this is on the disk.
        let a = URL(fileURLWithPath: "/a")
        #expect(await refusal(.copy(items: [a], to: URL(fileURLWithPath: "/a/b"))) == .intoItself(a))
        #expect(await refusal(.copy(items: [a], to: a)) == .intoItself(a))
        #expect(await refusal(.move(items: [a], to: URL(fileURLWithPath: "/a/b/c"))) == .intoItself(a))
        #expect(await refusal(.move(items: [a], to: URL(fileURLWithPath: "/a/../a/b"))) == .intoItself(a))
        // A name that only starts the same is another folder.
        #expect(await refusal(.copy(items: [a], to: URL(fileURLWithPath: "/ab"))) == nil)
        #expect(await refusal(.copy(items: [a], to: URL(fileURLWithPath: "/b"))) == nil)
    }

    @Test func aFolderReachedThroughALinkOrAnotherSpellingIsStillItself() async throws {
        let folder = try box.makeFolder("src/Folder")
        let inner = try box.makeFolder("src/Folder/inner")
        let link = box.path("link-to-inner")
        try box.files.createSymbolicLink(at: link, withDestinationURL: inner)
        let linkToFolder = box.path("link-to-folder")
        try box.files.createSymbolicLink(at: linkToFolder, withDestinationURL: folder)

        #expect(await refusal(.copy(items: [folder], to: link)) == .intoItself(folder))
        #expect(await refusal(.move(items: [folder], to: linkToFolder)) == .intoItself(folder))
        // The item named through a link in its path.
        let throughLink = linkToFolder.appendingPathComponent("inner")
        #expect(await refusal(.copy(items: [throughLink], to: inner)) == .intoItself(throughLink))
        // A link is copied as a link, so it can go into the folder it points at.
        #expect(await refusal(.copy(items: [linkToFolder], to: inner)) == nil)

        // Where the volume takes "FOLDER" for "Folder", so does the check.
        let shouted = box.path("src/FOLDER/inner")
        if box.exists(shouted) {
            #expect(await refusal(.copy(items: [folder], to: shouted)) == .intoItself(folder))
        }

        // And a run writes nothing.
        let outcome = await box.run(.copy(items: [folder], to: link), on: runner)
        #expect(outcome == Outcome(
            changes: [], failures: [], cancelled: false, summary: "“Folder” can't be put inside itself."))
        #expect(box.names(in: inner) == [])
    }

    @Test func anItemIsNotMovedToWhereItIs() async throws {
        let x = URL(fileURLWithPath: "/a/x")
        #expect(await refusal(.move(items: [x], to: URL(fileURLWithPath: "/a"))) == .ontoItself(x))
        #expect(await refusal(.move(items: [x], to: URL(fileURLWithPath: "/a/"))) == .ontoItself(x))
        #expect(await refusal(.move(items: [x], to: URL(fileURLWithPath: "/b"))) == nil)
        // The second of two is found too.
        let y = URL(fileURLWithPath: "/b/y")
        #expect(await refusal(.move(items: [y, x], to: URL(fileURLWithPath: "/a"))) == .ontoItself(x))

        // Through a link to the folder it is in.
        let file = try box.makeFile("src/notes.md", "notes")
        let link = box.path("link-to-src")
        try box.files.createSymbolicLink(at: link, withDestinationURL: src)
        #expect(await refusal(.move(items: [file], to: link)) == .ontoItself(file))

        let outcome = await box.run(.move(items: [file], to: link), on: runner)
        #expect(outcome.changes == [])
        #expect(outcome.summary == "“notes.md” is already there.")
        #expect(box.names(in: src) == ["notes.md"])
    }

    @Test func aNameThatCannotBeUsedIsRefusedWithAReason() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let cases: [(name: String, reason: String)] = [
            ("", "A name can't be empty."),
            ("a/b", "A name can't have a “/” in it."),
            (".", "“.” is not a name an item can have."),
            ("..", "“..” is not a name an item can have."),
            (String(repeating: "n", count: 256), "That name is too long."),
            ("a\0b", "A name can't have that character in it."),
        ]
        for (name, reason) in cases {
            #expect(await refusal(.rename(item: file, to: name)) == .badName(name, reason: reason))
            #expect(await refusal(.newFolder(in: dest, name: name)) == .badName(name, reason: reason))
        }
        #expect(await refusal(.rename(item: file, to: "ideas.md")) == nil)
        #expect(await refusal(.rename(item: file, to: String(repeating: "n", count: 255))) == nil)
        #expect(await refusal(.newFolder(in: dest, name: "Projects")) == nil)

        // A run changes nothing and says why.
        let outcome = await box.run(.rename(item: file, to: "a/b"), on: runner)
        #expect(outcome == Outcome(
            changes: [], failures: [], cancelled: false, summary: "A name can't have a “/” in it."))
        #expect(box.names(in: src) == ["notes.md"])
    }

    @Test func nothingToDoIsRefused() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        #expect(await refusal(.copy(items: [], to: dest)) == .nothingToDo)
        #expect(await refusal(.move(items: [], to: dest)) == .nothingToDo)
        #expect(await refusal(.duplicate(items: [])) == .nothingToDo)
        #expect(await refusal(.trash(items: [])) == .nothingToDo)
        #expect(await refusal(.rename(item: file, to: "notes.md")) == .nothingToDo)
        #expect(await refusal(.trash(items: [file])) == nil)
        #expect(await refusal(.duplicate(items: [file])) == nil)
    }

    // MARK: Safety

    /// A runner that tells `watch` each stage of its work.
    private func watchedRunner(
        _ watch: @escaping @Sendable (OperationRunner.Stage, OperationRunner) -> Void
    ) -> OperationRunner {
        let itself = Locked<OperationRunner?>(nil)
        let runner = OperationRunner(watching: { stage in
            if let runner = itself.value { watch(stage, runner) }
        })
        itself.value = runner
        return runner
    }

    /// Cancels the run from inside it, and comes back when that is done.
    private static func cancelAndWait(_ runner: OperationRunner) {
        let done = DispatchSemaphore(value: 0)
        Task {
            await runner.cancel()
            done.signal()
        }
        done.wait()
    }

    @Test func aCopyIsWrittenUnderAPartialNameAndRenamedAtTheEnd() async throws {
        try box.makeFile("src/Tree/one.txt", "one")
        try box.makeFile("src/Tree/a/two.txt", "two")
        let tree = box.path("src/Tree")
        let file = try box.makeFile("src/notes.md", "notes")
        let seen = Locked<[[String]]>([])
        let box = box
        let dest = dest
        let runner = watchedRunner { stage, _ in
            if case .placing = stage { seen.change { $0.append(box.names(in: dest)) } }
        }

        let outcome = await box.run(.copy(items: [tree, file], to: dest), on: runner)

        #expect(outcome.failures == [])
        // Just before each item got its name: the tree whole under a partial
        // name and nothing else; then the tree in place and the file partial.
        let listings = seen.value
        try #require(listings.count == 2)
        try #require(listings[0].count == 1)
        let partialTree = listings[0][0]
        #expect(partialTree.hasPrefix(".Tree.grove-partial-"))
        #expect(UUID(uuidString: String(partialTree.dropFirst(".Tree.grove-partial-".count))) != nil)
        try #require(listings[1].count == 2)
        #expect(listings[1][0].hasPrefix(".notes.md.grove-partial-"))
        #expect(listings[1][1] == "Tree")
        #expect(box.names(in: dest) == ["Tree", "notes.md"])
    }

    @Test func cancelInTheMiddleOfATreeLeavesNothingOfItAndKeepsWhatWasDone() async throws {
        let first = try box.makeFile("src/first.txt", "first")
        for index in 0..<10 { try box.makeFile("src/Tree/file-\(index).txt", "file \(index)") }
        let tree = box.path("src/Tree")
        let last = try box.makeFile("src/last.txt", "last")
        let copied = Locked(0)
        let runner = watchedRunner { stage, runner in
            // The first file is first.txt; the fourth is the third of the tree.
            if case .fileCopied = stage, copied.change({ $0 += 1; return $0 }) == 4 {
                Self.cancelAndWait(runner)
            }
        }

        let outcome = await box.run(.copy(items: [first, tree, last], to: dest), on: runner)

        #expect(outcome == Outcome(
            changes: [.created(dest.appendingPathComponent("first.txt"))], failures: [], cancelled: true,
            summary: "Copied 1 of 3 items (cancelled)"))
        // Stopped after the file in hand: the tree's other files were never read.
        #expect(copied.value == 4)
        #expect(box.names(in: dest) == ["first.txt"])
        #expect(box.names(in: tree).count == 10)

        // The cancel was that run's: the next one runs.
        let next = await box.run(.copy(items: [last], to: dest), on: runner)
        #expect(next.cancelled == false)
        #expect(box.names(in: dest) == ["first.txt", "last.txt"])
    }

    @Test func aCancelWithNothingRunningCancelsNothing() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        await runner.cancel()

        let outcome = await box.run(.copy(items: [file], to: dest), on: runner)

        #expect(outcome.cancelled == false)
        #expect(box.names(in: dest) == ["notes.md"])
    }

    @Test func cancelStopsAMoveBetweenItems() async throws {
        let files = try (0..<4).map { try box.makeFile("src/file-\($0).txt", "file \($0)") }
        let placed = Locked(0)
        let runner = watchedRunner { stage, runner in
            if case .placing = stage, placed.change({ $0 += 1; return $0 }) == 2 {
                Self.cancelAndWait(runner)
            }
        }

        let outcome = await box.run(.move(items: files, to: dest), on: runner)

        // The second was in hand when the cancel came: it is finished.
        #expect(outcome.cancelled)
        #expect(outcome.changes.count == 2)
        #expect(outcome.summary == "Moved 2 of 4 items (cancelled)")
        #expect(box.names(in: dest) == ["file-0.txt", "file-1.txt"])
        #expect(box.names(in: src) == ["file-2.txt", "file-3.txt"])
    }

    @Test func aFailureInTheMiddleOfATreeLeavesNothingOfIt() async throws {
        try box.makeFile("src/Tree/a.txt", "a")
        try box.makeFile("src/Tree/b/unreadable.txt", "secret")
        try box.makeFile("src/Tree/c.txt", "c")
        let tree = box.path("src/Tree")
        #expect(chmod(tree.appendingPathComponent("b/unreadable.txt").path, 0) == 0)

        let outcome = await box.run(.copy(items: [tree], to: dest), on: runner)

        #expect(outcome.changes == [])
        #expect(outcome.failures == [
            ItemFailure(url: tree, reason: "“b/unreadable.txt” in it: you don't have permission")
        ])
        #expect(outcome.cancelled == false)
        #expect(outcome.summary == "Nothing copied (1 failed)")
        #expect(box.names(in: dest) == [])
        #expect(box.names(in: tree) == ["a.txt", "b", "c.txt"])
    }

    @Test func oneUnreadableSourceAmongFiveFailsAloneAndTheRunGoesOn() async throws {
        let files = try (0..<5).map { try box.makeFile("src/file-\($0).txt", "file \($0)") }
        #expect(chmod(files[2].path, 0) == 0)

        let outcome = await box.run(.copy(items: files, to: dest), on: runner)

        #expect(outcome.changes == [0, 1, 3, 4].map { .created(dest.appendingPathComponent("file-\($0).txt")) })
        #expect(outcome.failures == [ItemFailure(url: files[2], reason: "you don't have permission")])
        #expect(outcome.cancelled == false)
        #expect(outcome.summary == "Copied 4 of 5 items (1 failed)")
        #expect(box.names(in: dest) == ["file-0.txt", "file-1.txt", "file-3.txt", "file-4.txt"])
        #expect(box.text(dest.appendingPathComponent("file-4.txt")) == "file 4")
    }

    @Test func aTargetFolderThatIsNotThereFailsEveryItemAndMakesNothing() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        let nowhere = box.path("nowhere")

        let copied = await box.run(.copy(items: [file], to: nowhere), on: runner)
        let moved = await box.run(.move(items: [file], to: nowhere), on: runner)

        #expect(copied.changes == [])
        let reason = "the folder “nowhere” is not there"
        #expect(copied.failures == [ItemFailure(url: file, reason: reason)])
        #expect(moved.changes == [])
        #expect(moved.failures == [ItemFailure(url: file, reason: reason)])
        #expect(!box.exists(nowhere))
        #expect(box.text(file) == "notes")
    }

    // MARK: A name that appears meanwhile (Review Focus 4)

    @Test func anItemThatAppearsAfterTheNamesWereLookedUpIsNotOverwritten() async throws {
        let file = try box.makeFile("src/notes.md", "mine")
        let other = try box.makeFile("src/other.md", "other")
        let operation = Operation.copy(items: [file, other], to: dest)
        #expect(await runner.existingNames(for: operation) == [])
        // Another program makes a file of that name before the run starts.
        let theirs = try box.makeFile("dest/notes.md", "theirs")

        // Even with "replace" as the answer: the question was never put for
        // this name, so it is not an answer to it.
        let outcome = await box.run(operation, on: runner, choice: .replace)

        #expect(outcome.changes == [.created(dest.appendingPathComponent("other.md"))])
        #expect(outcome.failures == [ItemFailure(url: file, reason: "an item with that name appeared")])
        #expect(outcome.summary == "Copied 1 of 2 items (1 failed)")
        #expect(box.text(theirs) == "theirs")
        #expect(box.text(file) == "mine")
        #expect(box.names(in: dest) == ["notes.md", "other.md"])
    }

    @Test func anItemThatAppearsJustBeforeTheLastRenameIsNotOverwritten() async throws {
        let file = try box.makeFile("src/notes.md", "mine")
        try box.makeFile("src/Tree/inside.txt", "mine")
        let tree = box.path("src/Tree")
        let box = box
        // The copy is whole under its partial name; then the name is taken.
        let runner = watchedRunner { stage, _ in
            guard case let .placing(target) = stage else { return }
            if target.lastPathComponent == "Tree" {
                _ = try? box.makeFile(at: target.appendingPathComponent("theirs.txt"), Data("theirs".utf8))
            } else if !target.lastPathComponent.contains(" 2") {
                _ = try? box.makeFile(at: target, Data("theirs".utf8))
            }
        }

        let copied = await box.run(.copy(items: [file, tree], to: dest), on: runner)

        #expect(copied.changes == [])
        #expect(copied.failures == [
            ItemFailure(url: file, reason: "an item with that name appeared"),
            ItemFailure(url: tree, reason: "an item with that name appeared"),
        ])
        #expect(box.text(dest.appendingPathComponent("notes.md")) == "theirs")
        #expect(box.names(in: dest.appendingPathComponent("Tree")) == ["theirs.txt"])
        #expect(box.names(in: dest) == ["Tree", "notes.md"])

        // A move, a rename and a duplicate end with the same kind of rename.
        let elsewhere = try box.makeFolder("elsewhere")
        let moved = await box.run(.move(items: [file], to: elsewhere), on: runner)
        #expect(moved.changes == [])
        #expect(moved.failures == [ItemFailure(url: file, reason: "an item with that name appeared")])
        #expect(box.text(elsewhere.appendingPathComponent("notes.md")) == "theirs")
        #expect(box.text(file) == "mine")

        let renamed = await box.run(.rename(item: file, to: "ideas.md"), on: runner)
        #expect(renamed.changes == [])
        #expect(renamed.failures == [ItemFailure(url: file, reason: "an item with that name appeared")])
        #expect(box.text(box.path("src/ideas.md")) == "theirs")
        #expect(box.text(file) == "mine")

        // "Keep both" and a duplicate want any free name: they take the next.
        let duplicated = await box.run(.duplicate(items: [file]), on: runner)
        #expect(duplicated.changes == [.created(box.path("src/notes copy 2.md"))])
        #expect(box.text(box.path("src/notes copy.md")) == "theirs")
        #expect(box.text(box.path("src/notes copy 2.md")) == "mine")
        #expect(box.partials(in: src) == [])
        #expect(box.partials(in: dest) == [])
    }

    @Test func anItemThatAppearsWhereOneWasReplacedIsNotOverwritten() async throws {
        let file = try box.makeFile("src/notes.md", "mine")
        let old = try box.makeFile("dest/notes.md", "old")
        let box = box
        // The old one is in the Trash; then another program takes the name.
        let runner = watchedRunner { stage, _ in
            if case let .placing(target) = stage { _ = try? box.makeFile(at: target, Data("theirs".utf8)) }
        }
        let operation = Operation.copy(items: [file], to: dest)
        #expect(await runner.existingNames(for: operation) == [old])

        let outcome = await box.run(operation, on: runner, choice: .replace)

        // The old one can't have its name back either: it is taken.
        #expect(outcome.failures == [
            ItemFailure(
                url: file,
                reason: "an item with that name appeared; “notes.md”, which it was to replace, is in the Trash")
        ])
        // What was done is said, so that it can be undone: the old one is in the Trash.
        try #require(outcome.changes.count == 1)
        guard case let .trashed(original, inTrash) = outcome.changes[0] else {
            Issue.record("not put in the Trash: \(outcome.changes)")
            return
        }
        #expect(original == old)
        #expect(box.text(inTrash) == "old")
        #expect(box.text(old) == "theirs")
        #expect(box.names(in: dest) == ["notes.md"])
    }

    // MARK: Links (Review Focus 3)

    @Test func aLinkIsCopiedAsALinkNotFollowed() async throws {
        let folder = try box.makeFolder("src/Folder")
        try box.makeFile("src/Folder/inside.txt", "inside")
        let toFolder = box.path("src/to-folder")
        try box.files.createSymbolicLink(atPath: toFolder.path, withDestinationPath: "Folder")
        let toNothing = box.path("src/to-nothing")
        try box.files.createSymbolicLink(atPath: toNothing.path, withDestinationPath: "/nowhere/at/all")
        // And one inside a tree, pointing out of it.
        try box.files.createSymbolicLink(
            atPath: folder.appendingPathComponent("up").path, withDestinationPath: "../Folder")

        let outcome = await box.run(.copy(items: [toFolder, toNothing, folder], to: dest), on: runner)

        #expect(outcome.failures == [])
        #expect(outcome.changes.count == 3)
        let files = box.files
        #expect(try files.destinationOfSymbolicLink(atPath: dest.appendingPathComponent("to-folder").path) == "Folder")
        #expect(
            try files.destinationOfSymbolicLink(atPath: dest.appendingPathComponent("to-nothing").path)
                == "/nowhere/at/all")
        #expect(try files.destinationOfSymbolicLink(atPath: dest.appendingPathComponent("Folder/up").path) == "../Folder")
        #expect(box.names(in: dest.appendingPathComponent("Folder")) == ["inside.txt", "up"])

        // Duplicated and moved as links too.
        let duplicated = await box.run(.duplicate(items: [toNothing]), on: runner)
        #expect(duplicated.changes == [.created(box.path("src/to-nothing copy"))])
        #expect(try files.destinationOfSymbolicLink(atPath: box.path("src/to-nothing copy").path) == "/nowhere/at/all")
        let elsewhere = try box.makeFolder("elsewhere")
        let moved = await box.run(.move(items: [toNothing], to: elsewhere), on: runner)
        #expect(moved.failures == [])
        #expect(
            try files.destinationOfSymbolicLink(atPath: elsewhere.appendingPathComponent("to-nothing").path)
                == "/nowhere/at/all")
    }

    // MARK: What is done about a name that exists

    @Test func existingNamesAreTheTargetsAlreadyThere() async throws {
        let notes = try box.makeFile("src/notes.md", "new")
        let ideas = try box.makeFile("src/ideas.md", "new")
        let docs = try box.makeFolder("src/docs")
        try box.makeFile("dest/notes.md", "old")
        try box.makeFolder("dest/docs")
        // A link that points nowhere holds its name all the same.
        let dangling = try box.makeFile("src/dangling", "new")
        try box.files.createSymbolicLink(atPath: dest.appendingPathComponent("dangling").path, withDestinationPath: "/nowhere")

        let items = [notes, ideas, docs, dangling]
        let expected = ["notes.md", "docs", "dangling"].map { dest.appendingPathComponent($0) }
        #expect(await runner.existingNames(for: .copy(items: items, to: dest)) == expected)
        #expect(await runner.existingNames(for: .move(items: items, to: dest)) == expected)
        #expect(await runner.existingNames(for: .duplicate(items: items)) == [])
        #expect(await runner.existingNames(for: .trash(items: items)) == [])
    }

    @Test func aNameThatDiffersOnlyByCaseOrUnicodeFormExistsWhereTheVolumeSaysSo() async throws {
        try box.makeFile("dest/Notes.md", "old")
        try box.makeFile("dest/caf\u{E9}.txt", "old")  // é as one character
        let notes = try box.makeFile("src/notes.md", "new")
        let cafe = try box.makeFile("src/cafe\u{301}.txt", "new")  // e and an accent
        // Asked of the volume itself: is "notes.md" there when "Notes.md" is?
        let sameByCase = box.exists(dest.appendingPathComponent("notes.md"))
        let sameByForm = box.exists(dest.appendingPathComponent("cafe\u{301}.txt"))

        let existing = await runner.existingNames(for: .copy(items: [notes, cafe], to: dest))

        var expected: [URL] = []
        if sameByCase { expected.append(dest.appendingPathComponent("notes.md")) }
        if sameByForm { expected.append(dest.appendingPathComponent("cafe\u{301}.txt")) }
        #expect(existing == expected)

        // "Keep both" then gives names that are free on this volume.
        let outcome = await box.run(.copy(items: [notes, cafe], to: dest), on: runner, choice: .keepBoth)
        #expect(outcome.failures == [])
        #expect(box.names(in: dest).count == 4)
        #expect(box.text(dest.appendingPathComponent("Notes.md")) == "old")
        #expect(box.text(dest.appendingPathComponent("caf\u{E9}.txt")) == "old")
        if sameByCase {
            #expect(outcome.changes.first == .created(dest.appendingPathComponent("notes 2.md")))
        }
    }

    @Test func skipLeavesBothAsTheyAre() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let other = try box.makeFile("src/other.md", "other")
        let old = try box.makeFile("dest/notes.md", "old")

        let outcome = await box.run(.move(items: [file, other], to: dest), on: runner, choice: .skip)

        #expect(outcome == Outcome(
            changes: [.moved(from: other, to: dest.appendingPathComponent("other.md"))], failures: [],
            cancelled: false, summary: "Moved 1 of 2 items (1 skipped)"))
        #expect(box.text(old) == "old")
        #expect(box.text(file) == "new")
    }

    /// ".tar.gz" is one extension: the number goes before it, as Finder's does.
    @Test func keepBothNumbersATarArchiveBeforeItsWholeExtension() async throws {
        let archive = try box.makeFile("src/archive.tar.gz", "new")
        try box.makeFile("dest/archive.tar.gz", "old")

        let copied = await box.run(.copy(items: [archive], to: dest), on: runner, choice: .keepBoth)

        #expect(copied.changes == [.created(dest.appendingPathComponent("archive 2.tar.gz"))])
        #expect(box.text(dest.appendingPathComponent("archive.tar.gz")) == "old")
        #expect(box.text(dest.appendingPathComponent("archive 2.tar.gz")) == "new")
        #expect(box.names(in: dest) == ["archive 2.tar.gz", "archive.tar.gz"])
    }

    @Test func keepBothTakesTheNextFreeNameAndKeepsTheExtension() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let folder = try box.makeFolder("src/docs")
        try box.makeFile("dest/notes.md", "old")
        try box.makeFile("dest/notes 2.md", "older")
        try box.makeFolder("dest/docs")

        let copied = await box.run(.copy(items: [file, folder], to: dest), on: runner, choice: .keepBoth)

        #expect(copied.changes == [
            .created(dest.appendingPathComponent("notes 3.md")), .created(dest.appendingPathComponent("docs 2")),
        ])
        #expect(copied.summary == "Copied 2 items to dest")
        #expect(box.text(dest.appendingPathComponent("notes.md")) == "old")
        #expect(box.text(dest.appendingPathComponent("notes 2.md")) == "older")
        #expect(box.text(dest.appendingPathComponent("notes 3.md")) == "new")

        let moved = await box.run(.move(items: [file], to: dest), on: runner, choice: .keepBoth)
        #expect(moved.changes == [.moved(from: file, to: dest.appendingPathComponent("notes 4.md"))])
        #expect(box.names(in: dest) == ["docs", "docs 2", "notes 2.md", "notes 3.md", "notes 4.md", "notes.md"])
    }

    @Test func replaceSendsTheOldOneToTheTrashAndAFolderIsReplacedWhole() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        try box.makeFile("src/docs/new.txt", "new")
        let folder = box.path("src/docs")
        let oldFile = try box.makeFile("dest/notes.md", "old")
        try box.makeFile("dest/docs/old.txt", "old")
        let oldFolder = dest.appendingPathComponent("docs")

        let outcome = await box.run(.copy(items: [file, folder], to: dest), on: runner, choice: .replace)

        #expect(outcome.failures == [])
        #expect(outcome.summary == "Copied 2 items to dest")
        try #require(outcome.changes.count == 4)
        guard case let .replaced(firstOriginal, fileInTrash) = outcome.changes[0],
            case let .replaced(secondOriginal, folderInTrash) = outcome.changes[2]
        else {
            Issue.record("the old ones were not replaced first: \(outcome.changes)")
            return
        }
        #expect(firstOriginal == oldFile)
        #expect(outcome.changes[1] == .created(oldFile))
        #expect(secondOriginal == oldFolder)
        #expect(outcome.changes[3] == .created(oldFolder))
        #expect(box.text(oldFile) == "new")
        // Not merged: what the old folder had is gone with it.
        #expect(box.names(in: oldFolder) == ["new.txt"])
        #expect(box.text(fileInTrash) == "old")
        #expect(box.names(in: folderInTrash) == ["old.txt"])
        #expect(!fileInTrash.path.hasPrefix(box.root.path))
    }

    @Test func aPlanOfAnswersIsWhatTheRunDoesAndOneForAllAnswersTheRest() async throws {
        let names = ["a.md", "b.md", "c.md", "d.md"]
        let items = try names.map { try box.makeFile("src/\($0)", "new") }
        let old = try names.map { try box.makeFile("dest/\($0)", "old") }
        let operation = Operation.copy(items: items, to: dest)

        // As the prompt would: one question a name, until one is for all.
        let existing = await runner.existingNames(for: operation)
        #expect(existing == old)
        var answers = ConflictPlan()
        answers.answer(.replace, for: existing[0], applyToAll: false)
        answers.answer(.keepBoth, for: existing[1], applyToAll: false)
        answers.answer(.skip, for: existing[2], applyToAll: true)
        let plan = answers

        let outcome = await runner.run(
            operation,
            resolve: { url in
                if let choice = plan.choice(for: url) { return choice }
                Issue.record("no answer about \(url.lastPathComponent)")
                return .skip
            },
            progress: { _ in })
        for case let .replaced(_, inTrash) in outcome.changes { box.inTrash.change { $0.append(inTrash) } }

        #expect(outcome.failures == [])
        #expect(outcome.summary == "Copied 2 of 4 items (2 skipped)")
        try #require(outcome.changes.count == 3)
        // Replaced: the old one is in the Trash, whole.
        guard case let .replaced(original, inTrash) = outcome.changes[0] else {
            Issue.record("the first was not replaced: \(outcome.changes)")
            return
        }
        #expect(original == old[0])
        #expect(box.text(inTrash) == "old")
        #expect(outcome.changes[1] == .created(old[0]))
        #expect(box.text(old[0]) == "new")
        // Both kept.
        #expect(outcome.changes[2] == .created(dest.appendingPathComponent("b 2.md")))
        #expect(box.text(old[1]) == "old")
        #expect(box.text(dest.appendingPathComponent("b 2.md")) == "new")
        // Skipped, the one asked about and the one after it: as they were,
        // and no change tells of them.
        #expect(box.text(old[2]) == "old")
        #expect(box.text(old[3]) == "old")
        #expect(box.names(in: dest) == ["a.md", "b 2.md", "b.md", "c.md", "d.md"])
        #expect(box.names(in: src) == names)
    }

    @Test func aMoveThatReplacesIsARenameAfterTheOldOneWentToTheTrash() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let number = try #require(box.inode(file))
        let old = try box.makeFile("dest/notes.md", "old")

        let outcome = await box.run(.move(items: [file], to: dest), on: runner, choice: .replace)

        try #require(outcome.changes.count == 2)
        guard case let .replaced(original, inTrash) = outcome.changes[0] else {
            Issue.record("the old one was not replaced first: \(outcome.changes)")
            return
        }
        #expect(original == old)
        #expect(outcome.changes[1] == .moved(from: file, to: old))
        #expect(box.text(inTrash) == "old")
        #expect(box.inode(old) == number)
        #expect(box.names(in: src) == [])
    }

    @Test func replacingALinkSendsTheLinkToTheTrashNotWhatItPointsAt() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let precious = try box.makeFile("precious/notes.md", "precious")
        try box.makeFile("precious-folder/inside.txt", "precious")
        let link = dest.appendingPathComponent("notes.md")
        try box.files.createSymbolicLink(at: link, withDestinationURL: precious)
        let folder = try box.makeFolder("src/docs")
        let folderLink = dest.appendingPathComponent("docs")
        try box.files.createSymbolicLink(at: folderLink, withDestinationURL: box.path("precious-folder"))

        let outcome = await box.run(.copy(items: [file, folder], to: dest), on: runner, choice: .replace)

        #expect(outcome.failures == [])
        #expect(outcome.changes.count == 4)
        #expect(box.text(link) == "new")
        #expect(box.names(in: dest.appendingPathComponent("docs")) == [])
        #expect(box.mode(dest.appendingPathComponent("docs")) != nil)
        #expect(box.text(precious) == "precious")
        #expect(box.names(in: box.path("precious-folder")) == ["inside.txt"])
        // What is in the Trash are the two links.
        for change in outcome.changes {
            if case let .replaced(_, inTrash) = change {
                #expect((try? box.files.destinationOfSymbolicLink(atPath: inTrash.path)) != nil)
            }
        }
    }

    @Test func anItemNeverReplacesItselfOrTheFolderItIsIn() async throws {
        let file = try box.makeFile("src/notes.md", "notes")
        // Copied to the folder it is in, with "replace" as the answer.
        let onto = await box.run(.copy(items: [file], to: src), on: runner, choice: .replace)
        #expect(onto.changes == [])
        #expect(onto.failures == [ItemFailure(url: file, reason: "it can't replace itself")])
        #expect(box.text(file) == "notes")

        // "Keep both" makes the copy beside it.
        let beside = await box.run(.copy(items: [file], to: src), on: runner, choice: .keepBoth)
        #expect(beside.changes == [.created(box.path("src/notes 2.md"))])

        // src/docs/src would replace the folder src it is in.
        let inner = try box.makeFolder("src/docs/src")
        let around = await box.run(.copy(items: [inner], to: box.root), on: runner, choice: .replace)
        #expect(around.changes == [])
        #expect(around.failures == [
            ItemFailure(url: inner, reason: "it is inside the item it would replace")
        ])
        #expect(box.exists(inner))
        #expect(box.text(file) == "notes")
    }

    @Test func twoItemsOfOneNameDoNotOverwriteEachOther() async throws {
        let first = try box.makeFile("src/a/notes.md", "first")
        let second = try box.makeFile("src/b/notes.md", "second")

        let outcome = await box.run(.copy(items: [first, second], to: dest), on: runner, choice: .replace)

        #expect(outcome.changes == [.created(dest.appendingPathComponent("notes.md"))])
        #expect(outcome.failures == [ItemFailure(url: second, reason: "an item with that name appeared")])
        #expect(box.text(dest.appendingPathComponent("notes.md")) == "first")

        // With an item of that name there before, and "replace" as the
        // answer: the answer is for the first; the second doesn't replace
        // the first one's arrival.
        let other = try box.makeFolder("other")
        let old = try box.makeFile("other/notes.md", "old")
        let operation = Operation.copy(items: [first, second], to: other)
        #expect(await runner.existingNames(for: operation) == [old, old])
        let asked = Locked(0)
        let replaced = await runner.run(
            operation, resolve: { _ in asked.change { $0 += 1 }; return .replace }, progress: { _ in })
        for case let .replaced(_, inTrash) in replaced.changes { box.inTrash.change { $0.append(inTrash) } }
        #expect(asked.value == 1)
        #expect(replaced.changes.count == 2)
        #expect(replaced.changes.last == .created(old))
        #expect(replaced.failures == [
            ItemFailure(url: second, reason: "another item of this operation has that name, and the answer was for it")
        ])
        #expect(box.text(old) == "first")

        // With "skip" as the answer the second is skipped as the first
        // was: nothing appeared, and nothing is said to have.
        #expect(await runner.existingNames(for: operation) == [old, old])
        let skipped = await box.run(operation, on: runner, choice: .skip)
        #expect(skipped == Outcome(
            changes: [], failures: [], cancelled: false, summary: "Nothing copied (2 skipped)"))
        #expect(box.text(old) == "first")
    }

    @Test func aNameIsTheItemsOwnOnlyInItsFolderAndInOtherCapitals() async throws {
        // Another name for the same file (a hard link) is another item to a rename.
        let file = try box.makeFile("src/notes.md", "notes")
        let other = box.path("src/ideas.md")
        try box.files.linkItem(at: file, to: other)
        #expect(box.inode(file) == box.inode(other))

        #expect(await runner.existingNames(for: .rename(item: file, to: "ideas.md")) == [other])
        let outcome = await box.run(.rename(item: file, to: "ideas.md"), on: runner)

        #expect(outcome.changes == [])
        #expect(outcome.failures == [
            ItemFailure(url: file, reason: "an item named “ideas.md” is already there")
        ])
        #expect(box.names(in: src) == ["ideas.md", "notes.md"])

        #expect(OperationRunner.isSameName("notes.md", "Notes.MD"))
        #expect(OperationRunner.isSameName("caf\u{E9}", "CAFE\u{301}"))
        #expect(!OperationRunner.isSameName("notes.md", "ideas.md"))
        #expect(!OperationRunner.isSameName("notes.md", "notes.md "))
    }

    // MARK: A replace whose newcomer doesn't come

    @Test func aMoveThatCannotBeDoneDoesNotSendTheOldOneToTheTrash() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let old = try box.makeFile("dest/notes.md", "old")
        let number = try #require(box.inode(old))

        // A locked item can't be renamed.
        #expect(chflags(file.path, UInt32(UF_IMMUTABLE)) == 0)
        let locked = await box.run(.move(items: [file], to: dest), on: runner, choice: .replace)
        #expect(locked == Outcome(
            changes: [], failures: [ItemFailure(url: file, reason: "it is locked")], cancelled: false,
            summary: "Nothing moved (1 failed)"))
        #expect(box.inode(old) == number)
        #expect(chflags(file.path, 0) == 0)

        // Nor can one in a folder that can't be written to.
        #expect(chmod(src.path, 0o555) == 0)
        let closed = await box.run(.move(items: [file], to: dest), on: runner, choice: .replace)
        #expect(closed.changes == [])
        #expect(closed.failures == [ItemFailure(url: file, reason: "you don't have permission")])
        #expect(box.inode(old) == number)
        #expect(box.text(old) == "old")
        #expect(box.text(file) == "new")
    }

    @Test func theOldOneGetsItsNameBackWhenTheMoveFailsAfterAll() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let old = try box.makeFile("dest/notes.md", "old")
        let number = try #require(box.inode(old))
        // Nothing in the way when it was looked for; locked just before the
        // rename, when the old one is in the Trash already.
        let once = Locked(false)
        let runner = watchedRunner { stage, _ in
            guard case .placing = stage, !once.change({ was in defer { was = true }; return was }) else { return }
            chflags(file.path, UInt32(UF_IMMUTABLE))
        }

        let outcome = await box.run(.move(items: [file], to: dest), on: runner, choice: .replace)

        // Nothing changed, in the end: the old one is where it was, the same item.
        #expect(outcome == Outcome(
            changes: [], failures: [ItemFailure(url: file, reason: "you don't have permission")],
            cancelled: false, summary: "Nothing moved (1 failed)"))
        #expect(box.inode(old) == number)
        #expect(box.text(old) == "old")
        #expect(box.text(file) == "new")
        #expect(box.names(in: dest) == ["notes.md"])
    }

    /// A file manager whose Trash takes nothing.
    private final class NoTrash: FileManager, @unchecked Sendable {
        override func trashItem(
            at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
        ) throws {
            throw CocoaError(.featureUnsupported)
        }
    }

    @Test func whenTheOldOneCannotGoToTheTrashNothingIsReplaced() async throws {
        let file = try box.makeFile("src/notes.md", "new")
        let moving = try box.makeFile("src/other.md", "new")
        let old = try box.makeFile("dest/notes.md", "old")
        let alsoOld = try box.makeFile("dest/other.md", "old")
        let runner = OperationRunner(fileManager: NoTrash())
        let reason = { (name: String) in "“\(name)” could not be moved to the Trash: its disk has no Trash" }

        let copied = await box.run(.copy(items: [file], to: dest), on: runner, choice: .replace)
        #expect(copied.changes == [])
        #expect(copied.failures == [ItemFailure(url: file, reason: reason("notes.md"))])
        let moved = await box.run(.move(items: [moving], to: dest), on: runner, choice: .replace)
        #expect(moved.changes == [])
        #expect(moved.failures == [ItemFailure(url: moving, reason: reason("other.md"))])
        // Never removed another way: both old ones are there, and both new ones.
        #expect(box.text(old) == "old")
        #expect(box.text(alsoOld) == "old")
        #expect(box.text(file) == "new")
        #expect(box.text(moving) == "new")
        #expect(box.allNames(in: dest) == ["notes.md", "other.md"])

        // And an item that can't go to the Trash stays.
        let trashed = await box.run(.trash(items: [file]), on: runner)
        #expect(trashed.changes == [])
        #expect(trashed.failures == [ItemFailure(url: file, reason: "its disk has no Trash")])
        #expect(box.text(file) == "new")
    }

    // MARK: Cloud items, through Finder

    /// A file manager whose Trash refuses, as macOS refuses an app without
    /// the File Provider permission.
    private final class NoPermissionTrash: FileManager, @unchecked Sendable {
        override func trashItem(
            at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
        ) throws {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    /// Finder, as the tests have it: it records what it is asked about and
    /// gives `answer`. On success it moves the item to the answer's URL, as
    /// Finder moves it to the Trash.
    private final class FakeFinder: FinderTrash, @unchecked Sendable {
        let answer: Result<URL, FinderTrashError>
        let asked = Locked<[URL]>([])

        init(_ answer: Result<URL, FinderTrashError>) { self.answer = answer }

        func trash(_ url: URL) -> Result<URL, FinderTrashError> {
            asked.change { $0.append(url) }
            if case let .success(inTrash) = answer {
                try? FileManager.default.createDirectory(
                    at: inTrash.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.moveItem(at: url, to: inTrash)
            }
            return answer
        }
    }

    /// A home of the box's own, with an iCloud Drive folder in it.
    private func cloudHome() throws -> (home: URL, drive: URL) {
        let home = box.path("home")
        let drive = try box.makeFolder(at: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"))
        return (home, drive)
    }

    private func cloudRunner(_ finder: FakeFinder, home: URL) -> OperationRunner {
        OperationRunner(fileManager: NoPermissionTrash(), finder: finder, home: home)
    }

    @Test func cloudItemGoesToTheTrashThroughFinder() async throws {
        let (home, drive) = try cloudHome()
        let file = try box.makeFile(at: drive.appendingPathComponent("notes.md"), Data("cloud".utf8))
        let trashURL = box.path("Trash/notes.md")
        let finder = FakeFinder(.success(trashURL))

        let outcome = await box.run(.trash(items: [file]), on: cloudRunner(finder, home: home))

        #expect(outcome.changes == [.trashed(original: file, inTrash: trashURL)])
        #expect(outcome.failures == [])
        #expect(finder.asked.value == [file])
        #expect(box.text(trashURL) == "cloud")
    }

    @Test func localPermissionErrorDoesNotAskFinder() async throws {
        let (home, _) = try cloudHome()
        let file = try box.makeFile("src/notes.md", "local")
        let finder = FakeFinder(.success(box.path("Trash/notes.md")))

        let outcome = await box.run(.trash(items: [file]), on: cloudRunner(finder, home: home))

        #expect(outcome.changes == [])
        #expect(outcome.failures == [ItemFailure(url: file, reason: "you don't have permission")])
        #expect(finder.asked.value == [])
        #expect(box.text(file) == "local")
    }

    /// The reason a cloud item fails with, when Finder answers `answer`.
    private func cloudFailure(_ answer: FinderTrashError) async throws -> [ItemFailure] {
        let (home, drive) = try cloudHome()
        let file = try box.makeFile(at: drive.appendingPathComponent("notes.md"), Data("cloud".utf8))
        let finder = FakeFinder(.failure(answer))
        let outcome = await box.run(.trash(items: [file]), on: cloudRunner(finder, home: home))
        #expect(outcome.changes == [])
        #expect(finder.asked.value == [file])
        #expect(outcome.failures.map(\.url) == [file])
        #expect(box.text(file) == "cloud")
        return outcome.failures
    }

    @Test func finderNotAllowedSaysSo() async throws {
        let failures = try await cloudFailure(.notAllowed)
        #expect(failures.map(\.reason) == [CloudTrash.notAllowed])
    }

    @Test func finderOtherErrorSaysSo() async throws {
        let failures = try await cloudFailure(.failed("boom"))
        #expect(failures.map(\.reason) == [CloudTrash.finderFailed("boom")])
    }

    @Test func finderUnknownLocation() async throws {
        let failures = try await cloudFailure(.unknownLocation)
        #expect(failures.map(\.reason) == ["it is in the Trash, but where there is not known"])
    }

    @Test func replaceInCloudFolderUsesFinder() async throws {
        let (home, drive) = try cloudHome()
        let file = try box.makeFile("src/notes.md", "new")
        let old = try box.makeFile(at: drive.appendingPathComponent("notes.md"), Data("old".utf8))
        let trashURL = box.path("Trash/notes.md")
        let finder = FakeFinder(.success(trashURL))

        let outcome = await box.run(
            .copy(items: [file], to: drive), on: cloudRunner(finder, home: home), choice: .replace)

        #expect(outcome.failures == [])
        #expect(outcome.changes == [.replaced(original: old, inTrash: trashURL), .created(old)])
        #expect(finder.asked.value == [old])
        #expect(box.text(trashURL) == "old")
        #expect(box.text(old) == "new")
        #expect(box.text(file) == "new")
    }

    // MARK: The source of a move to another volume, and the app's partial copies

    /// A tree and a copy of it, made as a move to another volume makes
    /// it, and the copier that made it.
    private func treeAndCopy(_ name: String = "Tree") throws -> (source: URL, copy: URL, copier: TreeCopier) {
        try box.makeFile("src/\(name)/one.txt", "one")
        try box.makeFile("src/\(name)/a/two.txt", "two")
        try box.makeFolder("src/\(name)/a/empty")
        try box.files.createSymbolicLink(atPath: box.path("src/\(name)/link").path, withDestinationPath: "a/two.txt")
        let source = box.path("src/\(name)")
        let copy = dest.appendingPathComponent(name)
        let copier = TreeCopier(flag: CancelFlag(), reporter: Reporter(send: { _ in }, watching: nil), watching: nil)
        try copier.copy(source.path, to: copy.path, remembering: true)
        return (source, copy, copier)
    }

    @Test func aCopyIsWholeOnlyWhenEveryItemOfTheSourceIsInItAndTheSame() async throws {
        /// Whether a fresh copy still counts as whole after `change`.
        var number = 0
        func wholeAfter(_ change: (_ source: URL, _ copy: URL) throws -> Void) throws -> Bool {
            number += 1
            let (source, copy, copier) = try treeAndCopy("Tree-\(number)")
            try change(source, copy)
            return copier.isWhole(copy.path, of: source.path)
        }
        let box = box

        #expect(try wholeAfter { _, _ in })
        // A file of the source the copy doesn't have.
        #expect(try !wholeAfter { source, _ in
            try box.makeFile(at: source.appendingPathComponent("a/extra.txt"), Data("extra".utf8))
        })
        // A file written to since: of another length at the same time; of
        // the same length a second later, and a thousandth of one.
        #expect(try !wholeAfter { source, _ in
            let two = source.appendingPathComponent("a/two.txt")
            let date = try #require(box.modified(two))
            try Data("two and more".utf8).write(to: two)
            try box.setModified(date, two)
        })
        for later in [1, 0.001] {
            #expect(try !wholeAfter { source, _ in
                let two = source.appendingPathComponent("a/two.txt")
                let date = try #require(box.modified(two))
                try Data("owt".utf8).write(to: two)
                try box.setModified(date + later, two)
            })
        }
        // The copy cut short.
        #expect(try !wholeAfter { _, copy in
            try Data("o".utf8).write(to: copy.appendingPathComponent("one.txt"))
        })
        // A link to another place; a file where a folder was; one item more in the copy.
        #expect(try !wholeAfter { _, copy in
            let link = copy.appendingPathComponent("link")
            try box.files.removeItem(at: link)
            try box.files.createSymbolicLink(atPath: link.path, withDestinationPath: "one.txt")
        })
        #expect(try !wholeAfter { _, copy in
            try box.files.removeItem(at: copy.appendingPathComponent("a/empty"))
            try box.makeFile(at: copy.appendingPathComponent("a/empty"), Data())
        })
        #expect(try !wholeAfter { _, copy in
            try box.makeFile(at: copy.appendingPathComponent("a/empty/more.txt"), Data())
        })
        // A copy the copier didn't make: it knows nothing of how the files were.
        let (source, copy, _) = try treeAndCopy("Tree-other")
        let (_, _, another) = try treeAndCopy("Tree-another")
        #expect(!another.isWhole(copy.path, of: source.path))
    }

    @Test func theSourceIsRemovedItemByItemAndWhatIsNotInTheCopyStays() async throws {
        let (source, copy, copier) = try treeAndCopy()
        // Came after the copy was made, and one changed since.
        let late = try box.makeFile("src/Tree/a/empty/late.txt", "late")
        let one = source.appendingPathComponent("one.txt")
        try Data("one, changed".utf8).write(to: one)

        #expect(!copier.removeSource(source.path, copiedTo: copy.path))

        // Neither is removed, nor the folders they are in; nothing of the copy is touched.
        #expect(box.text(late) == "late")
        #expect(box.text(one) == "one, changed")
        #expect(box.text(copy.appendingPathComponent("one.txt")) == "one")
        #expect(box.text(copy.appendingPathComponent("a/two.txt")) == "two")

        // A source as its copy has it goes, all of it, and only it.
        let (whole, itsCopy, itsCopier) = try treeAndCopy("Whole")
        #expect(itsCopier.removeSource(whole.path, copiedTo: itsCopy.path))
        #expect(!box.exists(whole))
        #expect(box.names(in: src) == ["Tree"])
        #expect(box.names(in: itsCopy) == ["a", "link", "one.txt"])
        // An item of the source that went by itself meanwhile is no reason to stop.
        let (third, thirdCopy, thirdCopier) = try treeAndCopy("Third")
        try box.files.removeItem(at: third.appendingPathComponent("one.txt"))
        #expect(thirdCopier.removeSource(third.path, copiedTo: thirdCopy.path))
        #expect(!box.exists(third))
    }

    @Test func onlyAPartialCopyIsEverRemovedDirectly() async throws {
        try box.makeFile("dest/Tree/inside.txt", "the user's")
        let users = dest.appendingPathComponent("Tree")
        TreeCopier.removeTemporary(users.path)
        #expect(box.text(users.appendingPathComponent("inside.txt")) == "the user's")

        // A partial copy goes whole, a locked file and a read-only folder in it too.
        let partial = dest.appendingPathComponent(".Tree.grove-partial-\(UUID().uuidString)")
        let locked = try box.makeFile(at: partial.appendingPathComponent("closed/locked.txt"), Data("x".utf8))
        #expect(chflags(locked.path, UInt32(UF_IMMUTABLE)) == 0)
        #expect(chmod(partial.appendingPathComponent("closed").path, 0o555) == 0)
        TreeCopier.removeTemporary(partial.path)
        #expect(!box.exists(partial))
        #expect(box.names(in: dest) == ["Tree"])
    }

    // MARK: One after the other

    @Test func runsStartedTogetherAreDoneOneAfterTheOther() async throws {
        let files = try (0..<6).map { try box.makeFile("src/file-\($0).txt", "file \($0)") }
        let inHand = Locked(0)
        let most = Locked(0)
        let runner = watchedRunner { stage, _ in
            guard case .placing = stage else { return }
            let now = inHand.change { $0 += 1; return $0 }
            most.change { $0 = max($0, now) }
            usleep(20_000)
            inHand.change { $0 -= 1 }
        }
        let box = box
        let dest = dest

        let outcomes = await withTaskGroup(of: Outcome.self) { group in
            for file in files {
                group.addTask { await box.run(.copy(items: [file], to: dest), on: runner) }
            }
            var all: [Outcome] = []
            for await outcome in group { all.append(outcome) }
            return all
        }

        #expect(outcomes.count == 6)
        #expect(outcomes.allSatisfy { $0.failures.isEmpty && $0.changes.count == 1 })
        #expect(most.value == 1)
        #expect(box.names(in: dest).count == 6)
    }

    // MARK: Progress

    @Test func progressOfACopyIsInBytesAndEndsAtTheTotal() async throws {
        let small = try box.makeFile(at: box.path("src/small.bin"), Data(repeating: 1, count: 1_000))
        try box.makeFile(at: box.path("src/Tree/a.bin"), Data(repeating: 2, count: 20_000))
        try box.makeFile(at: box.path("src/Tree/deep/b.bin"), Data(repeating: 3, count: 300_000))
        let tree = box.path("src/Tree")
        let reports = Locked<[Progress]>([])

        let outcome = await box.run(
            .copy(items: [small, tree], to: dest), on: runner,
            progress: { progress in reports.change { $0.append(progress) } })

        #expect(outcome.failures == [])
        let all = reports.value
        #expect(all.first == Progress(done: 0, total: 321_000, itemsDone: 0, itemsTotal: 2))
        #expect(all.last == Progress(done: 321_000, total: 321_000, itemsDone: 2, itemsTotal: 2))
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.done <= $1.done })
    }

    @Test func progressOfTheOthersIsInItems() async throws {
        let files = try (0..<3).map { try box.makeFile("src/file-\($0).txt", "file \($0)") }
        let reports = Locked<[Progress]>([])
        let collect: @Sendable (Progress) -> Void = { progress in reports.change { $0.append(progress) } }

        _ = await box.run(.move(items: files, to: dest), on: runner, progress: collect)
        #expect(reports.value.first == Progress(done: 0, total: 3, itemsDone: 0, itemsTotal: 3))
        #expect(reports.value.last == Progress(done: 3, total: 3, itemsDone: 3, itemsTotal: 3))

        reports.value = []
        let moved = files.map { dest.appendingPathComponent($0.lastPathComponent) }
        _ = await box.run(.trash(items: moved), on: runner, progress: collect)
        #expect(reports.value.first == Progress(done: 0, total: 3, itemsDone: 0, itemsTotal: 3))
        #expect(reports.value.last == Progress(done: 3, total: 3, itemsDone: 3, itemsTotal: 3))

        reports.value = []
        _ = await box.run(.newFolder(in: dest, name: "Projects"), on: runner, progress: collect)
        #expect(reports.value.last == Progress(done: 1, total: 1, itemsDone: 1, itemsTotal: 1))
    }

    @Test func progressIsReportedAtMostTenTimesASecondAndOnceAtTheEnd() async throws {
        // Enough small files for the copy to take a few tenths of a second.
        let tree = try box.makeFolder("src/Tree")
        for folder in 0..<20 {
            let directory = try box.makeFolder(at: tree.appendingPathComponent("folder-\(folder)"))
            for index in 0..<200 {
                try box.makeFile(at: directory.appendingPathComponent("file-\(index).txt"), Data("12345".utf8))
            }
        }
        let times = Locked<[(at: ContinuousClock.Instant, progress: Progress)]>([])
        let started = ContinuousClock.now

        let outcome = await box.run(
            .copy(items: [tree], to: dest), on: runner,
            progress: { progress in times.change { $0.append((ContinuousClock.now, progress)) } })

        let took = ContinuousClock.now - started
        #expect(outcome.failures == [])
        let all = times.value
        try #require(all.count >= 2)
        #expect(all.last?.progress == Progress(done: 20_000, total: 20_000, itemsDone: 1, itemsTotal: 1))
        // Every report but the last comes a tenth of a second after the one
        // before (a little less as seen from here: the clock is read twice).
        let limited = all.dropLast()
        for (earlier, later) in zip(limited, limited.dropFirst()) {
            #expect(later.at - earlier.at >= .milliseconds(90))
        }
        #expect(Double(limited.count) <= took / .milliseconds(100) + 1)
        // 4,000 files gave no more than these few reports.
        #expect(all.count < 100)
    }
}

// MARK: - Across volumes

/// Moves and copies between two small disk images, attached under the
/// test's own temporary folder and out of Finder's sight, and detached when
/// the test ends, passed or failed. A test is skipped, with the reason, on
/// a Mac where `hdiutil` can't make or attach an image.
@Suite(.serialized) final class OperationRunnerVolumeTests {
    private let box: Sandbox
    private let attached = Locked<[URL]>([])
    private let megabyte = 1_000_000

    init() throws {
        box = try Sandbox("volumes")
    }

    deinit {
        // The last attached first: one may be attached inside another.
        for volume in attached.value.reversed() {
            _ = try? Self.hdiutil(["detach", volume.path, "-force"])
        }
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

    /// A new, empty volume of 20 MB, attached at a folder under the test's
    /// own, or at the folder `at`.
    private func volume(_ name: String, format: String = "APFS", at folder: URL? = nil) throws -> URL {
        let image = box.path("\(name).dmg")
        let mountPoint = folder ?? box.path("mnt-\(name)")
        do {
            try Self.hdiutil(["create", "-size", "20m", "-fs", format, "-volname", name, image.path])
            try box.makeFolder(at: mountPoint)
            try Self.hdiutil(["attach", image.path, "-mountpoint", mountPoint.path, "-nobrowse"])
        } catch {
            try Test.cancel("skipped: no disk image to test with (\(error))")
        }
        attached.change { $0.append(mountPoint) }
        return mountPoint
    }

    private func bytes(_ megabytes: Int, of byte: UInt8) -> Data {
        Data(repeating: byte, count: megabytes * megabyte)
    }

    @Test func aMoveToAnotherVolumeCopiesThenRemovesTheSourceOnlyWhenTheCopyIsWhole() async throws {
        let a = try volume("GroveA")
        let b = try volume("GroveB")
        let tree = try box.makeFolder(at: a.appendingPathComponent("Tree"))
        try box.makeFile(at: tree.appendingPathComponent("one.bin"), bytes(2, of: 1))
        let two = try box.makeFile(at: tree.appendingPathComponent("a/two.txt"), Data("two".utf8))
        try box.makeFolder(at: tree.appendingPathComponent("a/empty"))
        try box.files.createSymbolicLink(atPath: tree.appendingPathComponent("link").path, withDestinationPath: "a/two.txt")
        box.setAttribute("com.projectgrove.test", "kept", on: two)
        try box.setTags(["Grove Test"], on: two)
        #expect(chmod(two.path, 0o640) == 0)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try box.setModified(date, two)
        let file = try box.makeFile(at: a.appendingPathComponent("notes.md"), Data("notes".utf8))

        // At every stage up to the item getting its name, the source is whole.
        let box = box
        let sourceWhole = Locked<[Bool]>([])
        let dataSeen = Locked<[Int64]>([])
        let runner = OperationRunner(watching: { stage in
            switch stage {
            case .fileCopied, .placing:
                sourceWhole.change {
                    $0.append(
                        box.names(in: tree) == ["a", "link", "one.bin"]
                            && box.names(in: tree.appendingPathComponent("a")) == ["empty", "two.txt"]
                            && box.text(two) == "two")
                }
            case let .copying(bytes):
                dataSeen.change { $0.append(bytes) }
            case .placeholder:
                break
            }
        })
        let reports = Locked<[Progress]>([])

        let outcome = await box.run(
            .move(items: [tree, file], to: b), on: runner,
            progress: { progress in reports.change { $0.append(progress) } })

        let moved = b.appendingPathComponent("Tree")
        #expect(outcome == Outcome(
            changes: [.moved(from: tree, to: moved), .moved(from: file, to: b.appendingPathComponent("notes.md"))],
            failures: [], cancelled: false, summary: "Moved 2 items to mnt-GroveB"))
        #expect(sourceWhole.value.count >= 4)
        #expect(sourceWhole.value.prefix(4).allSatisfy { $0 })
        // Then, and only then, the source went.
        #expect(!box.exists(tree))
        #expect(!box.exists(file))
        #expect(box.names(in: a).filter { !$0.hasPrefix(".") } == [])
        // And the copy is all of it.
        #expect(box.names(in: moved) == ["a", "link", "one.bin"])
        #expect(box.names(in: moved.appendingPathComponent("a")) == ["empty", "two.txt"])
        #expect(try Data(contentsOf: moved.appendingPathComponent("one.bin")) == bytes(2, of: 1))
        let movedTwo = moved.appendingPathComponent("a/two.txt")
        #expect(box.text(movedTwo) == "two")
        #expect(box.attribute("com.projectgrove.test", of: movedTwo) == "kept")
        #expect(box.tags(of: movedTwo) == ["Grove Test"])
        #expect(box.mode(movedTwo) == 0o640)
        #expect(box.modified(movedTwo) == date)
        #expect(try box.files.destinationOfSymbolicLink(atPath: moved.appendingPathComponent("link").path) == "a/two.txt")
        #expect(box.partials(in: b) == [])
        // Bytes were copied, so the progress is in bytes, and the copy of
        // the large file told how far it was.
        #expect(reports.value.last == Progress(done: 2_000_008, total: 2_000_008, itemsDone: 2, itemsTotal: 2))
        #expect(dataSeen.value.contains { $0 > 0 && $0 <= 2_000_000 })
    }

    @Test func aSourceWrittenToWhileItWasCopiedIsLeftWhereItIs() async throws {
        let a = try volume("GroveA")
        let b = try volume("GroveB")
        let tree = try box.makeFolder(at: a.appendingPathComponent("Tree"))
        try box.makeFile(at: tree.appendingPathComponent("one.txt"), Data("one".utf8))
        let growing = try box.makeFile(at: tree.appendingPathComponent("growing.txt"), Data("first".utf8))
        // The copy is made; before it has its name, the source gets more.
        let runner = OperationRunner(watching: { stage in
            if case .placing = stage { try? Data("first and more".utf8).write(to: growing) }
        })

        let outcome = await box.run(.move(items: [tree], to: b), on: runner)

        let copy = b.appendingPathComponent("Tree")
        // The copy stays and is told, so that it can be undone; the source
        // is whole, with what was written to it.
        #expect(outcome.changes == [.created(copy)])
        #expect(outcome.failures == [
            ItemFailure(
                url: tree,
                reason: "it changed while it was copied: the copy is there, and it was left where it is")
        ])
        #expect(outcome.summary == "Nothing moved (1 failed)")
        #expect(box.names(in: tree) == ["growing.txt", "one.txt"])
        #expect(box.text(growing) == "first and more")
        #expect(box.text(copy.appendingPathComponent("growing.txt")) == "first")
    }

    @Test func aMoveThatFailsOnTheWayLeavesTheSourceWholeAndNothingAtTheTarget() async throws {
        let a = try volume("GroveA")
        let b = try volume("GroveB")
        let tree = try box.makeFolder(at: a.appendingPathComponent("Tree"))
        try box.makeFile(at: tree.appendingPathComponent("a.txt"), Data("a".utf8))
        let unreadable = try box.makeFile(at: tree.appendingPathComponent("b/unreadable.txt"), Data("secret".utf8))
        try box.makeFile(at: tree.appendingPathComponent("c.txt"), Data("c".utf8))
        #expect(chmod(unreadable.path, 0) == 0)

        let outcome = await box.run(.move(items: [tree], to: b), on: OperationRunner())

        #expect(outcome.changes == [])
        #expect(outcome.failures == [
            ItemFailure(url: tree, reason: "“b/unreadable.txt” in it: you don't have permission")
        ])
        #expect(outcome.summary == "Nothing moved (1 failed)")
        #expect(box.names(in: tree) == ["a.txt", "b", "c.txt"])
        #expect(box.text(tree.appendingPathComponent("a.txt")) == "a")
        #expect(box.text(tree.appendingPathComponent("c.txt")) == "c")
        #expect(box.names(in: tree.appendingPathComponent("b")) == ["unreadable.txt"])
        #expect(box.names(in: b).filter { !$0.hasPrefix(".") || $0.contains("grove-partial") } == [])
    }

    @Test func aCancelledMoveLeavesTheSourceWholeAndNothingAtTheTarget() async throws {
        let a = try volume("GroveA")
        let b = try volume("GroveB")
        let tree = try box.makeFolder(at: a.appendingPathComponent("Tree"))
        for index in 0..<6 {
            try box.makeFile(at: tree.appendingPathComponent("file-\(index).txt"), Data("file \(index)".utf8))
        }
        let itself = Locked<OperationRunner?>(nil)
        let copied = Locked(0)
        let runner = OperationRunner(watching: { stage in
            guard case .fileCopied = stage, copied.change({ $0 += 1; return $0 }) == 3,
                let runner = itself.value
            else { return }
            let done = DispatchSemaphore(value: 0)
            Task {
                await runner.cancel()
                done.signal()
            }
            done.wait()
        })
        itself.value = runner

        let outcome = await box.run(.move(items: [tree], to: b), on: runner)

        #expect(outcome == Outcome(
            changes: [], failures: [], cancelled: true, summary: "Nothing moved (cancelled)"))
        #expect(box.names(in: tree).count == 6)
        #expect(box.names(in: b).filter { !$0.hasPrefix(".") || $0.contains("grove-partial") } == [])
    }

    @Test func aFullTargetStopsTheRunKeepsWhatWasCopiedAndNamesTheMissingRoom() async throws {
        let b = try volume("GroveB")
        // 30 MB for a volume of 20: on this Mac's own disk, as a copy; and
        // on another small volume, as a move.
        let files = try (0..<5).map {
            try box.makeFile(at: box.path("src/file-\($0).bin"), bytes(6, of: UInt8($0)))
        }

        let outcome = await box.run(.copy(items: files, to: b), on: OperationRunner())

        let copied = outcome.changes.count
        #expect(copied >= 1 && copied <= 3)
        #expect(outcome.changes == (0..<copied).map { .created(b.appendingPathComponent("file-\($0).bin")) })
        // The one that didn't fit failed; the ones after it were not tried.
        #expect(outcome.failures == [ItemFailure(url: files[copied], reason: "the disk is full")])
        #expect(outcome.cancelled == false)
        // What was copied stays, whole; of the one that didn't fit, nothing.
        #expect(box.names(in: b).filter { !$0.hasPrefix(".") || $0.contains("grove-partial") }
            == (0..<copied).map { "file-\($0).bin" })
        for index in 0..<copied {
            #expect(try Data(contentsOf: b.appendingPathComponent("file-\(index).bin")) == bytes(6, of: UInt8(index)))
        }
        let prefix = "Copied \(copied) of 5 items (not enough room on GroveB: "
        #expect(outcome.summary.hasPrefix(prefix))
        #expect(outcome.summary.hasSuffix(" MB more needed)"))
        // Between what the files left out need less the whole volume, and all they need.
        let figure = Double(outcome.summary.dropFirst(prefix.count).dropLast(" MB more needed)".count))
        let leftOut = Double(5 - copied) * 6
        #expect(try #require(figure) > leftOut - 20 + Double(copied) * 6 - 1)
        #expect(try #require(figure) <= leftOut)
        // The sources are all still there.
        #expect(box.names(in: box.path("src")).count == 5)

        // A move onto the full volume: the source stays.
        let a = try volume("GroveA")
        let big = try box.makeFile(at: a.appendingPathComponent("big.bin"), bytes(12, of: 9))
        let moved = await box.run(.move(items: [big], to: b), on: OperationRunner())
        #expect(moved.changes == [])
        #expect(moved.failures == [ItemFailure(url: big, reason: "the disk is full")])
        #expect(moved.summary.hasPrefix("Nothing moved (not enough room on GroveB: "))
        #expect(try Data(contentsOf: big) == bytes(12, of: 9))
        #expect(box.partials(in: b) == [])
    }

    @Test func replacingOnAnotherVolumeUsesThatVolumesTrash() async throws {
        let a = try volume("GroveA")
        let b = try volume("GroveB")
        let file = try box.makeFile(at: a.appendingPathComponent("notes.md"), Data("new".utf8))
        let old = try box.makeFile(at: b.appendingPathComponent("notes.md"), Data("old".utf8))
        let runner = OperationRunner()
        let operation = Operation.move(items: [file], to: b)
        #expect(await runner.existingNames(for: operation) == [old])

        let outcome = await box.run(operation, on: runner, choice: .replace)

        #expect(outcome.failures == [])
        try #require(outcome.changes.count == 2)
        guard case let .replaced(original, inTrash) = outcome.changes[0] else {
            Issue.record("the old one was not replaced first: \(outcome.changes)")
            return
        }
        #expect(original == old)
        #expect(outcome.changes[1] == .moved(from: file, to: old))
        // A volume has its own Trash; the item went there, not off the volume.
        #expect(inTrash.path.hasPrefix(b.path + "/.Trashes/"))
        #expect(box.text(inTrash) == "old")
        #expect(box.text(old) == "new")
        #expect(!box.exists(file))

        // And an item trashed on it goes to the same place.
        let trashed = await box.run(.trash(items: [old]), on: runner)
        guard case let .trashed(_, there)? = trashed.changes.first else {
            Issue.record("not put in the Trash: \(trashed)")
            return
        }
        #expect(there.path.hasPrefix(b.path + "/.Trashes/"))
        #expect(box.text(there) == "new")
    }

    @Test func aSourceThatCannotBeRemovedStaysAndTheCopyIsTold() async throws {
        let a = try volume("GroveA")
        let b = try volume("GroveB")
        let tree = try box.makeFolder(at: a.appendingPathComponent("Tree"))
        let kept = try box.makeFile(at: tree.appendingPathComponent("closed/kept.txt"), Data("kept".utf8))
        #expect(chmod(tree.appendingPathComponent("closed").path, 0o555) == 0)

        let outcome = await box.run(.move(items: [tree], to: b), on: OperationRunner())

        let copy = b.appendingPathComponent("Tree")
        #expect(outcome.changes == [.created(copy)])
        #expect(outcome.failures == [
            ItemFailure(url: tree, reason: "it was copied, but could not be removed from where it was")
        ])
        #expect(box.text(kept) == "kept")
        #expect(box.text(copy.appendingPathComponent("closed/kept.txt")) == "kept")
    }

    @Test func aVolumeAttachedInsideAnItemIsNotCopiedOrEmptied() async throws {
        // The item is on this Mac's own disk (a volume can't be attached
        // inside a disk image's), and goes to another volume.
        let b = try volume("GroveB")
        let tree = try box.makeFolder("src/Tree")
        try box.makeFile(at: tree.appendingPathComponent("one.txt"), Data("one".utf8))
        let inner = try volume("GroveC", at: box.makeFolder(at: tree.appendingPathComponent("inner")))
        let onInner = try box.makeFile(at: inner.appendingPathComponent("theirs.txt"), Data("theirs".utf8))
        let reason = "“inner” in it is another disk, attached there"

        let moved = await box.run(.move(items: [tree], to: b), on: OperationRunner())
        #expect(moved.changes == [])
        #expect(moved.failures == [ItemFailure(url: tree, reason: reason)])
        let copied = await box.run(.copy(items: [tree], to: b), on: OperationRunner())
        #expect(copied.changes == [])
        #expect(copied.failures == [ItemFailure(url: tree, reason: reason)])
        let duplicated = await box.run(.duplicate(items: [tree]), on: OperationRunner())
        #expect(duplicated.changes == [])
        #expect(duplicated.failures == [ItemFailure(url: tree, reason: reason)])

        #expect(box.text(onInner) == "theirs")
        #expect(box.text(tree.appendingPathComponent("one.txt")) == "one")
        #expect(box.allNames(in: b).filter { !$0.hasPrefix(".") || $0.contains("grove-partial") } == [])
        #expect(box.names(in: box.path("src")) == ["Tree"])
    }

    // MARK: ExFAT and FAT

    // The formats of most memory sticks and cards have no rename that
    // refuses to replace. There an item gets its name by way of an empty
    // placeholder made with a call that fails when the name exists.

    @Test func onAVolumeWithoutASafeRenameEveryOperationStillWorks() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let a = try volume("GroveA")
        let runner = OperationRunner()
        func visible(_ folder: URL) -> [String] { box.names(in: folder).filter { !$0.hasPrefix(".") } }

        // A copy to it: a file with an attribute, and a folder.
        let file = try box.makeFile("notes.md", "notes")
        box.setAttribute("com.projectgrove.test", "kept", on: file)
        try box.makeFile("docs/inside.txt", "inside")
        let copied = await box.run(.copy(items: [file, box.path("docs")], to: stick), on: runner)
        let onStick = stick.appendingPathComponent("notes.md")
        #expect(copied.failures == [])
        #expect(copied.changes == [.created(onStick), .created(stick.appendingPathComponent("docs"))])
        #expect(box.text(onStick) == "notes")
        #expect(box.attribute("com.projectgrove.test", of: onStick) == "kept")
        #expect(box.text(stick.appendingPathComponent("docs/inside.txt")) == "inside")
        #expect(visible(stick) == ["docs", "notes.md"])

        // A move to it, of a folder: the source goes.
        let tree = try box.makeFolder(at: a.appendingPathComponent("Tree"))
        let tagged = try box.makeFile(at: tree.appendingPathComponent("a/two.txt"), Data("two".utf8))
        box.setAttribute("com.projectgrove.test", "kept", on: tagged)
        let movedTo = await box.run(.move(items: [tree], to: stick), on: runner)
        let treeOnStick = stick.appendingPathComponent("Tree")
        #expect(movedTo.failures == [])
        #expect(movedTo.changes == [.moved(from: tree, to: treeOnStick)])
        #expect(!box.exists(tree))
        #expect(box.attribute("com.projectgrove.test", of: treeOnStick.appendingPathComponent("a/two.txt")) == "kept")
        // The attribute is in a file of its own there, which is no item.
        #expect(box.allNames(in: treeOnStick.appendingPathComponent("a")).contains("._two.txt"))

        // A rename, to a new name and to the same in other capitals.
        let renamed = await box.run(.rename(item: onStick, to: "ideas.md"), on: runner)
        let ideas = stick.appendingPathComponent("ideas.md")
        #expect(renamed.changes == [.moved(from: onStick, to: ideas)])
        let capitals = await box.run(.rename(item: ideas, to: "Ideas.md"), on: runner)
        #expect(capitals.failures == [])
        #expect(capitals.changes == [.moved(from: ideas, to: stick.appendingPathComponent("Ideas.md"))])
        #expect(visible(stick) == ["Ideas.md", "Tree", "docs"])
        #expect(box.text(stick.appendingPathComponent("Ideas.md")) == "notes")

        // A duplicate, twice; a move on the volume; a replace.
        let ideasNow = stick.appendingPathComponent("Ideas.md")
        _ = await box.run(.duplicate(items: [ideasNow]), on: runner)
        let duplicated = await box.run(.duplicate(items: [ideasNow, treeOnStick]), on: runner)
        #expect(duplicated.changes == [
            .created(stick.appendingPathComponent("Ideas copy 2.md")), .created(stick.appendingPathComponent("Tree copy")),
        ])
        let within = await box.run(.move(items: [ideasNow], to: stick.appendingPathComponent("docs")), on: runner)
        #expect(within.changes == [.moved(from: ideasNow, to: stick.appendingPathComponent("docs/Ideas.md"))])
        let newer = try box.makeFile("Ideas copy.md", "newer")
        let replaced = await box.run(.copy(items: [newer], to: stick), on: runner, choice: .replace)
        #expect(replaced.failures == [])
        #expect(replaced.changes.count == 2)
        #expect(box.text(stick.appendingPathComponent("Ideas copy.md")) == "newer")
        #expect(visible(stick) == ["Ideas copy 2.md", "Ideas copy.md", "Tree", "Tree copy", "docs"])
        #expect(box.partials(in: stick) == [])

        // A move from it (a folder with a file that has an attribute): all
        // of the source goes, and its attribute files are not copied as items.
        let back = await box.run(.move(items: [treeOnStick], to: a), on: runner)
        #expect(back.failures == [])
        #expect(back.changes == [.moved(from: treeOnStick, to: a.appendingPathComponent("Tree", isDirectory: true))])
        #expect(!box.exists(treeOnStick))
        #expect(box.allNames(in: tree.appendingPathComponent("a")) == ["two.txt"])
        #expect(box.attribute("com.projectgrove.test", of: tagged) == "kept")
        #expect(box.text(tagged) == "two")
    }

    @Test func onAVolumeWithoutASafeRenameANameInUseIsNotOverwritten() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let box = box
        let file = try box.makeFile("notes.md", "mine")
        try box.makeFile("docs/inside.txt", "mine")
        let folder = box.path("docs")
        let target = stick.appendingPathComponent("notes.md")
        func visible() -> [String] { box.allNames(in: stick).filter { !$0.hasPrefix(".") || $0.contains("grove-partial") } }

        // The name is taken just before it is asked for: a file's, a folder's.
        let early = OperationRunner(watching: { stage in
            guard case let .placing(url) = stage else { return }
            if url.lastPathComponent == "docs" {
                _ = try? box.makeFile(at: url.appendingPathComponent("theirs.txt"), Data("theirs".utf8))
            } else {
                _ = try? box.makeFile(at: url, Data("theirs".utf8))
            }
        })
        let taken = await box.run(.copy(items: [file, folder], to: stick), on: early)
        #expect(taken.changes == [])
        #expect(taken.failures == [
            ItemFailure(url: file, reason: "an item with that name appeared"),
            ItemFailure(url: folder, reason: "an item with that name appeared"),
        ])
        #expect(box.text(target) == "theirs")
        #expect(box.names(in: stick.appendingPathComponent("docs")) == ["theirs.txt"])
        #expect(visible() == ["docs", "notes.md"])
        try box.files.removeItem(at: target)
        try box.files.removeItem(at: stick.appendingPathComponent("docs"))

        // Another program writes into the placeholder: it is theirs, and stays.
        let written = OperationRunner(watching: { stage in
            guard case let .placeholder(url) = stage else { return }
            if url.lastPathComponent == "docs" {
                _ = try? box.makeFile(at: url.appendingPathComponent("theirs.txt"), Data("theirs".utf8))
            } else {
                try? Data("theirs".utf8).write(to: url)
            }
        })
        let used = await box.run(.copy(items: [file, folder], to: stick), on: written)
        #expect(used.changes == [])
        #expect(used.failures == [
            ItemFailure(url: file, reason: "an item with that name appeared"),
            ItemFailure(url: folder, reason: "an item with that name appeared"),
        ])
        #expect(box.text(target) == "theirs")
        #expect(box.names(in: stick.appendingPathComponent("docs")) == ["theirs.txt"])
        #expect(visible() == ["docs", "notes.md"])
        try box.files.removeItem(at: target)
        try box.files.removeItem(at: stick.appendingPathComponent("docs"))

        // The rename over the placeholder fails (the copy is gone by then):
        // no placeholder is left under the name.
        let gone = OperationRunner(watching: { stage in
            guard case .placeholder = stage else { return }
            for name in box.partials(in: stick) {
                try? box.files.removeItem(at: stick.appendingPathComponent(name))
            }
        })
        let failed = await box.run(.copy(items: [file, folder], to: stick), on: gone)
        #expect(failed.changes == [])
        #expect(failed.failures == [
            ItemFailure(url: file, reason: "it is no longer there"),
            ItemFailure(url: folder, reason: "it is no longer there"),
        ])
        #expect(visible() == [])
        #expect(box.text(file) == "mine")
    }

    @Test func onAVolumeWithoutASafeRenameEmptyFilesAndNamesInUseAreSafe() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let box = box
        let runner = OperationRunner()

        // Empty files, which all look alike, are copied and renamed there.
        let empty = try box.makeFile("empty.txt", "")
        let alsoEmpty = try box.makeFile("also-empty.txt", "")
        let copied = await box.run(.copy(items: [empty, alsoEmpty], to: stick), on: runner)
        #expect(copied.failures == [])
        #expect(copied.changes.count == 2)
        let onStick = stick.appendingPathComponent("empty.txt")
        let renamed = await box.run(.rename(item: onStick, to: "void.txt"), on: runner)
        let void = stick.appendingPathComponent("void.txt")
        #expect(renamed.changes == [.moved(from: onStick, to: void)])
        #expect(box.allNames(in: stick).filter { !$0.hasPrefix(".") } == ["also-empty.txt", "void.txt"])

        // A rename onto a name in use, of an empty file and of one that is
        // not: refused before anything is tried.
        let full = try box.makeFile(at: stick.appendingPathComponent("full.txt"), Data("full".utf8))
        for (taken, name) in [(stick.appendingPathComponent("also-empty.txt"), "also-empty.txt"), (full, "full.txt")] {
            #expect(await runner.existingNames(for: .rename(item: void, to: name)) == [taken])
            let onto = await box.run(.rename(item: void, to: name), on: runner)
            #expect(onto.changes == [])
            #expect(onto.failures == [ItemFailure(url: void, reason: "an item named “\(name)” is already there")])
        }
        #expect(box.text(full) == "full")
        #expect(box.text(void) == "")

        // And when the name is taken only just before the rename, by an
        // empty file and by one that is not.
        for theirs in ["", "theirs"] {
            let late = OperationRunner(watching: { stage in
                if case let .placing(url) = stage { _ = try? box.makeFile(at: url, Data(theirs.utf8)) }
            })
            let name = theirs.isEmpty ? "late-empty.txt" : "late-full.txt"
            let onto = await box.run(.rename(item: void, to: name), on: late)
            #expect(onto.changes == [])
            #expect(onto.failures == [ItemFailure(url: void, reason: "an item with that name appeared")])
            #expect(box.text(stick.appendingPathComponent(name)) == theirs)
            #expect(box.exists(void))
        }
        #expect(box.allNames(in: stick).filter { !$0.hasPrefix(".") }
            == ["also-empty.txt", "full.txt", "late-empty.txt", "late-full.txt", "void.txt"])
    }

    @Test func aFileNamedLikeAnAttributeFileCannotGoBesideItsNameOnSuchAVolume() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let runner = OperationRunner()
        // On this Mac's disk: twelve files, each with an attribute, and
        // beside each a real file named as macOS would name its attribute file.
        let pairs = try box.makeFolder("Pairs")
        let names = (0..<12).map { "n\($0).txt" }
        for name in names {
            let file = try box.makeFile("Pairs/\(name)", "data of \(name)")
            box.setAttribute("com.projectgrove.test", "kept", on: file)
            try box.makeFile("Pairs/._\(name)", "real ._\(name)")
        }
        // The folder lists some names before their `._` file and some after:
        // both orders are in the test.
        let listed = try #require(TreeCopier.names(in: pairs.path))
        let nameFirst = names.map { listed.firstIndex(of: $0)! < listed.firstIndex(of: "._" + $0)! }
        #expect(nameFirst.contains(true) && nameFirst.contains(false))
        let leftOut = names.map {
            ItemFailure(
                url: pairs.appendingPathComponent("._" + $0), reason: "it can't be kept beside “\($0)” on this disk")
        }
        func sorted(_ failures: [ItemFailure]) -> [ItemFailure] { failures.sorted { $0.url.path < $1.url.path } }

        // Copied: the folder arrives with every file; every `._` file is
        // told as left out, none is written, none overwritten unseen.
        let copied = await box.run(.copy(items: [pairs], to: stick), on: runner)
        let onStick = stick.appendingPathComponent("Pairs")
        #expect(copied.changes == [.created(onStick)])
        #expect(sorted(copied.failures) == sorted(leftOut))
        #expect(copied.summary == "Copied Pairs to mnt-GROVEFAT (12 left out)")
        for name in names {
            #expect(box.text(onStick.appendingPathComponent(name)) == "data of \(name)")
            #expect(box.attribute("com.projectgrove.test", of: onStick.appendingPathComponent(name)) == "kept")
            // What is there under the `._` name is macOS's own.
            #expect(TreeCopier.isAttributeFile(onStick.appendingPathComponent("._" + name).path))
            #expect(box.text(pairs.appendingPathComponent("._" + name)) == "real ._\(name)")
        }

        // Moved: the copy is not all of it, so the source stays, whole.
        try box.files.removeItem(at: onStick)
        let moved = await box.run(.move(items: [pairs], to: stick), on: runner)
        #expect(moved.changes == [.created(onStick)])
        #expect(sorted(moved.failures) == sorted(leftOut + [
            ItemFailure(
                url: pairs, reason: "it was copied without what can't be kept on this disk, and left where it is")
        ]))
        #expect(box.allNames(in: pairs).count == 24)

        // The two by themselves, in either order: the file goes, the `._` one doesn't.
        let file = pairs.appendingPathComponent("n0.txt")
        let dotted = pairs.appendingPathComponent("._n0.txt")
        for (index, items) in [[file, dotted], [dotted, file]].enumerated() {
            let folder = try box.makeFolder(at: stick.appendingPathComponent("order-\(index)"))
            let both = await box.run(.copy(items: items, to: folder), on: runner)
            #expect(both.changes == [.created(folder.appendingPathComponent("n0.txt"))])
            #expect(both.failures == [
                ItemFailure(url: dotted, reason: "it can't be kept beside “n0.txt” on this disk")
            ])
            #expect(box.text(folder.appendingPathComponent("n0.txt")) == "data of n0.txt")
        }
        // Without its name beside it, it is a file like any other.
        let alone = try box.makeFolder(at: stick.appendingPathComponent("alone"))
        let orphan = await box.run(.copy(items: [dotted], to: alone), on: runner)
        #expect(orphan.failures == [])
        #expect(box.text(alone.appendingPathComponent("._n0.txt")) == "real ._n0.txt")

        // The volume takes "X.TXT" for "x.txt", so that is a pair there too:
        // in a folder, and as two items.
        let mixed = try box.makeFolder("Case")
        let lower = try box.makeFile("Case/x.txt", "data")
        box.setAttribute("com.projectgrove.test", "kept", on: lower)
        let upper = try box.makeFile("Case/._X.TXT", "real")
        let reason = "it can't be kept beside “X.TXT” on this disk"
        let inFolder = await box.run(.copy(items: [mixed], to: stick), on: runner)
        #expect(inFolder.changes == [.created(stick.appendingPathComponent("Case"))])
        #expect(inFolder.failures == [ItemFailure(url: mixed.appendingPathComponent("._X.TXT"), reason: reason)])
        #expect(box.text(stick.appendingPathComponent("Case/x.txt")) == "data")
        for (index, items) in [[lower, upper], [upper, lower]].enumerated() {
            let folder = try box.makeFolder(at: stick.appendingPathComponent("case-\(index)"))
            let both = await box.run(.copy(items: items, to: folder), on: runner)
            #expect(both.changes == [.created(folder.appendingPathComponent("x.txt"))])
            #expect(both.failures == [ItemFailure(url: upper, reason: reason)])
        }
    }

    @Test func aRealFileNamedLikeAnAttributeFileIsNotLostWhenItsNameMovesOffSuchAVolume() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let a = try volume("GroveA")
        let runner = OperationRunner()
        /// `name` in `folder` on the stick, and beside it a `._name` that
        /// is a file of the user's, not macOS's attribute file.
        func pair(_ name: String, in folder: URL) throws -> (file: URL, dotted: URL) {
            let file = try box.makeFile(at: folder.appendingPathComponent(name), Data("data".utf8))
            let dotted = folder.appendingPathComponent("._" + name)
            try Data("real".utf8).write(to: dotted)
            #expect(!TreeCopier.isAttributeFile(dotted.path))
            return (file, dotted)
        }
        let folder = try box.makeFolder(at: stick.appendingPathComponent("Folder"))
        _ = try pair("x.txt", in: folder)
        let (file, dotted) = try pair("y.txt", in: stick)

        // The user's `._` file is an item of its folder; the one macOS
        // wrote for a file's attributes is not.
        let plain = try box.makeFile(at: folder.appendingPathComponent("z.txt"), Data("z".utf8))
        box.setAttribute("com.projectgrove.test", "kept", on: plain)
        #expect(box.allNames(in: folder) == ["._x.txt", "._z.txt", "x.txt", "z.txt"])
        let copier = TreeCopier(flag: CancelFlag(), reporter: Reporter(send: { _ in }, watching: nil), watching: nil)
        #expect(copier.items(in: folder.path)?.sorted() == ["._x.txt", "x.txt", "z.txt"])
        try box.files.removeItem(at: plain)
        #expect(box.allNames(in: folder) == ["._x.txt", "x.txt"])

        // What really happens there: macOS takes the `._` file for the
        // attributes of its name, can't read them, and so the name can't be
        // copied with its attributes. The item fails; nothing is removed,
        // of the folder or of the pair, and nothing is left at the target.
        let moved = await box.run(.move(items: [folder], to: a), on: runner)
        #expect(moved.changes == [])
        #expect(moved.failures == [
            ItemFailure(url: folder, reason: "“x.txt” in it: its attributes can't be read")
        ])
        #expect(box.allNames(in: folder) == ["._x.txt", "x.txt"])
        #expect(box.text(folder.appendingPathComponent("._x.txt")) == "real")

        let alone = await box.run(.move(items: [file], to: a), on: runner)
        #expect(alone.changes == [])
        #expect(alone.failures == [ItemFailure(url: file, reason: "its attributes can't be read")])
        #expect(box.text(file) == "data")
        #expect(box.text(dotted) == "real")
        #expect(box.allNames(in: a).filter { !$0.hasPrefix(".") || $0.contains("grove-partial") } == [])

        // The `._` file by itself is a file like any other, and can go.
        let only = await box.run(.copy(items: [dotted], to: a), on: runner)
        #expect(only.failures == [])
        #expect(box.text(a.appendingPathComponent("._y.txt")) == "real")
    }

    @Test func aFileOfTheUsersUnderAnAttributeFileNameIsNotOverwrittenByAnArrival() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let a = try volume("GroveA")
        let runner = OperationRunner()
        // On the stick, files of the user's named as macOS names its
        // attribute files, with nothing beside them (yet).
        let folder = try box.makeFolder(at: stick.appendingPathComponent("in"))
        let reals = ["._n.txt", "._d", "._m copy.txt", "._k 2.txt"]
        for name in reals { try box.makeFile(at: folder.appendingPathComponent(name), Data("real \(name)".utf8)) }
        func inTheWay(_ name: String) -> String { "“\(name)” is in the way on this disk" }

        // An arrival under the name beside one of them would have macOS
        // write its attribute file over it. Each is refused, before anything
        // is written: a copy, a move from another volume and on this one, a
        // rename, a new folder, a duplicate, and "keep both"'s next name.
        let file = try box.makeFile("n.txt", "data")
        box.setAttribute("com.projectgrove.test", "kept", on: file)
        let copied = await box.run(.copy(items: [file], to: folder), on: runner)
        #expect(copied.changes == [])
        #expect(copied.failures == [ItemFailure(url: file, reason: inTheWay("._n.txt"))])

        let onA = try box.makeFile(at: a.appendingPathComponent("n.txt"), Data("data".utf8))
        let moved = await box.run(.move(items: [onA], to: folder), on: runner)
        #expect(moved.changes == [])
        #expect(moved.failures == [ItemFailure(url: onA, reason: inTheWay("._n.txt"))])
        #expect(box.text(onA) == "data")

        let elsewhere = try box.makeFile(at: stick.appendingPathComponent("other/n.txt"), Data("data".utf8))
        let within = await box.run(.move(items: [elsewhere], to: folder), on: runner)
        #expect(within.changes == [])
        #expect(within.failures == [ItemFailure(url: elsewhere, reason: inTheWay("._n.txt"))])
        #expect(box.text(elsewhere) == "data")

        let z = try box.makeFile(at: folder.appendingPathComponent("z.txt"), Data("z".utf8))
        let renamed = await box.run(.rename(item: z, to: "n.txt"), on: runner)
        #expect(renamed.changes == [])
        #expect(renamed.failures == [ItemFailure(url: z, reason: inTheWay("._n.txt"))])
        #expect(box.text(z) == "z")

        let made = await box.run(.newFolder(in: folder, name: "d"), on: runner)
        #expect(made.changes == [])
        #expect(made.failures == [
            ItemFailure(url: folder.appendingPathComponent("d", isDirectory: true), reason: inTheWay("._d"))
        ])

        let m = try box.makeFile(at: folder.appendingPathComponent("m.txt"), Data("m".utf8))
        let duplicated = await box.run(.duplicate(items: [m]), on: runner)
        #expect(duplicated.changes == [])
        #expect(duplicated.failures == [ItemFailure(url: m, reason: inTheWay("._m copy.txt"))])

        try box.makeFile(at: folder.appendingPathComponent("k.txt"), Data("old".utf8))
        let k = try box.makeFile("k.txt", "new")
        let kept = await box.run(.copy(items: [k], to: folder), on: runner, choice: .keepBoth)
        #expect(kept.changes == [])
        #expect(kept.failures == [ItemFailure(url: k, reason: inTheWay("._k 2.txt"))])

        // Every one of them is as it was, and nothing else came.
        for name in reals { #expect(box.text(folder.appendingPathComponent(name)) == "real \(name)") }
        #expect(box.allNames(in: folder).filter { !$0.hasPrefix("._") } == ["k.txt", "m.txt", "z.txt"])
        #expect(box.partials(in: folder) == [])

        // What macOS does with such a file when the name beside it is
        // renamed, moved or put in the Trash: it goes with it, under the
        // new name. Nothing is lost, so that is not refused.
        let pair = try box.makeFolder(at: stick.appendingPathComponent("pair"))
        let x = try box.makeFile(at: pair.appendingPathComponent("x.txt"), Data("data".utf8))
        try Data("real".utf8).write(to: pair.appendingPathComponent("._x.txt"))
        let carried = await box.run(.rename(item: x, to: "y.txt"), on: runner)
        #expect(carried.failures == [])
        #expect(box.allNames(in: pair) == ["._y.txt", "y.txt"])
        #expect(box.text(pair.appendingPathComponent("._y.txt")) == "real")
        let along = await box.run(.move(items: [pair.appendingPathComponent("y.txt")], to: stick), on: runner)
        #expect(along.failures == [])
        #expect(box.allNames(in: pair) == [])
        #expect(box.text(stick.appendingPathComponent("._y.txt")) == "real")
        let trashed = await box.run(.trash(items: [stick.appendingPathComponent("y.txt")]), on: runner)
        guard case let .trashed(_, inTrash)? = trashed.changes.first else {
            Issue.record("not put in the Trash: \(trashed)")
            return
        }
        #expect(box.text(inTrash.deletingLastPathComponent().appendingPathComponent("._y.txt")) == "real")
        #expect(!box.exists(stick.appendingPathComponent("._y.txt")))
    }

    @Test func theSourceIsNotRemovedWhileAFileOfTheUsersWouldGoWithIt() async throws {
        let stick = try volume("GROVEFAT", format: "ExFAT")
        let a = try volume("GroveA")
        func copier() -> TreeCopier {
            TreeCopier(flag: CancelFlag(), reporter: Reporter(send: { _ in }, watching: nil), watching: nil)
        }

        // Beside the item itself: copied, and then a file of the user's
        // appears under the name macOS would remove with it.
        let file = try box.makeFile(at: stick.appendingPathComponent("y.txt"), Data("data".utf8))
        let one = copier()
        try one.copy(file.path, to: a.appendingPathComponent("y.txt").path, remembering: true)
        #expect(one.isWhole(a.appendingPathComponent("y.txt").path, of: file.path))
        let beside = stick.appendingPathComponent("._y.txt")
        try Data("real".utf8).write(to: beside)

        #expect(!one.removeSource(file.path, copiedTo: a.appendingPathComponent("y.txt").path))
        #expect(box.text(file) == "data")
        #expect(box.text(beside) == "real")

        // Inside the item: the same, beside a file in the folder copied.
        let folder = try box.makeFolder(at: stick.appendingPathComponent("Folder"))
        let inner = try box.makeFile(at: folder.appendingPathComponent("x.txt"), Data("data".utf8))
        let other = copier()
        try other.copy(folder.path, to: a.appendingPathComponent("Folder").path, remembering: true)
        #expect(other.isWhole(a.appendingPathComponent("Folder").path, of: folder.path))
        let innerBeside = folder.appendingPathComponent("._x.txt")
        try Data("real".utf8).write(to: innerBeside)

        #expect(!other.removeSource(folder.path, copiedTo: a.appendingPathComponent("Folder").path))
        #expect(box.text(inner) == "data")
        #expect(box.text(innerBeside) == "real")
    }
}
