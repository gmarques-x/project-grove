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
}
