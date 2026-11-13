import Foundation
import GroveExplorerCore
import Testing

@Suite struct TreeTests {
    // MARK: Fixtures (in memory, nothing on disk)

    private func url(_ path: String, folder: Bool = false) -> URL {
        URL(fileURLWithPath: path, isDirectory: folder)
    }

    private func entry(
        _ path: String, _ kind: Entry.Kind = .file, size: Int64? = nil, hidden: Bool = false
    ) -> Entry {
        let url = url(path)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: size, modified: nil,
            isHidden: hidden, typeDescription: kind == .folder ? "Folder" : "Document")
    }

    private func input(
        root: [Entry], children: [URL: [Entry]] = [:], open: Set<URL> = [],
        hasContents: [URL: Bool] = [:], sort: GroveExplorerCore.SortOrder = .byName,
        folderSizes: [URL: Int64] = [:], filter: String = "", showHidden: Bool = false,
        closedUnderFilter: Set<URL> = []
    ) -> TreeInput {
        TreeInput(
            root: root, children: children, open: open, hasContents: hasContents, sort: sort,
            folderSizes: folderSizes, filter: filter, showHidden: showHidden, closedUnderFilter: closedUnderFilter)
    }

    /// One line per item: "  name fold" (two spaces per level), "  ···" for a loading line,
    /// a "~" after the name for a context row.
    private func lines(_ items: [TreeItem]) -> [String] {
        items.map { item in
            switch item {
            case .row(let row):
                let fold: String
                switch row.fold {
                case .none: fold = ""
                case .closed: fold = " >"
                case .open: fold = " v"
                case .loading: fold = " …"
                }
                return String(repeating: "  ", count: row.depth) + row.entry.name
                    + (row.isContext ? "~" : "") + fold
            case .loading(_, let depth):
                return String(repeating: "  ", count: depth) + "···"
            }
        }
    }

    /// The tree of Step 1. `/t` holds: folder `a` (open, read: file `a1`,
    /// folder `a2` closed with contents, a hidden file), `b` (open, not
    /// read), `c` (closed, has contents), `d` (closed, empty), `e` (not
    /// looked into), a package and a link to a folder (both marked open and
    /// with contents, which they must not get), two files and a hidden file.
    /// `open` holds a stale folder that is no entry of its parent. Keys are
    /// spelled with a trailing slash, as a folder URL may be.
    private func basicTree(
        sort: GroveExplorerCore.SortOrder = .byName, folderSizes: [URL: Int64] = [:],
        showHidden: Bool = false
    ) -> TreeInput {
        input(
            root: [
                entry("/t/z.txt", size: 5), entry("/t/e", .folder), entry("/t/App.app", .package),
                entry("/t/c", .folder), entry("/t/m.txt", size: 50), entry("/t/a", .folder),
                entry("/t/L", .symlink(toFolder: true)), entry("/t/d", .folder), entry("/t/b", .folder),
                entry("/t/.DS_Store", hidden: true),
            ],
            children: [
                url("/t/a/", folder: true): [
                    entry("/t/a/a1", size: 7), entry("/t/a/hidden.txt", size: 1, hidden: true),
                    entry("/t/a/a2", .folder),
                ],
                url("/t/App.app/", folder: true): [entry("/t/App.app/Contents", .folder)],
                url("/t/gone/", folder: true): [entry("/t/gone/x")],
            ],
            open: [
                url("/t/a/", folder: true), url("/t/b/", folder: true),
                url("/t/App.app/", folder: true), url("/t/L/", folder: true),
                url("/t/gone/", folder: true),
            ],
            hasContents: [
                url("/t/a2/", folder: true): false,  // another folder's answer, by name only
                url("/t/a/a2/", folder: true): true, url("/t/c/", folder: true): true,
                url("/t/d/", folder: true): false, url("/t/App.app/", folder: true): true,
                url("/t/L/", folder: true): true,
            ],
            sort: sort, folderSizes: folderSizes, showHidden: showHidden)
    }

    // MARK: Step 1: the rows

    @Test func theRowsAreTheTreeInOrderWithTheirDepthsAndFolds() {
        #expect(lines(Tree.items(basicTree())) == [
            "a v",
            "  a2 >",
            "  a1",
            "b …",
            "  ···",
            "c >",
            "d",
            "e",
            "L",
            "App.app",
            "m.txt",
            "z.txt",
        ])
    }

    @Test func aFolderBeingReadHasOneLoadingLineBeneathItAtTheChildsDepth() {
        let items = Tree.items(basicTree())
        let b = items.firstIndex { if case .row(let row) = $0 { row.entry.name == "b" } else { false } }!
        #expect(items[b + 1] == .loading(under: url("/t/b"), depth: 1))
        #expect(items[b + 1].id != items[b].id)
    }

    @Test func childrenSortAmongThemselvesBySizeDescendingFoldersOnTop() {
        let sizes: [URL: Int64] = [
            url("/t/a"): 100, url("/t/b"): 300, url("/t/c"): 10, url("/t/d"): 200,
            url("/t/a/a2"): 1,
        ]
        let items = Tree.items(basicTree(
            sort: SortOrder(column: .size, ascending: false), folderSizes: sizes))
        #expect(lines(items) == [
            "b …",
            "  ···",
            "d",
            "a v",
            "  a2 >",
            "  a1",
            "c >",
            "e",
            "L",
            "m.txt",
            "z.txt",
            "App.app",
        ])
    }

    @Test func childrenSortByNameDescendingFoldersStillOnTop() {
        let items = Tree.items(basicTree(sort: SortOrder(column: .name, ascending: false)))
        #expect(lines(items) == [
            "L",
            "e",
            "d",
            "c >",
            "b …",
            "  ···",
            "a v",
            "  a2 >",
            "  a1",
            "z.txt",
            "m.txt",
            "App.app",
        ])
    }

    @Test func hiddenItemsShowAtEveryLevelOnlyWithShowHidden() {
        let shown = lines(Tree.items(basicTree(showHidden: true)))
        #expect(shown.contains("  hidden.txt"))
        #expect(shown.contains(".DS_Store"))
        #expect(shown.count == 14)
        let rows = Tree.items(basicTree(showHidden: true)).compactMap { item -> TreeRow? in
            if case .row(let row) = item { row } else { nil }
        }
        #expect(rows.first { $0.entry.name == "hidden.txt" }?.depth == 1)
    }

    @Test func anOpenFolderWhoseItemsAreAllHiddenHasNoChevronAndNoRows() {
        let tree = input(
            root: [entry("/t/a", .folder)],
            children: [url("/t/a"): [entry("/t/a/.x", hidden: true)]],
            open: [url("/t/a")], hasContents: [url("/t/a"): true])
        #expect(lines(Tree.items(tree)) == ["a"])
        var shown = tree
        shown.showHidden = true
        #expect(lines(Tree.items(shown)) == ["a v", "  .x"])
    }

    @Test func aStaleOpenFolderContributesNothing() {
        // `/t/gone` is open and read but no entry of `/t`; `App.app` is open
        // and read but a package.
        let paths = Tree.items(basicTree()).map { item -> String in
            switch item {
            case .row(let row): row.entry.url.path
            case .loading(let folder, _): folder.path
            }
        }
        #expect(!paths.contains { $0.hasPrefix("/t/gone") || $0.hasPrefix("/t/App.app/") })
        #expect(paths.count == 12)
    }

    // MARK: Step 2: the filter

    /// `/f`: a match at depth 0 (two files), 1 (`docs/reading`, open, with
    /// a match `bread.txt` and a non-match inside) and 3
    /// (`docs/deep/inner/thread.txt`); an open folder with no match
    /// (`empty`); a closed folder whose listing is known (`box`).
    private func filterTree(filter: String) -> TreeInput {
        input(
            root: [
                entry("/f/zzz.txt"), entry("/f/readme.md"), entry("/f/docs", .folder),
                entry("/f/Réadable.txt"), entry("/f/empty", .folder), entry("/f/box", .folder),
            ],
            children: [
                url("/f/docs"): [
                    entry("/f/docs/notes.txt"), entry("/f/docs/deep", .folder),
                    entry("/f/docs/reading", .folder),
                ],
                url("/f/docs/deep"): [entry("/f/docs/deep/inner", .folder)],
                url("/f/docs/deep/inner"): [
                    entry("/f/docs/deep/inner/thread.txt"), entry("/f/docs/deep/inner/other.txt"),
                ],
                url("/f/docs/reading"): [
                    entry("/f/docs/reading/milk.txt"), entry("/f/docs/reading/bread.txt"),
                ],
                url("/f/empty"): [entry("/f/empty/x.txt")],
                url("/f/box"): [entry("/f/box/readme2.txt")],
            ],
            open: [
                url("/f/docs"), url("/f/docs/deep"), url("/f/docs/deep/inner"),
                url("/f/docs/reading"), url("/f/empty"),
            ],
            hasContents: [url("/f/box"): true],
            filter: filter)
    }

    @Test func theUnfilteredTreeOfTheFilterFixture() {
        #expect(lines(Tree.items(filterTree(filter: ""))) == [
            "box >",
            "docs v",
            "  deep v",
            "    inner v",
            "      other.txt",
            "      thread.txt",
            "  reading v",
            "    bread.txt",
            "    milk.txt",
            "  notes.txt",
            "empty v",
            "  x.txt",
            "Réadable.txt",
            "readme.md",
            "zzz.txt",
        ])
    }

    @Test func aFilterKeepsMatchesAtAnyDepthAndTheirAncestorsAsContext() {
        #expect(lines(Tree.items(filterTree(filter: "read"))) == [
            "docs~ v",
            "  deep~ v",
            "    inner~ v",
            "      thread.txt",
            "  reading v",
            "    bread.txt",
            "Réadable.txt",
            "readme.md",
        ])
    }

    /// The fixture under "read" with `folder` closed as the app closes it:
    /// out of `open` (what is open inside it stays there), its listing and
    /// those beneath it gone; `closedUnderFilter` as given.
    private func closedUnderRead(_ folder: String, remembered: Bool) -> TreeInput {
        var tree = filterTree(filter: "read")
        tree.open.remove(url(folder))
        tree.children = tree.children.filter { !($0.key.path == folder || $0.key.path.hasPrefix(folder + "/")) }
        tree.closedUnderFilter = remembered ? [url(folder, folder: true)] : []
        return tree
    }

    /// The owner, 2026-11-13: under a filter, a folder kept only as context
    /// that the user closes stays, closed, its name quiet, until the filter
    /// changes; the matches inside are gone. (Before, it went with them.)
    @Test func aContextFolderClosedUnderAFilterStaysAsAClosedRow() {
        #expect(lines(Tree.items(closedUnderRead("/f/docs/deep", remembered: true))) == [
            "docs~ v",
            "  deep~ >",
            "  reading v",
            "    bread.txt",
            "Réadable.txt",
            "readme.md",
        ])
        // Deeper: its ancestors stay as context for it.
        #expect(lines(Tree.items(closedUnderRead("/f/docs/deep/inner", remembered: true))) == [
            "docs~ v",
            "  deep~ v",
            "    inner~ >",
            "  reading v",
            "    bread.txt",
            "Réadable.txt",
            "readme.md",
        ])
        // At the top: the folder alone.
        #expect(lines(Tree.items(closedUnderRead("/f/docs", remembered: true))) == [
            "docs~ >", "Réadable.txt", "readme.md",
        ])
        // Not remembered as closed under the filter, it goes, as a folder with no match.
        #expect(lines(Tree.items(closedUnderRead("/f/docs/deep", remembered: false))) == [
            "docs~ v", "  reading v", "    bread.txt", "Réadable.txt", "readme.md",
        ])
        // The status bar counts it as context, not as a match.
        #expect(Tree.counts(Tree.items(closedUnderRead("/f/docs/deep", remembered: true))).rows == 4)
    }

    /// Opened again (its chevron), the matches inside it come back (the set
    /// still names it: an open folder is open); while it is read it is not
    /// gone, it shows its loading line, as context.
    @Test func aContextFolderReopenedUnderTheFilterShowsItsMatchesAgain() {
        var reopened = filterTree(filter: "read")
        reopened.closedUnderFilter = [url("/f/docs/deep/", folder: true)]
        #expect(Tree.items(reopened) == Tree.items(filterTree(filter: "read")))
        var reading = closedUnderRead("/f/docs/deep", remembered: true)
        reading.open.insert(url("/f/docs/deep"))
        #expect(lines(Tree.items(reading)).prefix(3) == ["docs~ v", "  deep~ …", "    ···"])
    }

    /// Without a filter the set means nothing: the folder is closed as any.
    @Test func withoutAFilterAFolderClosedUnderOneIsClosedAsUsual() {
        var cleared = closedUnderRead("/f/docs/deep", remembered: true)
        cleared.filter = ""
        var plain = cleared
        plain.closedUnderFilter = []
        #expect(Tree.items(cleared) == Tree.items(plain))
        #expect(lines(Tree.items(cleared)).contains("  deep"))
    }

    @Test func everyWordMustMatchCaseAndAccentsIgnored() {
        #expect(lines(Tree.items(filterTree(filter: "  READ .md "))) == ["readme.md"])
        #expect(lines(Tree.items(filterTree(filter: "réad TXT"))) == [
            "docs~ v",
            "  deep~ v",
            "    inner~ v",
            "      thread.txt",
            "  reading~ v",
            "    bread.txt",
            "Réadable.txt",
        ])
        #expect(Tree.items(filterTree(filter: "nothing like it")).isEmpty)
    }

    @Test func theFilterNeverShowsWhatIsInAFolderThatIsNotOpen() {
        let shown = lines(Tree.items(filterTree(filter: "readme2")))
        #expect(shown.isEmpty)
    }

    @Test func underAFilterAFolderBeingReadShowsOnlyIfItMatches() {
        let tree = input(
            root: [entry("/l/reads", .folder), entry("/l/other", .folder)],
            open: [url("/l/reads"), url("/l/other")], filter: "read")
        let items = Tree.items(tree)
        #expect(lines(items) == ["reads …", "  ···"])
    }

    /// A matching open folder whose read has landed and none of whose
    /// items match: open, with nothing beneath it.
    @Test func aMatchingOpenFolderWithNoMatchingItemShowsOpenAndNothingBeneath() {
        let tree = input(
            root: [entry("/l/reads", .folder), entry("/l/other.txt")],
            children: [url("/l/reads"): [entry("/l/reads/a.txt"), entry("/l/reads/b", .folder)]],
            open: [url("/l/reads")], filter: "read")
        let items = Tree.items(tree)
        #expect(lines(items) == ["reads v"])
        #expect(Tree.counts(items).rows == 1)
    }

    /// Totals are found however a folder's URL is spelled, as the other
    /// keys of `TreeInput` are.
    @Test func aFolderSizeKeyedWithATrailingSlashIsFound() {
        let tree = input(
            root: [entry("/s/a", .folder), entry("/s/b", .folder), entry("/s/c", .folder)],
            sort: SortOrder(column: .size, ascending: false),
            folderSizes: [
                url("/s/a/", folder: true): 1, url("/s/b/", folder: true): 300,
                url("/s/./c", folder: true): 20,
            ])
        // Not found, they would go by name: a, b, c.
        #expect(lines(Tree.items(tree)) == ["b", "c", "a"])
    }

    @Test func theStatusCountsMatchesAgainstTheRowsThatWouldShowUnfiltered() {
        let filtered = Tree.itemsAndUnfilteredCount(filterTree(filter: "read"))
        let counts = Tree.counts(filtered.items)
        // thread.txt, reading, bread.txt, Réadable.txt, readme.md: "5 of 15".
        #expect(counts.rows == 5)
        #expect(filtered.unfilteredRows == 15)
        // Open folders among the rows showing, context ones included.
        #expect(counts.foldersOpen == 4)

        // Unfiltered, the two numbers agree, and they agree with `items`.
        let plain = Tree.itemsAndUnfilteredCount(filterTree(filter: ""))
        #expect(plain.items == Tree.items(filterTree(filter: "")))
        #expect(Tree.counts(plain.items).rows == 15)
        #expect(plain.unfilteredRows == 15)
        #expect(Tree.counts(plain.items).foldersOpen == 5)
    }

    @Test func aFolderBeingReadCountsAsOpenAndItsLoadingLineIsNoRow() {
        let counts = Tree.counts(Tree.items(basicTree()))
        #expect(counts.rows == 11)
        #expect(counts.foldersOpen == 2)  // a, and b still being read
        #expect(Tree.itemsAndUnfilteredCount(basicTree()).unfilteredRows == 11)
    }

    // MARK: Step 3: operands

    @Test func aSelectedFolderTakesItsSelectedItemsWithIt() {
        let items = Tree.items(basicTree())
        #expect(Tree.operands(of: [url("/t/z.txt"), url("/t/a/a1"), url("/t/a")], in: items)
            == [url("/t/a"), url("/t/z.txt")])
    }

    @Test func siblingsInsideAFolderAreBothOperandsInRowOrder() {
        let items = Tree.items(basicTree())
        #expect(Tree.operands(of: [url("/t/a/a1"), url("/t/a/a2")], in: items)
            == [url("/t/a/a2"), url("/t/a/a1")])
    }

    @Test func aDeepItemIsLeftOutUnderAnySelectedAncestor() {
        let items = Tree.items(filterTree(filter: ""))
        #expect(Tree.operands(
            of: [url("/f/docs/deep/inner/thread.txt"), url("/f/docs"), url("/f/empty/x.txt")], in: items)
            == [url("/f/docs"), url("/f/empty/x.txt")])
    }

    @Test func aSelectedURLThatIsNoRowIsDropped() {
        let items = Tree.items(basicTree())
        // Inside a folder still being read, inside a stale one, nowhere.
        #expect(Tree.operands(
            of: [url("/t/b/x"), url("/t/gone/x"), url("/elsewhere"), url("/t/m.txt")], in: items)
            == [url("/t/m.txt")])
        #expect(Tree.operands(of: [], in: items).isEmpty)
    }

    // MARK: Step 4: ⌥→, ←, orphans

    @Test func openAllOpensBreadthFirst() {
        let children: [URL: [Entry]] = [
            url("/r/top"): [
                entry("/r/top/f1", .folder), entry("/r/top/file"), entry("/r/top/f2", .folder),
            ],
            url("/r/top/f1"): [
                entry("/r/top/f1/g1", .folder), entry("/r/top/f1/App.app", .package),
                entry("/r/top/f1/link", .symlink(toFolder: true)),
            ],
            url("/r/top/f2"): [entry("/r/top/f2/g2", .folder), entry("/r/top/f2/none", .folder)],
            url("/r/top/f1/g1"): [entry("/r/top/f1/g1/h1", .folder)],
            url("/r/top/f2/none"): [],  // known empty: left closed
            // g2 and h1 are not read yet: opened, nothing known beneath.
        ]
        let result = Tree.openAll(under: url("/r/top"), known: children, showing: 20, showHidden: false, sort: .byName, folderSizes: [:])
        #expect(result.open == [
            url("/r/top"), url("/r/top/f1"), url("/r/top/f2"),
            url("/r/top/f1/g1"), url("/r/top/f2/g2"), url("/r/top/f1/g1/h1"),
        ])
        #expect(!result.stoppedAtLimit)
    }

    @Test func openAllStopsBeforeTheTabWouldShowMoreThanTheLimit() {
        let big = (0..<30).map { entry("/r/big/item \($0)") }
        let children = [url("/r/big"): big]
        let stopped = Tree.openAll(under: url("/r/big"), known: children, showing: 9_990, showHidden: false, sort: .byName, folderSizes: [:])
        #expect(stopped.open.isEmpty)
        #expect(stopped.stoppedAtLimit)

        let fits = Tree.openAll(under: url("/r/big"), known: children, showing: 9_970, showHidden: false, sort: .byName, folderSizes: [:])
        #expect(fits.open == [url("/r/big")])
        #expect(!fits.stoppedAtLimit)
    }

    @Test func openAllStopsPartWayAndKeepsWhatFits() {
        // top: 2 folders; each of them: 10 files.
        var children: [URL: [Entry]] = [
            url("/r/top"): [entry("/r/top/p", .folder), entry("/r/top/q", .folder)],
        ]
        children[url("/r/top/p")] = (0..<10).map { entry("/r/top/p/\($0)") }
        children[url("/r/top/q")] = (0..<10).map { entry("/r/top/q/\($0)") }
        let result = Tree.openAll(under: url("/r/top"), known: children, showing: Tree.rowLimit - 15, showHidden: false,
            sort: .byName, folderSizes: [:])
        #expect(result.open == [url("/r/top"), url("/r/top/p")])
        #expect(result.stoppedAtLimit)
    }

    @Test func openAllLeavesHiddenFoldersClosedAndUncountedUnlessShown() {
        let children: [URL: [Entry]] = [
            url("/r/top"): [entry("/r/top/.git", .folder, hidden: true), entry("/r/top/src", .folder)],
            url("/r/top/.git"): (0..<50).map { entry("/r/top/.git/\($0)") },
        ]
        // Hidden items left out: top adds one row (src), which fits; .git stays closed.
        let hiding = Tree.openAll(
            under: url("/r/top"), known: children, showing: Tree.rowLimit - 1, showHidden: false, sort: .byName,
            folderSizes: [:])
        #expect(hiding.open == [url("/r/top"), url("/r/top/src")])
        #expect(!hiding.stoppedAtLimit)

        // Shown: top adds two rows, one too many.
        let showing = Tree.openAll(
            under: url("/r/top"), known: children, showing: Tree.rowLimit - 1, showHidden: true, sort: .byName,
            folderSizes: [:])
        #expect(showing.open.isEmpty)
        #expect(showing.stoppedAtLimit)
    }

    /// Each level's folders are opened in the order the tab shows them, so
    /// a ⌥→ cut short by the limit opens the ones at the top.
    @Test func openAllOpensEachLevelInTheTabsOrder() {
        let children: [URL: [Entry]] = [
            url("/r/top"): [
                entry("/r/top/b", .folder), entry("/r/top/file"), entry("/r/top/c", .folder),
                entry("/r/top/a", .folder),
            ],
            url("/r/top/b"): [entry("/r/top/b/b2", .folder), entry("/r/top/b/b1", .folder)],
        ]
        func opened(_ sort: GroveExplorerCore.SortOrder, sizes: [URL: Int64] = [:]) -> [String] {
            Tree.openAll(
                under: url("/r/top"), known: children, showing: 0, showHidden: false, sort: sort,
                folderSizes: sizes
            ).open.map(\.lastPathComponent)
        }
        #expect(opened(.byName) == ["top", "a", "b", "c", "b1", "b2"])
        #expect(opened(SortOrder(column: .name, ascending: false)) == ["top", "c", "b", "a", "b2", "b1"])
        // By size, the totals keyed however a folder's URL is spelled.
        let sizes: [URL: Int64] = [
            url("/r/top/a/", folder: true): 1, url("/r/top/b/", folder: true): 3,
            url("/r/top/c/", folder: true): 2,
        ]
        #expect(opened(SortOrder(column: .size, ascending: false), sizes: sizes)
            == ["top", "b", "c", "a", "b1", "b2"])
    }

    /// The first folder that doesn't fit ends ⌥→: a later one that would
    /// fit stays closed, so what opens is a top part of the tab's order.
    @Test func openAllStopsAtTheFirstFolderThatDoesNotFitAndOpensNoLaterOne() {
        var children: [URL: [Entry]] = [
            url("/r/top"): [entry("/r/top/p", .folder), entry("/r/top/q", .folder)],
        ]
        children[url("/r/top/p")] = (0..<10).map { entry("/r/top/p/\($0)") }
        children[url("/r/top/q")] = [entry("/r/top/q/only")]
        // top adds 2 rows (fits), p would add 10 (doesn't), q 1 (would).
        let result = Tree.openAll(
            under: url("/r/top"), known: children, showing: Tree.rowLimit - 5, showHidden: false,
            sort: .byName, folderSizes: [:])
        #expect(result.open == [url("/r/top")])
        #expect(result.stoppedAtLimit)
    }

    @Test func parentRowIsTheRowOneLevelUp() {
        let items = Tree.items(filterTree(filter: ""))
        #expect(Tree.parentRow(of: url("/f/docs/deep/inner"), in: items) == url("/f/docs/deep"))
        #expect(Tree.parentRow(of: url("/f/docs/deep/inner/thread.txt"), in: items)
            == url("/f/docs/deep/inner"))
        #expect(Tree.parentRow(of: url("/f/docs/notes.txt"), in: items) == url("/f/docs"))
        #expect(Tree.parentRow(of: url("/f/docs/deep/", folder: true), in: items) == url("/f/docs"))
        #expect(Tree.parentRow(of: url("/f/docs"), in: items) == nil)
        #expect(Tree.parentRow(of: url("/f/nowhere/x"), in: items) == nil)
    }

    @Test func orphansAreOpenFoldersUnderAClosedOrVanishedAncestor() {
        let open: Set<URL> = [
            url("/t/a"), url("/t/a/x/", folder: true),  // reachable
            url("/t/a/gone"),                           // no longer in a's listing
            url("/t/a/gone/deeper"),                    // under it
            url("/t/b/y"), url("/t/b/y/z"),             // b is closed
            url("/t/c"), url("/t/c/q"),                 // c is still being read: kept
            url("/t/a/pkg.app"),                        // now a package
            url("/elsewhere/z"),                        // not under the tab's folder
        ]
        let children: [URL: [Entry]] = [
            url("/t/a/", folder: true): [entry("/t/a/x", .folder), entry("/t/a/pkg.app", .package)],
            url("/t/a/x"): [],
        ]
        #expect(Tree.orphans(open: open, root: url("/t"), children: children) == [
            url("/t/a/gone"), url("/t/a/gone/deeper"), url("/t/b/y"), url("/t/b/y/z"),
            url("/t/a/pkg.app"), url("/elsewhere/z"),
        ])
    }

    @Test func withTheTabsOwnListingAFirstLevelFolderThatWentIsAnOrphan() {
        let open: Set<URL> = [url("/t/a"), url("/t/went")]
        let children: [URL: [Entry]] = [url("/t"): [entry("/t/a", .folder)]]
        #expect(Tree.orphans(open: open, root: url("/t/", folder: true), children: children)
            == [url("/t/went")])
    }
}
