import CoreGraphics
import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct MenuListMoveTests {
    // A note, three rows, a note, a row.
    private let selectable = [false, true, true, true, false, true]

    @Test func downAndUpSkipWhatCannotBeChosenAndWrap() {
        #expect(MenuListMove.step(from: nil, by: 1, selectable: selectable) == 1)
        #expect(MenuListMove.step(from: nil, by: -1, selectable: selectable) == 5)
        #expect(MenuListMove.step(from: 1, by: 1, selectable: selectable) == 2)
        #expect(MenuListMove.step(from: 3, by: 1, selectable: selectable) == 5)
        #expect(MenuListMove.step(from: 5, by: 1, selectable: selectable) == 1)
        #expect(MenuListMove.step(from: 1, by: -1, selectable: selectable) == 5)
        #expect(MenuListMove.step(from: 5, by: -1, selectable: selectable) == 3)
        // From a row that can't be chosen (the pointer never leaves one lit, but still).
        #expect(MenuListMove.step(from: 4, by: 1, selectable: selectable) == 5)
        #expect(MenuListMove.step(from: 4, by: -1, selectable: selectable) == 3)
    }

    @Test func oneRowStaysAndNoRowIsNil() {
        #expect(MenuListMove.step(from: 0, by: 1, selectable: [true]) == 0)
        #expect(MenuListMove.step(from: 1, by: -1, selectable: [false, true, false]) == 1)
        #expect(MenuListMove.step(from: nil, by: 1, selectable: []) == nil)
        #expect(MenuListMove.step(from: nil, by: 1, selectable: [false, false]) == nil)
        #expect(MenuListMove.step(from: 0, by: 0, selectable: [true, true]) == nil)
        // An index past the end is taken for the last row.
        #expect(MenuListMove.step(from: 9, by: 1, selectable: [true, true, true]) == 0)
    }

    @Test func theEnds() {
        #expect(MenuListMove.first(selectable: selectable) == 1)
        #expect(MenuListMove.last(selectable: selectable) == 5)
        #expect(MenuListMove.first(selectable: [false]) == nil)
        #expect(MenuListMove.last(selectable: []) == nil)
    }

    @Test func aLetterJumpsToTheNextRowStartingWithItAndComesRound() {
        let titles = ["menu.toml line 3: unknown key", "Appearance", "Grove Keys", "About", "Ábaco", "Global Menu"]
        let all = [false, true, true, true, true, true]
        #expect(MenuListMove.jump(to: "a", from: nil, titles: titles, selectable: all) == 1)
        #expect(MenuListMove.jump(to: "a", from: 1, titles: titles, selectable: all) == 3)
        // Accents and case don't count.
        #expect(MenuListMove.jump(to: "A", from: 3, titles: titles, selectable: all) == 4)
        #expect(MenuListMove.jump(to: "a", from: 4, titles: titles, selectable: all) == 1)
        #expect(MenuListMove.jump(to: "g", from: 2, titles: titles, selectable: all) == 5)
        #expect(MenuListMove.jump(to: "g", from: 5, titles: titles, selectable: all) == 2)
        // The only such row: it stays.
        #expect(MenuListMove.jump(to: "g", from: 2, titles: ["x", "y", "Grove"], selectable: [true, true, true]) == 2)
        // A note is never jumped to; no match is nil.
        #expect(MenuListMove.jump(to: "m", from: nil, titles: titles, selectable: all) == nil)
        #expect(MenuListMove.jump(to: "z", from: 1, titles: titles, selectable: all) == nil)
        #expect(MenuListMove.jump(to: "", from: 1, titles: titles, selectable: all) == nil)
        #expect(MenuListMove.jump(to: "a", from: nil, titles: [], selectable: []) == nil)
    }
}

@Suite struct MenuHoverIntentTests {
    @Test func aSubmenuOpensAfterTheDelayNotBefore() {
        var intent = MenuHoverIntent()
        intent.pointer(over: 2, opens: true, now: 10)
        #expect(intent.due == 10 + MenuHoverIntent.openDelay)
        #expect(intent.fire(now: 10.1) == nil)
        #expect(intent.open == nil)
        #expect(intent.fire(now: 10 + MenuHoverIntent.openDelay) == .open(2))
        #expect(intent.open == 2 && intent.due == nil)
        // Nothing twice.
        #expect(intent.fire(now: 11) == nil)
    }

    @Test func movingOnTheSameRowDoesNotPutTheOpeningOff() {
        var intent = MenuHoverIntent()
        intent.pointer(over: 2, opens: true, now: 10)
        intent.pointer(over: 2, opens: true, now: 10.1)
        #expect(intent.due == 10 + MenuHoverIntent.openDelay)
        #expect(intent.fire(now: 10.16) == .open(2))
    }

    @Test func passingOverARowOpensNothing() {
        var intent = MenuHoverIntent()
        intent.pointer(over: 1, opens: true, now: 10)
        intent.pointer(over: 2, opens: false, now: 10.05)
        #expect(intent.due == nil)
        #expect(intent.fire(now: 11) == nil)
        // Another row with a submenu: its own delay, from when it was reached.
        intent.pointer(over: 1, opens: true, now: 12)
        intent.pointer(over: 3, opens: true, now: 12.1)
        #expect(intent.fire(now: 12.2) == nil)
        #expect(intent.fire(now: 12.1 + MenuHoverIntent.openDelay) == .open(3))
    }

    @Test func aPlainRowClosesTheOpenSubmenuAfterTheDelay() {
        var intent = MenuHoverIntent()
        intent.set(open: 0)
        intent.pointer(over: 4, opens: false, now: 20)
        #expect(intent.open == 0)
        #expect(intent.fire(now: 20.1) == nil)
        #expect(intent.fire(now: 20 + MenuHoverIntent.openDelay) == .close)
        #expect(intent.open == nil)
    }

    @Test func crossingRowsTowardTheSubmenuKeepsItForTheGracePeriod() {
        var intent = MenuHoverIntent()
        intent.set(open: 0)
        // Down and to the right, over two other rows, into the submenu.
        intent.pointer(over: 1, opens: true, towardSubmenu: true, now: 30)
        #expect(intent.due == 30 + MenuHoverIntent.grace)
        intent.pointer(over: 2, opens: false, towardSubmenu: true, now: 30.1)
        #expect(intent.due == 30.1 + MenuHoverIntent.grace)
        #expect(intent.fire(now: 30.3) == nil)
        intent.pointerInSubmenu()
        #expect(intent.due == nil)
        #expect(intent.fire(now: 40) == nil)
        #expect(intent.open == 0)
    }

    @Test func stoppingOnTheWayLetsTheGracePeriodRunOut() {
        var intent = MenuHoverIntent()
        intent.set(open: 0)
        intent.pointer(over: 1, opens: true, towardSubmenu: true, now: 30)
        #expect(intent.fire(now: 30.29) == nil)
        #expect(intent.fire(now: 30 + MenuHoverIntent.grace) == .open(1))
        #expect(intent.open == 1)
        // The same toward a plain row: the submenu closes.
        intent.pointer(over: 2, opens: false, towardSubmenu: true, now: 31)
        #expect(intent.fire(now: 31 + MenuHoverIntent.grace) == .close)
    }

    @Test func movingStraightDownSwitchesAfterTheOpeningDelay() {
        var intent = MenuHoverIntent()
        intent.set(open: 0)
        intent.pointer(over: 1, opens: true, towardSubmenu: false, now: 30)
        #expect(intent.due == 30 + MenuHoverIntent.openDelay)
        #expect(intent.fire(now: 30 + MenuHoverIntent.openDelay) == .open(1))
    }

    @Test func towardCountsOnlyWhileASubmenuIsOpen() {
        var intent = MenuHoverIntent()
        intent.pointer(over: 1, opens: true, towardSubmenu: true, now: 5)
        #expect(intent.due == 5 + MenuHoverIntent.openDelay)
    }

    @Test func backOnTheOpenRowNothingIsLeftWaiting() {
        var intent = MenuHoverIntent()
        intent.set(open: 0)
        intent.pointer(over: 3, opens: false, now: 1)
        intent.pointer(over: 0, opens: true, now: 1.05)
        #expect(intent.due == nil)
        #expect(intent.fire(now: 5) == nil)
        #expect(intent.open == 0)
    }

    @Test func leavingThePanelKeepsWhatIsOpenAndOpensNothingNew() {
        var intent = MenuHoverIntent()
        intent.pointer(over: 1, opens: true, now: 1)
        intent.pointerAway()
        #expect(intent.fire(now: 5) == nil)
        intent.set(open: 2)
        intent.pointer(over: 4, opens: false, now: 6)
        intent.pointerAway()
        #expect(intent.fire(now: 9) == nil)
        #expect(intent.open == 2)
    }

    @Test func aClickOrAKeyIsAtOnce() {
        var intent = MenuHoverIntent()
        intent.pointer(over: 1, opens: true, now: 1)
        intent.set(open: 3)
        #expect(intent.open == 3 && intent.due == nil)
        intent.set(open: nil)
        #expect(intent.open == nil)
        #expect(intent.fire(now: 9) == nil)
    }
}

@Suite struct MenuListLayoutTests {
    /// The app's measures: the panel's 12 pt inset less the rows' own 4
    /// (down) and 8 (across); a line and its 4 pt above and below.
    static let metrics = MenuListLayout.Metrics(edge: 8, side: 4, rule: 9)
    /// The shipped menu's top level: seven rows, a line above the last.
    static let top = MenuListLayout(width: 200, heights: Array(repeating: 24, count: 7),
                                    separators: [false, false, false, false, false, false, true], metrics: metrics)

    @Test func rowsStackFromTheEdgeWithALineWhereAskedFor() {
        let layout = Self.top
        #expect(layout.rows.count == 7)
        #expect(layout.rows[0] == CGRect(x: 4, y: 8, width: 192, height: 24))
        #expect(layout.rows[5] == CGRect(x: 4, y: 128, width: 192, height: 24))
        // The line's 9 pt before the last row.
        #expect(layout.rows[6] == CGRect(x: 4, y: 161, width: 192, height: 24))
        #expect(layout.height == 193)
        #expect(layout.size == CGSize(width: 200, height: 193))
    }

    @Test func theFirstRowsLineIsNotDrawn() {
        let layout = MenuListLayout(width: 190, heights: [24, 40, 24], separators: [true, false, true],
                                    metrics: Self.metrics)
        #expect(layout.rows.map(\.minY) == [8, 32, 81])
        #expect(layout.height == 113)
        #expect(!MenuListLayout.showsRule(0, separators: [true, false, true]))
        #expect(MenuListLayout.showsRule(2, separators: [true, false, true]))
        #expect(!MenuListLayout.showsRule(1, separators: [true, false, true]))
        #expect(!MenuListLayout.showsRule(5, separators: [true]))
    }

    @Test func anEmptyMenuIsItsPadding() {
        let layout = MenuListLayout(width: 200, heights: [], separators: [], metrics: Self.metrics)
        #expect(layout.rows.isEmpty && layout.height == 16)
        #expect(layout.row(at: CGPoint(x: 10, y: 8)) == nil)
    }

    @Test func thePointersRow() {
        let layout = Self.top
        #expect(layout.row(at: CGPoint(x: 100, y: 8)) == 0)
        #expect(layout.row(at: CGPoint(x: 100, y: 31.9)) == 0)
        #expect(layout.row(at: CGPoint(x: 100, y: 32)) == 1)
        // The whole width counts, the outline included.
        #expect(layout.row(at: CGPoint(x: 0, y: 40)) == 1)
        #expect(layout.row(at: CGPoint(x: 200, y: 40)) == 1)
        #expect(layout.row(at: CGPoint(x: 201, y: 40)) == nil)
        #expect(layout.row(at: CGPoint(x: -1, y: 40)) == nil)
        // The padding and the line are no row.
        #expect(layout.row(at: CGPoint(x: 100, y: 4)) == nil)
        #expect(layout.row(at: CGPoint(x: 100, y: 156)) == nil)
        #expect(layout.row(at: CGPoint(x: 100, y: 161)) == 6)
        #expect(layout.row(at: CGPoint(x: 100, y: 185)) == nil)
    }
}

@Suite struct MenuListPlacementTests {
    /// Between the measured border lines (5.5 and 1914.5), below the top
    /// line, above the bottom gap (spec 2026-11-12-bar-panels-design §5).
    static let bounds = CGRect(x: 5.5, y: 49.5, width: 1909, height: 1185.5)
    /// The Grove menu under the pine, on the left line.
    static let menu = CGRect(x: 5.5, y: 49.5, width: 200, height: 193)

    static func place(_ parent: CGRect, row: Int, size: CGSize, bounds: CGRect = bounds) -> CGRect {
        MenuListPlacement.submenu(parent: parent, row: MenuListLayoutTests.top.rows[row], size: size, firstRow: 8,
                                  bounds: bounds)
    }

    @Test func theSubmenuSharesTheOutlineAndItsFirstRowIsLevelWithTheOpeningRow() {
        // "Appearance", the first row: the two panels' tops are level.
        let first = Self.place(Self.menu, row: 0, size: CGSize(width: 190, height: 193))
        #expect(first == CGRect(x: 204.5, y: 49.5, width: 190, height: 193))
        // The shared line: the submenu's left 1 pt is the menu's right 1 pt.
        #expect(first.minX == Self.menu.maxX - 1)
        // "Learn", the fourth row (y 80 in the menu): the submenu's first
        // row (8 below its top) starts where that row does.
        let fourth = Self.place(Self.menu, row: 3, size: CGSize(width: 190, height: 137))
        #expect(fourth.minY + 8 == Self.menu.minY + 80)
        #expect(fourth == CGRect(x: 204.5, y: 121.5, width: 190, height: 137))
    }

    @Test func aThirdLevelGoesOnFromTheSecond() {
        let second = Self.place(Self.menu, row: 3, size: CGSize(width: 190, height: 193))
        let third = Self.place(second, row: 1, size: CGSize(width: 220, height: 64))
        #expect(third.minX == second.maxX - 1)
        #expect(third.minY == second.minY + 32 - 8)
    }

    @Test func withoutRoomAtTheRightItGoesToTheLeftOfItsParent() {
        let parent = CGRect(x: 1700, y: 49.5, width: 200, height: 193)
        let side = Self.place(parent, row: 0, size: CGSize(width: 190, height: 100))
        #expect(side.maxX == parent.minX + 1)
        #expect(side.minX == 1511)
        // Exactly fitting stays at the right.
        let fits = Self.place(CGRect(x: 1525.5, y: 49.5, width: 200, height: 193), row: 0,
                              size: CGSize(width: 190, height: 100))
        #expect(fits.minX == 1724.5 && fits.maxX == 1914.5)
    }

    @Test func withRoomOnNeitherSideItIsKeptInside() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 600)
        let side = Self.place(CGRect(x: 60, y: 0, width: 200, height: 193), row: 0,
                              size: CGSize(width: 190, height: 100), bounds: narrow)
        #expect(side.minX == 110 && side.maxX == 300)
        // Wider than the screen: from its left edge.
        let wide = Self.place(CGRect(x: 60, y: 0, width: 200, height: 193), row: 0,
                              size: CGSize(width: 400, height: 100), bounds: narrow)
        #expect(wide.minX == 0)
    }

    @Test func nearTheBottomItMovesUpAndNeverAboveTheTop() {
        let low = CGRect(x: 5.5, y: 1000, width: 200, height: 193)
        let side = Self.place(low, row: 6, size: CGSize(width: 190, height: 193))
        #expect(side.maxY == Self.bounds.maxY)
        #expect(side.minY == 1042)
        let tall = Self.place(Self.menu, row: 6, size: CGSize(width: 190, height: 3000))
        #expect(tall.minY == Self.bounds.minY)
    }

    @Test func theWindowIsOnWholePointsWithThePanelInsetInIt() {
        let (frame, inset) = MenuListPlacement.window(for: CGRect(x: 204.5, y: 121.5, width: 190, height: 137))
        #expect(frame == CGRect(x: 204, y: 121, width: 191, height: 138))
        #expect(inset == CGPoint(x: 0.5, y: 0.5))
        let whole = MenuListPlacement.window(for: CGRect(x: 12, y: 50, width: 190, height: 100))
        #expect(whole.frame == CGRect(x: 12, y: 50, width: 190, height: 100) && whole.inset == .zero)
    }
}
