import GroveExplorerCore
import Testing

@Suite struct StatusTextTests {
    @Test func countsTheItems() {
        #expect(StatusText.items(total: 212, foldersOpen: 0, selected: 0, selectedBytes: nil, filteredFrom: nil) == "212 items")
        #expect(StatusText.items(total: 1, foldersOpen: 0, selected: 0, selectedBytes: nil, filteredFrom: nil) == "1 item")
        #expect(StatusText.items(total: 0, foldersOpen: 0, selected: 0, selectedBytes: nil, filteredFrom: nil) == "0 items")
    }

    @Test func saysHowManyAreSelectedAndTheirSize() {
        #expect(
            StatusText.items(total: 212, foldersOpen: 0, selected: 3, selectedBytes: 48_200_000, filteredFrom: nil)
                == "3 of 212 selected · 48.2 MB")
        #expect(StatusText.items(total: 1, foldersOpen: 0, selected: 1, selectedBytes: 0, filteredFrom: nil) == "1 of 1 selected · Zero KB")
    }

    /// A selected folder whose total isn't known yet: no size rather than a wrong one.
    @Test func leavesTheSizeOutWhileItIsNotKnown() {
        #expect(StatusText.items(total: 212, foldersOpen: 0, selected: 3, selectedBytes: nil, filteredFrom: nil) == "3 of 212 selected")
    }

    @Test func aFilterSaysHowManyOfTheFolderShow() {
        #expect(StatusText.items(total: 4, foldersOpen: 0, selected: 0, selectedBytes: nil, filteredFrom: 212) == "4 of 212")
    }

    /// The selection is counted among the rows the filter shows.
    @Test func aSelectionUnderAFilterIsCountedAmongWhatShows() {
        #expect(
            StatusText.items(total: 4, foldersOpen: 0, selected: 2, selectedBytes: 3_000, filteredFrom: 212) == "2 of 4 selected · 3 KB")
    }

    // MARK: Folders open in place

    @Test func saysHowManyFoldersAreOpen() {
        #expect(
            StatusText.items(total: 212, foldersOpen: 3, selected: 0, selectedBytes: nil, filteredFrom: nil)
                == "212 items · 3 folders open")
        #expect(
            StatusText.items(total: 12, foldersOpen: 1, selected: 0, selectedBytes: nil, filteredFrom: nil)
                == "12 items · 1 folder open")
        #expect(StatusText.items(total: 12, foldersOpen: 0, selected: 0, selectedBytes: nil, filteredFrom: nil) == "12 items")
    }

    /// With a selection the line is about the selection: no count of open folders.
    @Test func aSelectionLeavesTheOpenFoldersOut() {
        #expect(
            StatusText.items(total: 19, foldersOpen: 3, selected: 2, selectedBytes: 350_000, filteredFrom: nil)
                == "2 of 19 selected · 350 KB")
    }

    /// Under a filter the line counts the matches against the rows that would
    /// show without it, open folders' included, and says no more.
    @Test func aFilterCountsMatchesAgainstTheRowsThatWouldShow() {
        #expect(
            StatusText.items(total: 5, foldersOpen: 4, selected: 0, selectedBytes: nil, filteredFrom: 33) == "5 of 33")
    }
}
