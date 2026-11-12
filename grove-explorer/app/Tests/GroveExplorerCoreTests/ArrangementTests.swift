import Foundation
import GroveExplorerCore
import Testing

@Suite struct ArrangementTests {
    private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)

    private func arrangement(
        _ folder: URL? = nil, sort: GroveExplorerCore.SortOrder = .byName, filter: String = "", showHidden: Bool = false
    ) -> Arrangement {
        Arrangement(folder: folder ?? downloads, sort: sort, filter: filter, showHidden: showHidden)
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

    // MARK: Rows a pane already has, for a tab that comes to show their folder

    @Test func rowsArrangedAsTheTabAsksAreShownAsTheyAre() {
        #expect(arrangement().reuse(for: arrangement(), entries: 50_000) == .asItIs)
    }

    @Test func aSmallFolderIsArrangedAtOnce() {
        let bySize = arrangement(sort: GroveExplorerCore.SortOrder(column: .size, ascending: true))
        #expect(arrangement().reuse(for: bySize, entries: 212) == .arrangeNow)
        #expect(arrangement(filter: "shot").reuse(for: arrangement(), entries: Arrangement.arrangeNowLimit) == .arrangeNow)
        #expect(Arrangement.arrangeNowLimit == 10_000)
    }

    @Test func aBigFolderInAnotherSortKeepsItsOrderMeanwhile() {
        // The same rows, the right set: only their order is still the other tab's.
        let bySize = arrangement(sort: GroveExplorerCore.SortOrder(column: .size, ascending: true))
        #expect(arrangement().reuse(for: bySize, entries: 10_001) == .oldOrder)
        #expect(arrangement(filter: "shot").reuse(for: arrangement(sort: bySize.sort, filter: " shot"), entries: 50_000) == .oldOrder)
    }

    @Test func aBigFolderUnderAnotherFilterOrHiddenFlagIsBlankMeanwhile() {
        // Never another tab's pick of rows, even for a moment.
        #expect(arrangement(filter: "shot").reuse(for: arrangement(), entries: 10_001) == .blank)
        #expect(arrangement().reuse(for: arrangement(filter: "shot"), entries: 50_000) == .blank)
        #expect(arrangement(showHidden: true).reuse(for: arrangement(), entries: 50_000) == .blank)
        // With the sort different too.
        let bySize = arrangement(sort: GroveExplorerCore.SortOrder(column: .size, ascending: true), filter: "shot")
        #expect(arrangement().reuse(for: bySize, entries: 50_000) == .blank)
    }
}
