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

    /// With folders open in place, what a run made is found in whichever
    /// listed folder it went to, at any depth.
    @Test func arrivalsAreFoundInEveryListedFolder() {
        let folders = ["/t", "/t/a", "/t/a/b"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let new = ["/t/x", "/t/a/b/y", "/t/closed/z"].map { URL(fileURLWithPath: $0) }
        let listed = ["/t/x", "/t/a", "/t/a/b", "/t/a/b/y/"].map { URL(fileURLWithPath: $0) }
        let here = AfterOperation.arrivals(new, in: folders, listed: listed)
        // As the listings spell them; z is in no listed folder, so not awaited.
        #expect(here.found.map(\.path) == ["/t/x", "/t/a/b/y"])
        #expect(here.complete)
        let partly = AfterOperation.arrivals(new, in: folders, listed: [URL(fileURLWithPath: "/t/x")])
        #expect(partly.found.map(\.path) == ["/t/x"])
        #expect(!partly.complete)
    }

    /// F5 into an open folder: its listing has the copy before its rows
    /// do (the rows are arranged off the main thread). Looked for among
    /// the rows, the copy is not there yet and the arrivals are not done;
    /// once the rows land with it, it is found, and they are.
    @Test func arrivalsInAnOpenFolderAreFoundOnceItsRowsLand() {
        func entry(_ path: String, _ kind: Entry.Kind = .file) -> Entry {
            let url = URL(fileURLWithPath: path, isDirectory: kind == .folder)
            return Entry(url: url, name: url.lastPathComponent, kind: kind, size: nil, modified: nil, isHidden: false,
                typeDescription: "")
        }
        let root = URL(fileURLWithPath: "/t", isDirectory: true), open = entry("/t/a", .folder).url
        func rows(_ children: [Entry]) -> [URL] {
            Tree.items(TreeInput(
                root: [entry("/t/a", .folder), entry("/t/z.txt")], children: [open: children], open: [open],
                hasContents: [:], sort: .byName, folderSizes: [:], filter: "", showHidden: false)
            ).compactMap { if case .row(let row) = $0 { row.entry.url } else { nil } }
        }
        let made = [URL(fileURLWithPath: "/t/a/new.txt")]
        let before = rows([entry("/t/a/old.txt")])
        let early = AfterOperation.arrivals(made, in: [root, open], listed: before)
        #expect(early.found.isEmpty && !early.complete)
        let after = rows([entry("/t/a/old.txt"), entry("/t/a/new.txt")])
        let landed = AfterOperation.arrivals(made, in: [root, open], listed: after)
        #expect(landed.found.map(\.path) == ["/t/a/new.txt"] && landed.complete)
    }

    /// F5 of foo.txt and bar.txt into a pane filtered on "foo": bar.txt is
    /// listed but won't show, so it is not awaited, and the arrivals are
    /// complete with foo.txt. A hidden item while hidden items are hidden
    /// is the same; one not listed yet is still awaited.
    @Test func whatWontShowIsNotAwaited() {
        func entry(_ path: String, hidden: Bool = false) -> Entry {
            let url = URL(fileURLWithPath: path)
            return Entry(url: url, name: url.lastPathComponent, kind: .file, size: nil, modified: nil, isHidden: hidden,
                typeDescription: "")
        }
        let folder = URL(fileURLWithPath: "/t", isDirectory: true)
        let listed = [entry("/t/foo.txt"), entry("/t/bar.txt"), entry("/t/.foo-hidden", hidden: true)]
        let made = ["/t/foo.txt", "/t/bar.txt", "/t/.foo-hidden"].map { URL(fileURLWithPath: $0) }
        let unshown = AfterOperation.unshown(made, among: listed, showHidden: false, filter: "foo")
        #expect(Set(unshown.map(\.path)) == ["/t/bar.txt", "/t/.foo-hidden"])
        let here = AfterOperation.arrivals(
            made, in: [folder], listed: [URL(fileURLWithPath: "/t/foo.txt")], leavingOut: unshown)
        #expect(here.found.map(\.path) == ["/t/foo.txt"] && here.complete)
        // Without a filter, with hidden items shown: everything listed shows.
        #expect(AfterOperation.unshown(made, among: listed, showHidden: true, filter: "  ").isEmpty)
        // One not listed yet is awaited.
        let early = AfterOperation.arrivals(
            made + [URL(fileURLWithPath: "/t/foo 2.txt")], in: [folder], listed: [URL(fileURLWithPath: "/t/foo.txt")],
            leavingOut: unshown)
        #expect(!early.complete)
    }
}
