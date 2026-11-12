import Foundation
@testable import GroveExplorerCore
import Testing

// Foundation has an `Operation` too.
private typealias Operation = GroveExplorerCore.Operation

/// The words of an operation, of what it did, and of a refusal. Nothing
/// here touches the disk.
@Suite struct OperationTests {
    private func items(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/src/item-\($0).txt") }
    }

    private let notes = URL(fileURLWithPath: "/src/notes.md")
    private let downloads = URL(fileURLWithPath: "/Users/someone/Downloads", isDirectory: true)

    // MARK: While it runs

    @Test func wordsNameOneItemAndCountMore() {
        #expect(Operation.copy(items: items(1_204), to: downloads).words == "Copying 1,204 items to Downloads")
        #expect(
            Operation.move(items: [notes], to: URL(fileURLWithPath: "/Users/someone/Documents")).words
                == "Moving notes.md to Documents")
        #expect(Operation.copy(items: [notes], to: downloads).words == "Copying notes.md to Downloads")
        #expect(Operation.move(items: items(2), to: downloads).words == "Moving 2 items to Downloads")
    }

    @Test func wordsOfTheOperationsWithoutATarget() {
        #expect(Operation.duplicate(items: [notes]).words == "Duplicating notes.md")
        #expect(Operation.duplicate(items: items(3)).words == "Duplicating 3 items")
        #expect(Operation.rename(item: notes, to: "ideas.md").words == "Renaming notes.md to ideas.md")
        #expect(Operation.newFolder(in: downloads, name: "Projects").words == "Making the folder Projects")
        #expect(Operation.trash(items: [notes]).words == "Moving notes.md to the Trash")
        #expect(Operation.trash(items: items(1_000_000)).words == "Moving 1,000,000 items to the Trash")
    }

    @Test func numbersAreGroupedInThrees() {
        #expect(Wording.grouped(0) == "0")
        #expect(Wording.grouped(999) == "999")
        #expect(Wording.grouped(1_000) == "1,000")
        #expect(Wording.grouped(12_345) == "12,345")
        #expect(Wording.grouped(1_234_567) == "1,234,567")
    }

    // MARK: When it is over

    private func summary(
        _ operation: Operation, done: Int, skipped: Int = 0, failed: Int = 0, cancelled: Bool = false,
        shortage: Shortage? = nil
    ) -> String {
        Wording.summary(
            of: operation, done: done, skipped: skipped, failed: failed, cancelled: cancelled,
            shortage: shortage)
    }

    @Test func summaryOfARunThatDidEverything() {
        #expect(summary(.move(items: items(3), to: downloads), done: 3) == "Moved 3 items to Downloads")
        #expect(summary(.copy(items: [notes], to: downloads), done: 1) == "Copied notes.md to Downloads")
        #expect(summary(.duplicate(items: [notes]), done: 1) == "Duplicated notes.md")
        #expect(summary(.rename(item: notes, to: "ideas.md"), done: 1) == "Renamed notes.md to ideas.md")
        #expect(summary(.newFolder(in: downloads, name: "Projects"), done: 1) == "Made the folder Projects")
        #expect(summary(.trash(items: items(2)), done: 2) == "Moved 2 items to the Trash")
    }

    @Test func summaryOfARunThatStoppedOrLeftItemsOut() {
        let copy = Operation.copy(items: items(40), to: downloads)
        #expect(summary(copy, done: 12, cancelled: true) == "Copied 12 of 40 items (cancelled)")
        #expect(summary(copy, done: 37, failed: 3) == "Copied 37 of 40 items (3 failed)")
        #expect(summary(copy, done: 30, skipped: 10) == "Copied 30 of 40 items (10 skipped)")
        #expect(
            summary(copy, done: 5, skipped: 2, failed: 1, cancelled: true)
                == "Copied 5 of 40 items (cancelled, 1 failed, 2 skipped)")
        #expect(summary(.move(items: [notes], to: downloads), done: 0, failed: 1) == "Nothing moved (1 failed)")
        #expect(summary(.rename(item: notes, to: "ideas.md"), done: 0, failed: 1) == "Nothing renamed (1 failed)")
        #expect(
            summary(.trash(items: items(3)), done: 2, failed: 1) == "Moved 2 of 3 items to the Trash (1 failed)")
        #expect(summary(.trash(items: [notes]), done: 0, failed: 1) == "Nothing moved to the Trash (1 failed)")
    }

    @Test func summaryOfAFullDiskNamesTheMissingRoom() {
        let copy = Operation.copy(items: items(5), to: downloads)
        #expect(
            summary(copy, done: 2, failed: 1, shortage: Shortage(volume: "Backup", missing: 12_600_000))
                == "Copied 2 of 5 items (not enough room on Backup: 12.6 MB more needed)")
        #expect(
            summary(copy, done: 0, failed: 1, shortage: Shortage(volume: "Backup", missing: nil))
                == "Nothing copied (not enough room on Backup)")
    }

    // MARK: Refusals

    @Test func aRefusalIsASentence() {
        let folder = URL(fileURLWithPath: "/a", isDirectory: true)
        #expect(OperationRefusal.intoItself(folder).sentence == "“a” can't be put inside itself.")
        #expect(OperationRefusal.ontoItself(notes).sentence == "“notes.md” is already there.")
        #expect(OperationRefusal.badName("", reason: "A name can't be empty.").sentence == "A name can't be empty.")
        #expect(OperationRefusal.nothingToDo.sentence == "There is nothing to do.")
    }
}
