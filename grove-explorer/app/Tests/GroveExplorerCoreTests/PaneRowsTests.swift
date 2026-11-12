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
}
