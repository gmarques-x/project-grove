import Foundation
@testable import GroveExplorerCore
import Testing

/// The window's state and each change to it. Nothing here reads the disk:
/// the folders are only names. (An answer is compared with `== true`
/// because `#expect` can't take a bare call to a mutating method.)
@Suite struct BrowserTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func browser(_ path: String = "/a/b", twoPanes: Bool = false) -> Browser {
        Browser(start: folder(path), twoPanes: twoPanes, showHidden: false)
    }

    /// The folders of the active pane's tabs, as paths.
    private func tabPaths(_ browser: Browser) -> [String] {
        browser.panes[browser.active.rawValue].tabs.map(\.folder.path)
    }

    // MARK: Start

    @Test func startsWithOnePaneAndOneTabOnTheStartFolder() {
        let browser = Browser(start: folder("/a/b"), twoPanes: false, showHidden: true)
        #expect(browser.panes.count == 1)
        #expect(browser.panes[0].tabs.count == 1)
        #expect(browser.panes[0].current == 0)
        #expect(browser.active == .left)
        #expect(browser.showHidden)
        #expect(browser.activeTab.folder.path == "/a/b")
        #expect(browser.activeTab.sort == .byName)
        #expect(browser.activeTab.back.isEmpty)
        #expect(browser.activeTab.forward.isEmpty)
    }

    @Test func startsWithTwoPanesOnTheStartFolderWhenAsked() {
        let browser = browser(twoPanes: true)
        #expect(browser.panes.count == 2)
        #expect(browser.active == .left)
        #expect(browser.tab(.left)?.folder.path == "/a/b")
        #expect(browser.tab(.right)?.folder.path == "/a/b")
        #expect(browser.tab(.left)?.id != browser.tab(.right)?.id)
    }

    @Test func aSideWithoutAPaneHasNoTab() {
        let browser = browser()
        #expect(browser.tab(.left) == browser.activeTab)
        #expect(browser.tab(.right) == nil)
    }

    @Test func theOtherSide() {
        #expect(Side.left.other == .right)
        #expect(Side.right.other == .left)
    }

    // MARK: Titles

    @Test func aTabIsTitledByItsFoldersName() {
        #expect(Tab(folder: folder("/a/project-grove")).title == "project-grove")
        #expect(Tab(folder: folder("/")).title == "/")
    }

    @Test func theHomeFolderIsTitledHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(Tab(folder: home).title == "Home")
        #expect(Tab(folder: URL(fileURLWithPath: home.path + "/")).title == "Home")
        #expect(Tab(folder: home.appendingPathComponent("Developer")).title == "Developer")
    }

    // MARK: History

    @Test func goingToAFolderPushesHistoryAndClearsForward() {
        var browser = browser("/a")
        browser.go(to: folder("/a/b"))
        browser.go(to: folder("/a/b/c"))
        #expect(browser.activeTab.folder.path == "/a/b/c")
        #expect(browser.activeTab.back.map(\.path) == ["/a", "/a/b"])
        #expect(browser.activeTab.forward.isEmpty)
    }

    @Test func goingToTheFolderAlreadyShownChangesNothing() {
        var browser = browser("/a")
        browser.go(to: folder("/a/b"))
        let before = browser
        browser.go(to: URL(fileURLWithPath: "/a/b"))
        browser.go(to: folder("/a/x/../b"))
        #expect(browser == before)
    }

    @Test func theFolderIsKeptAsGiven() {
        var browser = browser("/a")
        let link = URL(fileURLWithPath: "/var/x", isDirectory: true)
        browser.go(to: link)
        #expect(browser.activeTab.folder == link)
    }

    @Test func backAndForwardWalkTheHistory() {
        var browser = browser("/a")
        browser.go(to: folder("/b"))
        browser.go(to: folder("/c"))

        #expect(browser.goBack() == true)
        #expect(browser.activeTab.folder.path == "/b")
        #expect(browser.activeTab.back.map(\.path) == ["/a"])
        #expect(browser.activeTab.forward.map(\.path) == ["/c"])

        #expect(browser.goBack() == true)
        #expect(browser.activeTab.folder.path == "/a")
        #expect(browser.activeTab.forward.map(\.path) == ["/c", "/b"])
        #expect(browser.goBack() == false)
        #expect(browser.activeTab.folder.path == "/a")

        #expect(browser.goForward() == true)
        #expect(browser.goForward() == true)
        #expect(browser.activeTab.folder.path == "/c")
        #expect(browser.activeTab.back.map(\.path) == ["/a", "/b"])
        #expect(browser.goForward() == false)
        #expect(browser.activeTab.folder.path == "/c")
    }

    @Test func goingSomewhereAfterBackDropsForward() {
        var browser = browser("/a")
        browser.go(to: folder("/b"))
        browser.go(to: folder("/c"))
        #expect(browser.goBack() == true)
        browser.go(to: folder("/d"))
        #expect(browser.activeTab.folder.path == "/d")
        #expect(browser.activeTab.back.map(\.path) == ["/a", "/b"])
        #expect(browser.activeTab.forward.isEmpty)
        #expect(browser.goForward() == false)
    }

    @Test func upGoesToTheParentAsAnyOtherGo() {
        var browser = browser("/a/b")
        #expect(browser.goBack() == false)
        #expect(browser.goUp() == true)
        #expect(browser.activeTab.folder.path == "/a")
        #expect(browser.activeTab.back.map(\.path) == ["/a/b"])
        #expect(browser.goUp() == true)
        #expect(browser.activeTab.folder.path == "/")
    }

    @Test func upStopsAtAVolumesRoot() {
        var startup = browser("/")
        #expect(startup.goUp() == false)
        #expect(startup == browser("/").with(id: startup.activeTab.id))

        var disk = browser("/Volumes/Backup/x")
        #expect(disk.goUp() == true)
        #expect(disk.activeTab.folder.path == "/Volumes/Backup")
        #expect(disk.goUp() == false)
        #expect(disk.activeTab.folder.path == "/Volumes/Backup")
    }

    // MARK: Tabs

    @Test func aNewTabOpensAfterTheCurrentOneOnTheSameFolder() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/z"))
        browser.selectTab(0)
        browser.setSort(.size)
        browser.go(to: folder("/b"))

        browser.newTab()
        #expect(tabPaths(browser) == ["/b", "/b", "/z"])
        #expect(browser.panes[0].current == 1)
        #expect(browser.activeTab.sort == SortOrder(column: .size, ascending: true))
        #expect(browser.activeTab.back.isEmpty)
        #expect(browser.activeTab.forward.isEmpty)
        #expect(Set(browser.panes[0].tabs.map(\.id)).count == 3)
    }

    @Test func aNewTabOpensOnTheFolderGiven() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/z"))
        #expect(tabPaths(browser) == ["/a", "/z"])
        #expect(browser.activeTab.folder.path == "/z")
    }

    @Test func theLastTabOfAPaneDoesNotClose() {
        var browser = browser("/a")
        let before = browser
        #expect(browser.closeTab() == false)
        #expect(browser == before)
    }

    @Test func closingATabShowsTheOneThatTakesItsPlace() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.newTab(folder: folder("/c"))
        browser.selectTab(1)

        #expect(browser.closeTab() == true)
        #expect(tabPaths(browser) == ["/a", "/c"])
        #expect(browser.activeTab.folder.path == "/c")

        // The rightmost has none after it: the one before shows.
        #expect(browser.closeTab() == true)
        #expect(tabPaths(browser) == ["/a"])
        #expect(browser.activeTab.folder.path == "/a")
        #expect(browser.closeTab() == false)
    }

    @Test func selectingATabThatIsNotThereChangesNothing() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.selectTab(0)
        #expect(browser.activeTab.folder.path == "/a")
        browser.selectTab(2)
        browser.selectTab(-1)
        #expect(browser.activeTab.folder.path == "/a")
        browser.selectTab(1)
        #expect(browser.activeTab.folder.path == "/b")
    }

    @Test func nextAndPreviousTabGoRound() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.newTab(folder: folder("/c"))

        browser.nextTab()
        #expect(browser.activeTab.folder.path == "/a")
        browser.nextTab()
        #expect(browser.activeTab.folder.path == "/b")
        browser.previousTab()
        #expect(browser.activeTab.folder.path == "/a")
        browser.previousTab()
        #expect(browser.activeTab.folder.path == "/c")
    }

    // MARK: Panes

    @Test func theSecondPaneOpensOnTheActiveTabsFolder() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.setSort(.modified)

        browser.togglePanes()
        #expect(browser.panes.count == 2)
        #expect(browser.active == .left)
        #expect(browser.panes[1].tabs.map(\.folder.path) == ["/b"])
        #expect(browser.tab(.right)?.sort == SortOrder(column: .modified, ascending: true))
        #expect(browser.tab(.right)?.id != browser.tab(.left)?.id)
    }

    @Test func togglingPanesTwiceGivesBackTheSamePane() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.go(to: folder("/c"))
        let before = browser

        browser.togglePanes()
        #expect(browser != before)
        browser.togglePanes()
        #expect(browser == before)
    }

    @Test func closingAPaneKeepsTheActiveOne() {
        var browser = browser("/a", twoPanes: true)
        browser.switchPane()
        browser.go(to: folder("/right"))
        browser.newTab(folder: folder("/right/two"))
        let kept = browser.panes[1]

        browser.togglePanes()
        #expect(browser.panes == [kept])
        #expect(browser.active == .left)
        #expect(browser.activeTab.folder.path == "/right/two")
    }

    @Test func switchingPaneWithOnePaneOpensTheSecond() {
        var browser = browser("/a")
        browser.switchPane()
        #expect(browser.panes.count == 2)
        #expect(browser.active == .right)
        #expect(browser.activeTab.folder.path == "/a")
        #expect(browser.tab(.left)?.folder.path == "/a")
    }

    @Test func switchingPaneGoesToTheOtherOne() {
        var browser = browser("/a", twoPanes: true)
        browser.switchPane()
        #expect(browser.active == .right)
        #expect(browser.panes.count == 2)
        browser.switchPane()
        #expect(browser.active == .left)
    }

    @Test func changesTouchOnlyTheActivePane() {
        var browser = browser("/a", twoPanes: true)
        let left = browser.panes[0]
        browser.switchPane()

        browser.go(to: folder("/b"))
        browser.newTab(folder: folder("/c"))
        browser.setSort(.kind)
        #expect(browser.goBack() == false)
        browser.previousTab()
        #expect(browser.goUp() == true)
        #expect(browser.closeTab() == true)

        #expect(browser.panes[0] == left)
        #expect(browser.panes[1].tabs.map(\.folder.path) == ["/c"])
    }

    // MARK: Sort

    @Test func sortingByTheSameColumnAgainReverses() {
        var browser = browser()
        browser.setSort(.name)
        #expect(browser.activeTab.sort == SortOrder(column: .name, ascending: false))
        browser.setSort(.name)
        #expect(browser.activeTab.sort == SortOrder(column: .name, ascending: true))

        browser.setSort(.name)
        browser.setSort(.name)
        browser.setSort(.name)
        #expect(browser.activeTab.sort == SortOrder(column: .name, ascending: false))
    }

    @Test func sortingByAnotherColumnStartsAscending() {
        var browser = browser()
        browser.setSort(.name)
        browser.setSort(.size)
        #expect(browser.activeTab.sort == SortOrder(column: .size, ascending: true))
    }

    @Test func eachTabKeepsItsOwnSort() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.setSort(.kind)
        browser.selectTab(0)
        #expect(browser.activeTab.sort == .byName)
        browser.selectTab(1)
        #expect(browser.activeTab.sort == SortOrder(column: .kind, ascending: true))
    }

    // MARK: Repair

    @Test func aMissingFolderFallsBackToItsNearestExistingParent() {
        var browser = browser("/a/b/c")
        browser.repair(exists: { $0.path == "/a" || $0.path == "/" }, home: home)
        #expect(browser.activeTab.folder.path == "/a")
    }

    @Test func aFolderThatExistsIsLeftAsItIs() {
        var browser = browser("/a/b/c")
        browser.go(to: folder("/a/b"))
        let before = browser
        browser.repair(exists: { _ in true }, home: home)
        #expect(browser == before)
    }

    @Test func repairLooksAtEveryTabOfEveryPane() {
        var browser = browser("/a/gone", twoPanes: true)
        browser.newTab(folder: folder("/a/here"))
        browser.switchPane()
        browser.go(to: folder("/a/here/gone/deeper"))

        let existing: Set<String> = ["/", "/a", "/a/here"]
        browser.repair(exists: { existing.contains($0.path) }, home: home)
        #expect(browser.panes[0].tabs.map(\.folder.path) == ["/a", "/a/here"])
        #expect(browser.panes[1].tabs.map(\.folder.path) == ["/a/here"])
        #expect(browser.active == .right)
    }

    @Test func tabsOfAnEjectedVolumeMoveHome() {
        var browser = browser("/Volumes/Backup/photos/2026")
        browser.newTab(folder: folder("/Volumes/Backup"))
        // /Volumes is still there, but it is not where the disk's tabs belong.
        let existing: Set<String> = ["/", "/Volumes", home.path]
        browser.repair(exists: { existing.contains($0.path) }, home: home)
        #expect(tabPaths(browser) == [home.path, home.path])
    }

    @Test func whenNothingExistsTheTabMovesHome() {
        var browser = browser("/a/b")
        browser.repair(exists: { _ in false }, home: home)
        #expect(browser.activeTab.folder == home)
    }

    // MARK: History's length

    @Test func theHistoryKeepsTheLatestHundredFolders() {
        var browser = browser("/start")
        for n in 1...150 { browser.go(to: folder("/f/\(n)")) }
        #expect(browser.activeTab.back.count == 100)
        // The oldest went: what is left is the hundred before /f/150.
        #expect(browser.activeTab.back.first?.path == "/f/50")
        #expect(browser.activeTab.back.last?.path == "/f/149")
    }

    @Test func goingBackAndForwardKeepsBothHistoriesWithinTheHundred() {
        var browser = browser("/start")
        for n in 1...150 { browser.go(to: folder("/f/\(n)")) }
        for _ in 1...100 { #expect(browser.goBack() == true) }
        #expect(browser.goBack() == false)
        #expect(browser.activeTab.forward.count == 100)
        #expect(browser.activeTab.folder.path == "/f/50")
        for _ in 1...100 { #expect(browser.goForward() == true) }
        #expect(browser.activeTab.folder.path == "/f/150")
        #expect(browser.activeTab.back.count == 100)
        #expect(browser.activeTab.forward.isEmpty)
    }

    @Test func aHistoryLongerThanTheLimitFromAnOldFileIsCutOnTheNextStep() {
        var browser = browser("/start")
        browser.panes[0].tabs[0].back = (1...300).map { folder("/old/\($0)") }
        browser.go(to: folder("/next"))
        #expect(browser.activeTab.back.count == 100)
        #expect(browser.activeTab.back.last?.path == "/start")
    }

    // MARK: Closing a tab that isn't showing

    @Test func closingATabBeforeTheCurrentOneKeepsTheCurrentOneShowing() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.newTab(folder: folder("/c"))
        #expect(browser.closeTab(0, in: .left) == true)
        #expect(tabPaths(browser) == ["/b", "/c"])
        #expect(browser.activeTab.folder.path == "/c")
    }

    @Test func closingATabAfterTheCurrentOneLeavesItWhereItIs() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.newTab(folder: folder("/c"))
        browser.selectTab(0)
        #expect(browser.closeTab(2, in: .left) == true)
        #expect(tabPaths(browser) == ["/a", "/b"])
        #expect(browser.activeTab.folder.path == "/a")
    }

    @Test func closingTheCurrentTabByItsPlaceIsClosingTheCurrentTab() {
        var browser = browser("/a")
        browser.newTab(folder: folder("/b"))
        browser.newTab(folder: folder("/c"))
        #expect(browser.closeTab(2, in: .left) == true)
        #expect(browser.activeTab.folder.path == "/b")
    }

    @Test func aTabOfTheOtherPaneClosesWithoutThatPaneBecomingActive() {
        var browser = browser("/a", twoPanes: true)
        browser.switchPane()
        browser.newTab(folder: folder("/b"))
        browser.switchPane()
        #expect(browser.closeTab(0, in: .right) == true)
        #expect(browser.active == .left)
        #expect(browser.tab(.right)?.folder.path == "/b")
        #expect(browser.panes[1].tabs.count == 1)
    }

    @Test func theOnlyTabATabThatIsNotThereAndAPaneThatIsNotThereDoNotClose() {
        var browser = browser("/a")
        #expect(browser.closeTab(0, in: .left) == false)
        browser.newTab(folder: folder("/b"))
        #expect(browser.closeTab(5, in: .left) == false)
        #expect(browser.closeTab(-1, in: .left) == false)
        #expect(browser.closeTab(0, in: .right) == false)
        #expect(tabPaths(browser) == ["/a", "/b"])
    }
}

private extension Browser {
    /// This browser with its one tab's id replaced, to compare two that were
    /// made apart.
    func with(id: UUID) -> Browser {
        var copy = self
        let tab = copy.panes[0].tabs[0]
        copy.panes[0].tabs[0] = Tab(
            id: id, folder: tab.folder, sort: tab.sort, back: tab.back, forward: tab.forward)
        return copy
    }
}
