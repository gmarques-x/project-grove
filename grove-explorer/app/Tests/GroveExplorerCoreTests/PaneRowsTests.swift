import Foundation
import GroveExplorerCore
import Testing

/// A pane between two folders: the rows it has are of the folder it left
/// until the new one is read, and no command may act on them.
@Suite struct PaneRowsTests {
    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    // MARK: Whose rows a pane has

    @Test func rowsAreTheTabsOnlyWhenTheyAreOfItsFolder() {
        #expect(PaneRows.areCurrent(listed: folder("/Users/me/Downloads"), tabFolder: folder("/Users/me/Downloads")))
        // ⌘↓ into a folder, ⌘↑ out of one: the rows are still the other folder's.
        #expect(!PaneRows.areCurrent(listed: folder("/Users/me"), tabFolder: folder("/Users/me/Downloads")))
        #expect(!PaneRows.areCurrent(listed: folder("/Users/me/Downloads"), tabFolder: folder("/Users/me")))
    }

    @Test func aFolderIsItselfHoweverItsPathIsSpelled() {
        #expect(PaneRows.areCurrent(listed: folder("/Users/me/Downloads"), tabFolder: URL(fileURLWithPath: "/Users/me/Downloads")))
        #expect(PaneRows.areCurrent(listed: folder("/Users/me/x/../Downloads"), tabFolder: folder("/Users/me/Downloads")))
        // A name that only starts the same is another folder.
        #expect(!PaneRows.areCurrent(listed: folder("/Users/me/Downloads 2"), tabFolder: folder("/Users/me/Downloads")))
    }

    @Test func noRowsOrNoTabIsNeverCurrent() {
        #expect(!PaneRows.areCurrent(listed: nil, tabFolder: folder("/Users/me")))
        #expect(!PaneRows.areCurrent(listed: folder("/Users/me"), tabFolder: nil))
        #expect(!PaneRows.areCurrent(listed: nil, tabFolder: nil))
    }

    // MARK: Whose selection goes

    private func browser() -> Browser {
        var browser = Browser(start: folder("/Users/me"), twoPanes: true, showHidden: false)
        browser.newTab(folder: folder("/Users/me/Documents"))
        return browser
    }

    @Test func aTabThatWentToAnotherFolderLosesItsSelection() {
        let was = browser()
        var now = was
        now.go(to: folder("/Users/me/Downloads"))
        #expect(PaneRows.tabsThatMoved(from: was, to: now) == [was.activeTab.id])
        // Up, back and forward are moves like any other.
        var up = was
        let wentUp = up.goUp()
        #expect(wentUp)
        #expect(PaneRows.tabsThatMoved(from: was, to: up) == [was.activeTab.id])
        var back = now
        let wentBack = back.goBack()
        #expect(wentBack)
        #expect(PaneRows.tabsThatMoved(from: now, to: back) == [was.activeTab.id])
    }

    @Test func tabsThatStayedKeepTheirs() {
        let was = browser()
        var now = was
        now.previousTab()
        now.switchPane()
        now.setSort(.size)
        now.showHidden.toggle()
        #expect(PaneRows.tabsThatMoved(from: was, to: now).isEmpty)
        // The same folder spelled another way is not a move.
        var same = was
        same.go(to: URL(fileURLWithPath: "/Users/me/x/../Documents"))
        #expect(PaneRows.tabsThatMoved(from: was, to: same).isEmpty)
    }

    @Test func aNewTabAndAClosedOneAreNotMoves() {
        let was = browser()
        var more = was
        more.newTab(folder: folder("/tmp"))
        #expect(PaneRows.tabsThatMoved(from: was, to: more).isEmpty)
        var fewer = was
        let closed = fewer.closeTab()
        #expect(closed)
        #expect(PaneRows.tabsThatMoved(from: was, to: fewer).isEmpty)
    }

    /// Two panes to one: the pane that stays keeps its tabs, by their ids.
    @Test func closingAPaneMovesNoTab() {
        var was = browser()
        was.switchPane()
        var now = was
        now.togglePanes()
        #expect(PaneRows.tabsThatMoved(from: was, to: now).isEmpty)
    }

    @Test func everyTabThatMovedIsNamed() {
        let was = browser()
        var now = was
        // A folder that went: the tabs on it and under it all move.
        now.repair(exists: { $0.path == "/Users" || $0.path == "/" }, home: folder("/Users/me"))
        let moved = PaneRows.tabsThatMoved(from: was, to: now)
        let expected = Set(was.panes.flatMap(\.tabs).map(\.id).filter { id in
            let old = was.panes.flatMap(\.tabs).first { $0.id == id }!
            let new = now.panes.flatMap(\.tabs).first { $0.id == id }!
            return old.folder.standardizedFileURL.path != new.folder.standardizedFileURL.path
        })
        #expect(!moved.isEmpty)
        #expect(moved == expected)
    }

    // MARK: Whose rows a folder open in place has

    private func listing(_ paths: [String]) -> [Entry] {
        paths.map {
            Entry(
                url: folder($0), name: folder($0).lastPathComponent, kind: .folder, size: nil, modified: nil,
                isHidden: false, typeDescription: "Folder")
        }
    }

    /// /t is shown with a open; a read of a was begun. What follows before
    /// it lands decides whether its rows go into the pane.
    private func opened() -> (browser: Browser, read: PaneRows.ChildRead) {
        var browser = Browser(start: folder("/t"), twoPanes: false, showHidden: false)
        browser.setOpen([folder("/t/a")], in: .left)
        let tab = browser.activeTab
        return (browser, PaneRows.ChildRead(tab: tab.id, tabFolder: tab.folder, folder: folder("/t/a")))
    }

    /// What the app asks with: the tab's open folders that show (`Tree.reachable`).
    private func isCurrent(_ read: PaneRows.ChildRead, in browser: Browser, listed: URL?, root: [String]) -> Bool {
        let tab = browser.tab(.left)
        let open = tab.map {
            Tree.reachable(open: $0.open, root: $0.folder, children: [$0.folder: listing(root)])
        } ?? []
        return PaneRows.isCurrent(read, tab: tab, listed: listed, open: open)
    }

    @Test func aChildReadLandsWhileNothingChanged() {
        let (browser, read) = opened()
        #expect(isCurrent(read, in: browser, listed: folder("/t"), root: ["/t/a"]))
        // However the folders are spelled.
        #expect(isCurrent(read, in: browser, listed: URL(fileURLWithPath: "/t/x/.."), root: ["/t/a"]))
    }

    @Test func aChildReadLandingAfterTheFolderWasClosedIsDropped() {
        var (browser, read) = opened()
        browser.setOpen([], in: .left)
        #expect(!isCurrent(read, in: browser, listed: folder("/t"), root: ["/t/a"]))
    }

    @Test func aChildReadLandingAfterItsParentWasClosedIsDropped() {
        var browser = Browser(start: folder("/t"), twoPanes: false, showHidden: false)
        browser.setOpen([folder("/t/a"), folder("/t/a/b")], in: .left)
        let read = PaneRows.ChildRead(tab: browser.activeTab.id, tabFolder: folder("/t"), folder: folder("/t/a/b"))
        // ← on a: what was open inside it is remembered, not shown, not read.
        browser.setOpen([folder("/t/a/b")], in: .left)
        #expect(!isCurrent(read, in: browser, listed: folder("/t"), root: ["/t/a"]))
    }

    @Test func aChildReadLandingAfterTheTabNavigatedIsDropped() {
        var (browser, read) = opened()
        browser.go(to: folder("/t/a"))
        // The pane is between two folders, then has the new one's rows.
        #expect(!isCurrent(read, in: browser, listed: folder("/t"), root: ["/t/a"]))
        #expect(!isCurrent(read, in: browser, listed: folder("/t/a"), root: []))
    }

    @Test func aChildReadLandingAfterTheTabWasSwitchedIsDropped() {
        var (browser, read) = opened()
        browser.newTab(folder: folder("/t"))
        browser.setOpen([folder("/t/a")], in: .left)
        // Another tab, on the same folder with the same folder open: not the read's.
        #expect(!isCurrent(read, in: browser, listed: folder("/t"), root: ["/t/a"]))
    }

    @Test func aChildReadLandingWhileThePaneIsBetweenTwoFoldersIsDropped() {
        let (browser, read) = opened()
        #expect(!isCurrent(read, in: browser, listed: folder("/u"), root: ["/t/a"]))
        #expect(!isCurrent(read, in: browser, listed: nil, root: ["/t/a"]))
    }

    @Test func aChildReadLandingAfterTheFolderWasRenamedIsDropped() {
        var (browser, read) = opened()
        // Renamed in the app: it stays open under its new name.
        let tab = browser.activeTab
        browser.setOpen(Tree.remapped(tab.open, from: folder("/t/a"), to: folder("/t/b")), in: .left)
        #expect(!isCurrent(read, in: browser, listed: folder("/t"), root: ["/t/b"]))
        // And the read of the new name is.
        let again = PaneRows.ChildRead(tab: tab.id, tabFolder: tab.folder, folder: folder("/t/b"))
        #expect(isCurrent(again, in: browser, listed: folder("/t"), root: ["/t/b"]))
    }

    @Test func aChildReadLandingAfterTheFolderWasDeletedIsDropped() {
        var (browser, read) = opened()
        let tab = browser.activeTab
        let gone = Tree.vanished(in: tab.folder, listing: [], open: tab.open)
        browser.setOpen(tab.open.subtracting(gone), in: .left)
        #expect(!isCurrent(read, in: browser, listed: folder("/t"), root: []))
    }
}
