import GroveExplorerCore
import Testing

/// ↑ and ↓ in a card whose list is longer than the card.
@Suite struct CardScrollTests {
    @Test func downBringsTheNextItemBelowIntoViewAtTheBottom() {
        #expect(CardScroll.step(down: true, visible: 0...5, count: 12) == CardScroll.Step(item: 6, toTop: false))
        #expect(CardScroll.step(down: true, visible: 3...9, count: 12) == CardScroll.Step(item: 10, toTop: false))
    }

    @Test func upBringsTheNextItemAboveIntoViewAtTheTop() {
        #expect(CardScroll.step(down: false, visible: 3...9, count: 12) == CardScroll.Step(item: 2, toTop: true))
        #expect(CardScroll.step(down: false, visible: 1...6, count: 12) == CardScroll.Step(item: 0, toTop: true))
    }

    /// Nothing more that way: nothing is asked for and nothing is kept,
    /// so the next press the other way answers at once.
    @Test func atAnEndThereIsNoStep() {
        #expect(CardScroll.step(down: true, visible: 5...11, count: 12) == nil)
        #expect(CardScroll.step(down: false, visible: 0...5, count: 12) == nil)
        #expect(CardScroll.step(down: false, visible: 5...11, count: 12) == CardScroll.Step(item: 4, toTop: true))
        #expect(CardScroll.step(down: true, visible: 0...11, count: 12) == nil)
        #expect(CardScroll.step(down: true, visible: 0...0, count: 0) == nil)
    }

    /// Before the card has said what it shows, it shows its top.
    @Test func withNothingKnownYetItStartsFromTheTop() {
        #expect(CardScroll.step(down: true, visible: nil, count: 12) == CardScroll.Step(item: 1, toTop: false))
        #expect(CardScroll.step(down: false, visible: nil, count: 12) == nil)
    }

    /// What is in view is what the card says, wherever a wheel left it.
    @Test func aRangeBeyondTheItemsIsHeldToThem() {
        #expect(CardScroll.step(down: true, visible: 8...20, count: 12) == nil)
    }
}
