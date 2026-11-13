import Foundation
import GroveExplorerCore
import Testing

@Suite struct ArrangementTests {
    private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)

    private func arrangement(
        _ folder: URL? = nil, sort: GroveExplorerCore.SortOrder = .byName, filter: String = "", showHidden: Bool = false,
        open: Set<URL> = []
    ) -> Arrangement {
        Arrangement(folder: folder ?? downloads, sort: sort, filter: filter, showHidden: showHidden, open: open)
    }

    @Test func theSameFolderSortFilterAndHiddenFlagIsReusedAsItIs() {
        #expect(arrangement().serves(arrangement()))
        #expect(arrangement(filter: "shot png", showHidden: true).serves(arrangement(filter: "shot png", showHidden: true)))
    }

    @Test func theSameFolderUnderAnotherFilterIsNot() {
        // ⌘F "shot", then ⌘T: the new tab has no filter and must not show four rows.
        #expect(!arrangement(filter: "shot").serves(arrangement()))
        #expect(!arrangement().serves(arrangement(filter: "shot")))
        #expect(!arrangement(filter: "shot").serves(arrangement(filter: "sho")))
    }

    @Test func aFilterClearedIsNoFilter() {
        #expect(!arrangement(filter: "shot").serves(arrangement(filter: "")))
        // A field that is open and empty, or holds only spaces, filters nothing.
        #expect(arrangement(filter: "").serves(arrangement(filter: "  ")))
        #expect(arrangement(filter: " ").serves(arrangement()))
    }

    @Test func spacesAroundTheWordsDoNotCount() {
        #expect(arrangement(filter: "shot  png ").serves(arrangement(filter: " shot png")))
    }

    @Test func theSameFolderInAnotherSortIsNot() {
        #expect(!arrangement().serves(arrangement(sort: GroveExplorerCore.SortOrder(column: .size, ascending: true))))
        #expect(!arrangement().serves(arrangement(sort: GroveExplorerCore.SortOrder(column: .name, ascending: false))))
    }

    @Test func hiddenItemsShownOrNotIsAnotherList() {
        #expect(!arrangement(showHidden: true).serves(arrangement(showHidden: false)))
    }

    @Test func anotherFolderIsNeverReused() {
        let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)
        #expect(!arrangement().serves(arrangement(documents)))
    }

    @Test func aFolderUnderAnotherSpellingOfItsPathIsTheSameFolder() {
        let spelled = URL(fileURLWithPath: "/Users/me/Documents/../Downloads/", isDirectory: true)
        #expect(arrangement().serves(arrangement(spelled)))
    }

    // MARK: Folders open in place

    private func inside(_ name: String, slash: Bool = false) -> URL {
        URL(fileURLWithPath: downloads.path + "/" + name + (slash ? "/" : ""), isDirectory: true)
    }

    /// Rows arranged with one folder open are other rows than with two.
    @Test func anotherSetOfOpenFoldersIsAnotherList() {
        #expect(!arrangement(open: [inside("a")]).serves(arrangement(open: [inside("a"), inside("b")])))
        #expect(!arrangement(open: [inside("a"), inside("b")]).serves(arrangement(open: [inside("a")])))
        #expect(!arrangement(open: [inside("a")]).serves(arrangement()))
        #expect(!arrangement().serves(arrangement(open: [inside("a")])))
    }

    @Test func theSameOpenFoldersHoweverSpelledAreReused() {
        #expect(arrangement(open: [inside("a"), inside("b")]).serves(arrangement(open: [inside("b"), inside("a")])))
        let spelled = URL(fileURLWithPath: downloads.path + "/x/../a/", isDirectory: true)
        #expect(arrangement(open: [inside("a")]).serves(arrangement(open: [spelled])))
        #expect(arrangement(open: [inside("a", slash: true)]).serves(arrangement(open: [inside("a")])))
    }

    @Test func anArrangementForAnotherSetOfOpenFoldersArrivingLateIsDropped() {
        #expect(!Arrangement.mayShow(arrived: arrangement(open: [inside("a")]), for: arrangement()))
        #expect(Arrangement.mayShow(arrived: arrangement(open: [inside("a")]), for: arrangement(open: [inside("a")])))
    }

    @Test func whetherAFilterFilters() {
        #expect(!arrangement().isFiltered)
        #expect(!arrangement(filter: "  ").isFiltered)
        #expect(arrangement(filter: " a").isFiltered)
    }

    // MARK: An arrangement that arrives late

    @Test func anArrangementForTabAArrivingWhenThePaneShowsTabBOfTheSameFolderIsDropped() {
        // Tab A typed a filter letter; its rows were still being arranged
        // when the pane went to tab B, which has no filter.
        let forA = arrangement(filter: "s"), tabB = arrangement()
        #expect(!Arrangement.mayShow(arrived: forA, for: tabB))
        // And one for A's sort by size, with totals still arriving.
        let bySize = arrangement(sort: GroveExplorerCore.SortOrder(column: .size, ascending: false))
        #expect(!Arrangement.mayShow(arrived: bySize, for: tabB))
    }

    @Test func anArrangementForWhatThePaneAsksNowIsShown() {
        #expect(Arrangement.mayShow(arrived: arrangement(filter: "s"), for: arrangement(filter: "s")))
    }

    @Test func anArrangementForAFilterTypedOnSinceIsDropped() {
        #expect(!Arrangement.mayShow(arrived: arrangement(filter: "s"), for: arrangement(filter: "sh")))
    }

    @Test func anArrangementForAPaneThatHasNoTabIsDropped() {
        #expect(!Arrangement.mayShow(arrived: arrangement(), for: nil))
    }
}
