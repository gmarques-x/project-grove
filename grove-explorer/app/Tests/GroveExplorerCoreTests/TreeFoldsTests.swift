import Foundation
import GroveExplorerCore
import Testing

/// The rules over the open set that the app's open folders follow: which
/// are read and watched, which went, what the fold keys do.
@Suite struct TreeFoldsTests {
    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    private func entry(_ path: String, _ kind: Entry.Kind = .folder, hidden: Bool = false) -> Entry {
        let url = URL(fileURLWithPath: path, isDirectory: kind == .folder)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: nil, modified: nil, isHidden: hidden,
            typeDescription: "")
    }

    private func paths(_ urls: Set<URL>) -> [String] { urls.map(\.standardizedFileURL.path).sorted() }

    // MARK: Which open folders are read and watched

    /// /t has a and c; a is open and read (a/b inside, open); c is closed
    /// but remembers c/d open; x is open and no longer in /t.
    private var open: Set<URL> { [folder("/t/a"), folder("/t/a/b"), folder("/t/c/d"), folder("/t/x")] }
    private var children: [URL: [Entry]] {
        [folder("/t"): [entry("/t/a"), entry("/t/c")], folder("/t/a"): [entry("/t/a/b"), entry("/t/a/f", .file)]]
    }

    @Test func onlyTheOpenFoldersThatShowAreRead() {
        let reachable = Tree.reachable(open: open, root: folder("/t"), children: children)
        // c/d waits for c to open again; x is no item of /t.
        #expect(paths(reachable) == ["/t/a", "/t/a/b"])
    }

    @Test func aFolderInsideOneStillBeingReadIsReadToo() {
        // a's listing hasn't come: what is open inside it is read meanwhile.
        let reachable = Tree.reachable(
            open: [folder("/t/a"), folder("/t/a/b")], root: folder("/t"), children: [folder("/t"): [entry("/t/a")]])
        #expect(paths(reachable) == ["/t/a", "/t/a/b"])
    }

    // MARK: Which open folders went

    @Test func aFolderNoLongerInItsParentsListingWentAndEverythingOpenInsideIt() {
        let gone = Tree.vanished(
            in: folder("/t"), listing: [entry("/t/c")],
            open: [folder("/t/a"), folder("/t/a/b"), folder("/t/a/b/deep"), folder("/t/c"), folder("/t/c/d")])
        #expect(paths(gone) == ["/t/a", "/t/a/b", "/t/a/b/deep"])
    }

    /// A folder closed in the list keeps what was open inside it (← is not
    /// ⌥←): that is not a folder that went.
    @Test func whatIsOpenInsideAClosedFolderStays() {
        let gone = Tree.vanished(in: folder("/t"), listing: [entry("/t/c")], open: [folder("/t/c/d")])
        #expect(gone.isEmpty)
    }

    /// Renamed by another program: the old name went; a file or a package
    /// of the old name is no folder to keep open.
    @Test func aFolderThatBecameSomethingElseWent() {
        let gone = Tree.vanished(
            in: folder("/t"), listing: [entry("/t/a", .package), entry("/t/b", .file), entry("/t/new")],
            open: [folder("/t/a"), folder("/t/b"), folder("/t/old")])
        #expect(paths(gone) == ["/t/a", "/t/b", "/t/old"])
    }

    @Test func onlyTheFolderReadIsAskedAbout() {
        // /t/a's listing says nothing of what is open in /t or in /u.
        let gone = Tree.vanished(
            in: folder("/t/a"), listing: [entry("/t/a/b")],
            open: [folder("/t/a/b"), folder("/t/z"), folder("/u/v"), folder("/t/a/gone/")])
        #expect(paths(gone) == ["/t/a/gone"])
    }

    @Test func spellingsOfOneFolderAreOne() {
        let gone = Tree.vanished(
            in: URL(fileURLWithPath: "/t/x/.."), listing: [entry("/t/a")], open: [URL(fileURLWithPath: "/t/a/")])
        #expect(gone.isEmpty)
    }

    // MARK: A folder renamed in the app

    @Test func aRenamedFolderStaysOpenWithWhatIsOpenInsideIt() {
        let open: Set<URL> = [folder("/t/a"), folder("/t/a/b"), folder("/t/ab"), folder("/t/c")]
        let moved = Tree.remapped(open, from: URL(fileURLWithPath: "/t/a"), to: folder("/t/z"))
        // "/t/ab" only starts the same: another folder.
        #expect(paths(moved) == ["/t/ab", "/t/c", "/t/z", "/t/z/b"])
        #expect(Tree.remapped(open, from: folder("/t/q"), to: folder("/t/r")) == open)
    }

    // MARK: What an operation takes

    private func row(_ path: String, depth: Int, kind: Entry.Kind = .file) -> TreeItem {
        .row(TreeRow(entry: entry(path, kind), depth: depth, fold: .none, isContext: false))
    }

    private func index(_ items: [TreeItem]) -> [URL: Int] {
        var index: [URL: Int] = [:]
        for (place, item) in items.enumerated() { if case .row(let row) = item { index[row.entry.url] = place } }
        return index
    }

    @Test func operandsThroughTheIndexAreTheOperands() {
        let items: [TreeItem] = [
            row("/t/a", depth: 0, kind: .folder), row("/t/a/x", depth: 1), .loading(under: entry("/t/b").url, depth: 1),
            row("/t/m", depth: 0), row("/t/z", depth: 0),
        ]
        let rows = index(items)
        let selections: [Set<URL>] = [
            [], [entry("/t/z", .file).url, entry("/t/m", .file).url],
            [entry("/t/a").url, entry("/t/a/x", .file).url, entry("/t/z", .file).url],
            [entry("/t/a/x", .file).url], [entry("/t/m", .file).url, entry("/t/gone", .file).url],
        ]
        for selection in selections {
            #expect(Tree.operands(of: selection, in: items, index: rows) == Tree.operands(of: selection, in: items))
        }
        // Rows at depth 0 only: in row order.
        #expect(Tree.operands(of: [entry("/t/z", .file).url, entry("/t/a").url], in: items, index: rows).map(\.path)
            == ["/t/a", "/t/z"])
    }

    // MARK: The fold keys

    private func fold(_ path: String, depth: Int, _ fold: TreeRow.Fold, kind: Entry.Kind = .folder) -> TreeItem {
        .row(TreeRow(entry: entry(path, kind), depth: depth, fold: fold, isContext: false))
    }

    /// /t: a (open: a/x a file, a/b open: a/b/y), c (closed with contents),
    /// d (no chevron), e (being read), f.txt.
    private var tree: [TreeItem] {
        [
            fold("/t/a", depth: 0, .open), fold("/t/a/b", depth: 1, .open), fold("/t/a/b/y", depth: 2, .none, kind: .file),
            fold("/t/a/x", depth: 1, .none, kind: .file), fold("/t/c", depth: 0, .closed), fold("/t/d", depth: 0, .none),
            fold("/t/e", depth: 0, .loading), .loading(under: entry("/t/e").url, depth: 1),
            fold("/t/f.txt", depth: 0, .none, kind: .file),
        ]
    }

    private func url(_ path: String, folder: Bool = true) -> URL { entry(path, folder ? .folder : .file).url }

    private func right(_ selected: [URL], everything: Bool = false) -> Tree.FoldAction? {
        Tree.right(selection: Set(selected), in: tree, index: index(tree), everything: everything)
    }

    private func left(_ selected: [URL], open: Set<URL> = [], everything: Bool = false) -> Tree.FoldAction? {
        Tree.left(selection: Set(selected), in: tree, index: index(tree), open: open, everything: everything)
    }

    @Test func rightOpensAClosedFolderAndGoesIntoAnOpenOne() {
        #expect(right([url("/t/c")]) == .open(url("/t/c")))
        #expect(right([url("/t/a")]) == .select(url("/t/a/b")))
        #expect(right([url("/t/a/b")]) == .select(url("/t/a/b/y", folder: false)))
        // No chevron (empty, or not looked into yet), being read, a file,
        // nothing or two selected: nothing.
        #expect(right([url("/t/d")]) == nil)
        #expect(right([url("/t/e")]) == nil)
        #expect(right([url("/t/f.txt", folder: false)]) == nil)
        #expect(right([]) == nil)
        #expect(right([url("/t/c"), url("/t/d")]) == nil)
        // A URL that is no row (inside a closed folder, gone).
        #expect(right([url("/t/c/inner")]) == nil)
    }

    @Test func optionRightOpensEverythingInsideAFolderWithAChevron() {
        #expect(right([url("/t/c")], everything: true) == .openAll(url("/t/c")))
        #expect(right([url("/t/a")], everything: true) == .openAll(url("/t/a")))
        #expect(right([url("/t/e")], everything: true) == .openAll(url("/t/e")))
        #expect(right([url("/t/d")], everything: true) == nil)
        #expect(right([url("/t/f.txt", folder: false)], everything: true) == nil)
    }

    @Test func leftClosesAnOpenFolderOrGoesToTheParentRow() {
        #expect(left([url("/t/a")]) == .close(url("/t/a")))
        #expect(left([url("/t/e")]) == .close(url("/t/e")))
        #expect(left([url("/t/a/b/y", folder: false)]) == .select(url("/t/a/b")))
        #expect(left([url("/t/a/x", folder: false)]) == .select(url("/t/a")))
        // At the top: nowhere to go.
        #expect(left([url("/t/c")]) == nil)
        #expect(left([url("/t/f.txt", folder: false)]) == nil)
        #expect(left([url("/t/a"), url("/t/c")]) == nil)
    }

    @Test func optionLeftClosesEverythingInside() {
        #expect(left([url("/t/a")], everything: true) == .closeAll(url("/t/a")))
        // Closed, but remembering what was open inside it: that is forgotten.
        #expect(left([url("/t/c")], open: [url("/t/c/z")], everything: true) == .closeAll(url("/t/c")))
        // Nothing open in it: as ←.
        #expect(left([url("/t/c")], everything: true) == nil)
        #expect(left([url("/t/a/x", folder: false)], everything: true) == .select(url("/t/a")))
    }

    @Test func closingKeepsOrForgetsWhatWasOpenInside() {
        let open: Set<URL> = [url("/t/a"), url("/t/a/b"), url("/t/a/b/c"), url("/t/ab"), url("/t/z")]
        #expect(paths(Tree.closing(url("/t/a"), everything: false, open: open)) == ["/t/a/b", "/t/a/b/c", "/t/ab", "/t/z"])
        #expect(paths(Tree.closing(url("/t/a"), everything: true, open: open)) == ["/t/ab", "/t/z"])
    }

    /// Closing a folder with something selected inside it: the folder is
    /// selected instead, and the rest of the selection stays.
    @Test func whatWasSelectedInsideAClosedFolderBecomesTheFolder() {
        let selection: Set<URL> = [url("/t/a/x", folder: false), url("/t/a/b/y", folder: false), url("/t/c")]
        #expect(paths(Tree.selection(selection, closing: url("/t/a"))) == ["/t/a", "/t/c"])
        #expect(Tree.selection([url("/t/c")], closing: url("/t/a")) == [url("/t/c")])
        // A context folder under a filter is not selected in their stead
        // (final review A3): ⌘⌫ would take everything in it.
        #expect(paths(Tree.selection(selection, closing: url("/t/a"), asContext: true)) == ["/t/c"])
    }

    @Test func theRowsOutsideAFolderCountNothingOfItsContents() {
        #expect(Tree.rowsOutside(url("/t/a"), in: tree) == 5)  // a c d e f.txt
        #expect(Tree.rowsOutside(url("/t/a/b"), in: tree) == 7)
        #expect(Tree.rowsOutside(url("/t/e"), in: tree) == 8)  // the loading line is no row
        #expect(Tree.rowsOutside(url("/t/nowhere"), in: tree) == 8)
        for folder in ["/t/a", "/t/a/b", "/t/e", "/t/c", "/t/nowhere"] {
            #expect(Tree.rowsOutside(url(folder), in: tree, index: index(tree)) == Tree.rowsOutside(url(folder), in: tree))
        }
    }

    @Test func theLimitIsSaidAsTheRowLimit() {
        #expect(Tree.stoppedAtLimit == "Stopped at 10,000 rows")
        #expect(Tree.rowLimit == 10_000)
    }

    @Test func operandPlacesAreTheOperandsByPlace() {
        let items = tree
        let rows = index(items)
        let selections: [Set<URL>] = [
            [url("/t/a"), url("/t/a/b/y", folder: false), url("/t/c")], [url("/t/a/b"), url("/t/a/b/y", folder: false)],
            [url("/t/a/x", folder: false), url("/t/f.txt", folder: false)], [],
        ]
        for selection in selections {
            let places = selection.compactMap { rows[$0] }.sorted()
            let byPlace = Tree.operandPlaces(places, in: items).compactMap { place -> URL? in
                if case .row(let row) = items[place] { row.entry.url } else { nil }
            }
            #expect(byPlace == Tree.operands(of: selection, in: items))
        }
    }

    // MARK: ⌥→, step by step

    @Test func optionRightAddsWhatItFoundAndGoesOnWhileReadsCanOpenMore() {
        let found = [url("/t/a"), url("/t/a/b"), url("/t/a/c")]
        let first = Tree.openAllStep(found: found, stoppedAtLimit: false, open: [url("/t/a")], refused: [], reading: [])
        #expect(first.open.map(\.path) == ["/t/a/b", "/t/a/c"])
        #expect(first.goesOn && !first.stoppedAtLimit)
        // b and c are being read: nothing new yet, it waits for them.
        let waiting = Tree.openAllStep(
            found: found, stoppedAtLimit: false, open: Set(found), refused: [], reading: [url("/t/a/b")])
        #expect(waiting.open.isEmpty && waiting.goesOn)
    }

    @Test func optionRightEndsWhenAStepAddsNothingAndNothingIsOnItsWay() {
        let found = [url("/t/a"), url("/t/a/b")]
        // Everything read: done.
        let done = Tree.openAllStep(found: found, stoppedAtLimit: false, open: Set(found), refused: [], reading: [])
        #expect(done.open.isEmpty && !done.goesOn)
        // b was unreadable (it closed, its chevron a no): not opened again, and it ends.
        let refused = Tree.openAllStep(
            found: found, stoppedAtLimit: false, open: [url("/t/a")], refused: [url("/t/a/b/")], reading: [])
        #expect(refused.open.isEmpty && !refused.goesOn)
        // At the limit: what fits is added, and it stops, saying so.
        let limit = Tree.openAllStep(found: found, stoppedAtLimit: true, open: [url("/t/a")], refused: [], reading: [])
        #expect(limit.open.map(\.path) == ["/t/a/b"])
        #expect(!limit.goesOn && limit.stoppedAtLimit)
    }
}
