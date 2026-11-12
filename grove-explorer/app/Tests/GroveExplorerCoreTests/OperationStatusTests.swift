import Foundation
import GroveExplorerCore
import Testing

@Suite struct OperationStatusTests {
    private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
    private func items(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/Users/me/Documents/\($0).md") }
    }
    private func progress(_ done: Int64, _ total: Int64, items: Int, of all: Int) -> GroveExplorerCore.Progress {
        Progress(done: done, total: total, itemsDone: items, itemsTotal: all)
    }

    // MARK: While it runs

    @Test func severalItemsAreCounted() {
        let copy = Operation.copy(items: items(342), to: downloads)
        #expect(OperationStatus.running(copy, progress(1, 10, items: 128, of: 342)) == "Copying 128 of 342 to Downloads")
        #expect(OperationStatus.running(.move(items: items(1204), to: downloads), progress(0, 1204, items: 1000, of: 1204))
            == "Moving 1,000 of 1,204 to Downloads")
        #expect(OperationStatus.running(.trash(items: items(5)), progress(2, 5, items: 2, of: 5)) == "Moving 2 of 5 to the Trash")
        #expect(OperationStatus.running(.duplicate(items: items(5)), progress(2, 5, items: 2, of: 5)) == "Duplicating 2 of 5")
    }

    @Test func oneItemAndARunNotYetHeardFromSayTheOperationsWords() {
        let one = Operation.copy(items: [URL(fileURLWithPath: "/Users/me/Documents/notes.md")], to: downloads)
        #expect(OperationStatus.running(one, progress(1, 10, items: 0, of: 1)) == "Copying notes.md to Downloads")
        let many = Operation.copy(items: items(342), to: downloads)
        #expect(OperationStatus.running(many, nil) == "Copying 342 items to Downloads")
    }

    @Test func theMeterIsBytesOrItemsDoneOfTheTotal() {
        #expect(OperationStatus.fraction(progress(37, 100, items: 1, of: 9)) == 0.37)
        #expect(OperationStatus.fraction(nil) == 0)
        // Nothing to do is not a division.
        #expect(OperationStatus.fraction(progress(0, 0, items: 0, of: 0)) == 0)
        // Never beyond its ends, whatever is told.
        #expect(OperationStatus.fraction(progress(12, 10, items: 1, of: 1)) == 1)
        #expect(OperationStatus.fraction(progress(-1, 10, items: 1, of: 1)) == 0)
        #expect(OperationStatus.percent(progress(128, 342, items: 128, of: 342)) == "37%")
        #expect(OperationStatus.percent(nil) == "0%")
    }

    // MARK: After

    @Test func failuresAreCountedWithWhatWasNotDone() {
        #expect(OperationStatus.couldNot(.copy(items: items(9), to: downloads), failed: 3) == "3 items could not be copied")
        #expect(OperationStatus.couldNot(.copy(items: items(9), to: downloads), failed: 1) == "1 item could not be copied")
        #expect(OperationStatus.couldNot(.move(items: items(9), to: downloads), failed: 2) == "2 items could not be moved")
        #expect(OperationStatus.couldNot(.duplicate(items: items(9)), failed: 2) == "2 items could not be duplicated")
        #expect(OperationStatus.couldNot(.trash(items: items(2000)), failed: 1200) == "1,200 items could not be moved to the Trash")
        #expect(OperationStatus.couldNot(.rename(item: items(1)[0], to: "x"), failed: 1) == "1 item could not be renamed")
        #expect(OperationStatus.couldNot(.newFolder(in: downloads, name: "x"), failed: 1) == "The folder could not be made")
    }

    @Test func aFailureIsItsNameAndTheReason() {
        let failure = ItemFailure(url: URL(fileURLWithPath: "/Users/me/Documents/notes.md"), reason: "you don't have permission")
        #expect(OperationStatus.line(for: failure) == "notes.md: you don't have permission")
    }

    @Test func aRenameThatFailedSaysWhyUnderItsField() {
        let taken = ItemFailure(
            url: URL(fileURLWithPath: "/Users/me/Documents/notes.md"), reason: "an item named “todo.md” is already there")
        #expect(OperationStatus.renameReason(for: taken) == "An item named “todo.md” is already there.")
        #expect(OperationStatus.nameTaken("todo.md") == "An item named “todo.md” is already there.")
    }
}
