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
}
