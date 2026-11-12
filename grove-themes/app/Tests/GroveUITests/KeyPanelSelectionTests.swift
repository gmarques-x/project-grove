import Testing
@testable import GroveUI

/// How a key panel's selection moves: what ↑/↓, a click and a new list do
/// in the launcher and the searchable cheat sheet.
@Suite struct KeyPanelSelectionTests {
    func selection(_ ids: [String]) -> KeyPanelSelection<String> {
        var selection = KeyPanelSelection<String>()
        selection.show(ids)
        return selection
    }

    @Test func nothingIsSelectedInAnEmptyList() {
        var selection = KeyPanelSelection<String>()
        #expect(selection.selected == nil)
        #expect(selection.index == nil)
        selection.move(1)
        selection.move(-1)
        selection.select("a")
        #expect(selection.selected == nil)
        selection.show([])
        #expect(selection.index == nil)
    }

    @Test func aNewListSelectsItsFirstRow() {
        var selection = selection(["a", "b", "c"])
        #expect(selection.selected == "a")
        #expect(selection.index == 0)
        selection.move(2)
        selection.show(["c", "d"])
        #expect(selection.selected == "c")
        #expect(selection.index == 0)
        selection.show([])
        #expect(selection.selected == nil)
    }

    @Test func theArrowsStopAtTheEnds() {
        var selection = selection(["a", "b", "c"])
        selection.move(-1)
        #expect(selection.selected == "a")
        selection.move(1)
        #expect(selection.selected == "b")
        selection.move(1)
        selection.move(1)
        selection.move(1)
        #expect(selection.selected == "c")
        #expect(selection.index == 2)
        selection.move(-1)
        #expect(selection.selected == "b")
    }

    @Test func aClickSelectsARowThatIsListed() {
        var selection = selection(["a", "b", "c"])
        selection.select("c")
        #expect(selection.selected == "c")
        selection.select("x")
        #expect(selection.selected == "c")
        selection.move(-1)
        #expect(selection.selected == "b")
    }

    /// A list brought up to date under the same query (the launcher's apps
    /// scanned again, Ghostty's keys arriving in the cheat sheet).
    @Test func aRefreshedListKeepsTheSelectedRowWhereItNowIs() {
        var selection = selection(["a", "b", "c"])
        selection.move(1)
        selection.show(["x", "a", "y", "b", "c"], keepingSelection: true)
        #expect(selection.selected == "b")
        #expect(selection.index == 3)
        // Gone from the list: the first row.
        selection.show(["x", "y"], keepingSelection: true)
        #expect(selection.selected == "x")
        selection.show([], keepingSelection: true)
        #expect(selection.selected == nil)
        // Nothing was selected: the first row.
        selection.show(["a", "b"], keepingSelection: true)
        #expect(selection.selected == "a")
    }

    /// The selection is a place, so two rows with one id don't trap ↓.
    @Test func rowsWithTheSameIdDoNotTrapTheArrows() {
        var selection = selection(["a", "b", "b", "c"])
        selection.move(1)
        selection.move(1)
        #expect(selection.index == 2)
        selection.move(1)
        #expect(selection.selected == "c")
    }
}
