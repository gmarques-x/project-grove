import GroveExplorerCore
import Testing

@Suite struct ListColumnsTests {
    @Test func aWidePaneHasEveryColumnAndTheLongDate() {
        let columns = ListColumns(paneWidth: 747)
        #expect(columns.showsDate && columns.showsKind && !columns.shortDate)
        // 747 less the edges (16 each), Size (72), the date (16 + 140) and Kind (16 + 112).
        #expect(columns.name == 359)
    }

    @Test func under640KindGoesAndTheDateShortens() {
        let at = ListColumns(paneWidth: 640)
        #expect(at.showsKind && !at.shortDate)
        let under = ListColumns(paneWidth: 639)
        #expect(under.showsDate && !under.showsKind && under.shortDate)
        #expect(under.name == 639 - 32 - 72 - 16 - 104)
    }

    @Test func under430TheDateGoesToo() {
        #expect(ListColumns(paneWidth: 430).showsDate)
        let under = ListColumns(paneWidth: 429)
        #expect(!under.showsDate && !under.showsKind)
        #expect(under.name == 429 - 32 - 72)
    }

    /// Beyond the cap the other columns follow the name and the rest is empty.
    @Test func theNameStopsAt560() {
        let columns = ListColumns(paneWidth: 1700)
        #expect(columns.name == 560)
        #expect(columns.used == 16 + 560 + 72 + 16 + 140 + 16 + 112 + 16)
    }

    @Test func aPaneTooNarrowStillHasAName() {
        #expect(ListColumns(paneWidth: 90).name == ListColumns.nameFloor)
    }
}
