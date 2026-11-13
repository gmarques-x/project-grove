import Foundation
import GroveExplorerCore
import Testing

@Suite struct AfterOperationTests {
    private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
    private let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)
    private let trash = URL(fileURLWithPath: "/Users/me/.Trash", isDirectory: true)

    private func outcome(_ changes: [Change]) -> Outcome {
        Outcome(changes: changes, failures: [], cancelled: false, summary: "")
    }

    // MARK: What to select

    @Test func whatCameOrWasRenamedIsSelected() {
        let made = documents.appendingPathComponent("a.md")
        let from = downloads.appendingPathComponent("b.md"), to = documents.appendingPathComponent("b.md")
        #expect(AfterOperation.newItems(of: outcome([.created(made), .moved(from: from, to: to)])) == [made, to])
    }

    @Test func whatWentToTheTrashIsNotSelected() {
        let item = downloads.appendingPathComponent("a.md"), gone = trash.appendingPathComponent("a.md")
        let came = downloads.appendingPathComponent("a.md")
        #expect(AfterOperation.newItems(of: outcome([.trashed(original: item, inTrash: gone)])).isEmpty)
        // A replace: the newcomer, not the one it sent to the Trash.
        #expect(AfterOperation.newItems(of: outcome([.replaced(original: item, inTrash: gone), .created(came)])) == [came])
    }

    @Test func theArrivalsOfAFolderAreTheListedOnesAndWhetherAllAreThere() {
        let a = documents.appendingPathComponent("a.md"), b = documents.appendingPathComponent("b.md")
        let elsewhere = downloads.appendingPathComponent("c.md")
        let listedA = URL(fileURLWithPath: "/Users/me/Documents/a.md")
        let other = URL(fileURLWithPath: "/Users/me/Documents/z.md")

        let some = AfterOperation.arrivals([a, b, elsewhere], in: documents, listed: [other, listedA])
        #expect(some.found == [listedA])
        #expect(!some.complete)

        let all = AfterOperation.arrivals([a, b, elsewhere], in: documents, listed: [a, b, other])
        #expect(all.found == [a, b])
        #expect(all.complete)

        // Nothing of it belongs here.
        let none = AfterOperation.arrivals([elsewhere], in: documents, listed: [a])
        #expect(none.found.isEmpty)
        #expect(!none.complete)
    }

    @Test func aNewFolderIsFoundUnderTheUrlTheListingGivesIt() {
        // The runner's URL of a folder and the listing's may differ by the slash at the end.
        let made = URL(fileURLWithPath: "/Users/me/Documents/untitled folder", isDirectory: false)
        let listed = URL(fileURLWithPath: "/Users/me/Documents/untitled folder", isDirectory: true)
        let arrivals = AfterOperation.arrivals([made], in: documents, listed: [listed])
        #expect(arrivals.found == [listed])
        #expect(arrivals.found.first?.absoluteString == listed.absoluteString)
        #expect(arrivals.complete)
    }

    // MARK: Folders touched

    @Test func aCopyTouchesItsTargetAndAMoveItsSourcesToo() {
        let a = downloads.appendingPathComponent("a.md")
        #expect(AfterOperation.touchedFolders(by: .copy(items: [a], to: documents), outcome: outcome([])) == [documents])
        #expect(
            Set(AfterOperation.touchedFolders(by: .move(items: [a], to: documents), outcome: outcome([])).map(\.path))
                == [downloads.path, documents.path])
    }

    @Test func theOthersTouchTheFoldersOfTheirItems() {
        let a = downloads.appendingPathComponent("a.md"), b = documents.appendingPathComponent("b.md")
        #expect(AfterOperation.touchedFolders(by: .duplicate(items: [a]), outcome: outcome([])).map(\.path) == [downloads.path])
        #expect(AfterOperation.touchedFolders(by: .rename(item: a, to: "c.md"), outcome: outcome([])).map(\.path) == [downloads.path])
        #expect(AfterOperation.touchedFolders(by: .newFolder(in: documents, name: "x"), outcome: outcome([])).map(\.path) == [documents.path])
        #expect(
            Set(AfterOperation.touchedFolders(by: .trash(items: [a, b]), outcome: outcome([])).map(\.path))
                == [downloads.path, documents.path])
    }

    @Test func aFolderIsNamedOnceAndTheFoldersOfTheChangesCount() {
        let a = downloads.appendingPathComponent("a.md"), b = downloads.appendingPathComponent("b.md")
        #expect(AfterOperation.touchedFolders(by: .trash(items: [a, b]), outcome: outcome([])).count == 1)
        // A replaced item's old place, wherever the changes say it was.
        let elsewhere = URL(fileURLWithPath: "/Volumes/Backup/x.md")
        let touched = AfterOperation.touchedFolders(
            by: .trash(items: [a]), outcome: outcome([.trashed(original: elsewhere, inTrash: trash.appendingPathComponent("x.md"))]))
        #expect(Set(touched.map(\.path)) == [downloads.path, "/Volumes/Backup"])
    }

    // MARK: Totals that are stale

    @Test func aTouchedFolderAndTheFoldersItIsInHaveStaleTotals() {
        let known = [
            URL(fileURLWithPath: "/Users/me", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Documents/letters", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Doc", isDirectory: true),
        ]
        let stale = AfterOperation.staleTotals(among: known, touched: [documents])
        #expect(stale == [known[0], known[1]])
        #expect(AfterOperation.staleTotals(among: known, touched: []).isEmpty)
    }

    /// A change deep inside open folders: the totals of every folder it is
    /// in that shows as a row are stale, and no other.
    @Test func aChangeInsideOpenFoldersMakesTheirTotalsStale() {
        let known = ["/t/a", "/t/a/b", "/t/a/b/c", "/t/a/b2", "/t/a2", "/t/z"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let stale = AfterOperation.staleTotals(among: known, touched: [URL(fileURLWithPath: "/t/a/b/c/d")])
        #expect(stale.map(\.path) == ["/t/a", "/t/a/b", "/t/a/b/c"])
    }
}
