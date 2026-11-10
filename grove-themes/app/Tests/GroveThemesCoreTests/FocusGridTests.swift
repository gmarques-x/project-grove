import Testing
@testable import GroveThemesCore

@Suite struct FocusGridTests {
    typealias Item = FocusGrid.Item

    /// Moves a fresh grid starting on `start` and returns where it ends.
    func after(_ moves: [FocusGrid.Direction], from start: String,
               layout: FocusGrid.Layout = .dropdown) -> Item {
        var grid = FocusGrid(layout: layout, current: start)
        for move in moves { grid.move(move) }
        return grid.focused
    }

    @Test(arguments: ["dark-hard", "dark-medium", "dark-soft", "light-hard", "light-medium", "light-soft"])
    func startsOnTheCurrentScheme(_ scheme: String) {
        #expect(FocusGrid(layout: .dropdown, current: scheme).focused == .scheme(scheme))
        #expect(FocusGrid(layout: .gallery, current: scheme).focused == .scheme(scheme))
    }

    @Test func anUnknownCurrentStartsInTheMiddleOfTheTopRow() {
        #expect(FocusGrid(layout: .dropdown, current: "nope").focused == .scheme("dark-medium"))
    }

    @Test(arguments: [FocusGrid.Layout.dropdown, .gallery])
    func movesBetweenTiles(_ layout: FocusGrid.Layout) {
        #expect(after([.right], from: "dark-hard", layout: layout) == .scheme("dark-medium"))
        #expect(after([.right, .right], from: "dark-hard", layout: layout) == .scheme("dark-soft"))
        #expect(after([.left], from: "dark-medium", layout: layout) == .scheme("dark-hard"))
        #expect(after([.down], from: "dark-soft", layout: layout) == .scheme("light-soft"))
        #expect(after([.up], from: "light-hard", layout: layout) == .scheme("dark-hard"))
        #expect(after([.down, .right, .up], from: "dark-hard", layout: layout) == .scheme("dark-medium"))
    }

    /// Every corner and edge: a move off the grid stays put (no wrap).
    @Test(arguments: [FocusGrid.Layout.dropdown, .gallery])
    func stopsAtTheEdges(_ layout: FocusGrid.Layout) {
        #expect(after([.left], from: "dark-hard", layout: layout) == .scheme("dark-hard"))
        #expect(after([.up], from: "dark-hard", layout: layout) == .scheme("dark-hard"))
        #expect(after([.up], from: "dark-medium", layout: layout) == .scheme("dark-medium"))
        #expect(after([.right], from: "dark-soft", layout: layout) == .scheme("dark-soft"))
        #expect(after([.up], from: "dark-soft", layout: layout) == .scheme("dark-soft"))
        #expect(after([.left], from: "light-hard", layout: layout) == .scheme("light-hard"))
        #expect(after([.right], from: "light-soft", layout: layout) == .scheme("light-soft"))
        #expect(after([.left, .left, .left], from: "light-soft", layout: layout) == .scheme("light-hard"))
    }

    @Test func galleryHasNoMenuRows() {
        for scheme in ["light-hard", "light-medium", "light-soft"] {
            #expect(after([.down], from: scheme, layout: .gallery) == .scheme(scheme))
            #expect(after([.down, .down, .down], from: scheme, layout: .gallery) == .scheme(scheme))
        }
    }

    @Test func dropdownGoesDownFromTheBottomRowToOpenThenQuit() {
        for scheme in ["light-hard", "light-medium", "light-soft"] {
            #expect(after([.down], from: scheme) == .openWindow)
            #expect(after([.down, .down], from: scheme) == .quit)
            #expect(after([.down, .down, .down], from: scheme) == .quit)
        }
        #expect(after([.down, .down], from: "dark-hard") == .openWindow)
    }

    @Test func menuRowsAreOneColumn() {
        #expect(after([.down, .left], from: "light-hard") == .openWindow)
        #expect(after([.down, .right], from: "light-soft") == .openWindow)
        #expect(after([.down, .down, .left], from: "light-hard") == .quit)
        #expect(after([.down, .down, .right], from: "light-soft") == .quit)
        #expect(after([.down, .down, .up], from: "light-medium") == .openWindow)
    }

    @Test func upFromOpenReturnsToTheColumnLastUsed() {
        #expect(after([.down, .up], from: "light-hard") == .scheme("light-hard"))
        #expect(after([.down, .up], from: "light-soft") == .scheme("light-soft"))
        #expect(after([.down, .down, .up, .up], from: "light-soft") == .scheme("light-soft"))
        #expect(after([.left, .down, .down, .up], from: "dark-soft") == .scheme("light-medium"))
    }
}

@Suite struct KeyboardFocusTests {
    typealias Item = FocusGrid.Item

    @Test func keys() {
        let none: FocusKey.Modifiers = []
        #expect(FocusKey.up.command(none) == .move(.up))
        #expect(FocusKey.down.command(none) == .move(.down))
        #expect(FocusKey.left.command(none) == .move(.left))
        #expect(FocusKey.right.command(none) == .move(.right))
        #expect(FocusKey.up.command(.shift) == nil)
        #expect(FocusKey.left.command(.command) == nil)
        #expect(FocusKey.right.command(.control) == nil)
        for (key, direction) in [("h", FocusGrid.Direction.left), ("j", .down), ("k", .up), ("l", .right)] {
            #expect(FocusKey.character(Character(key)).command(.control) == .move(direction))
            #expect(FocusKey.character(Character(key)).command(none) == nil)
            #expect(FocusKey.character(Character(key)).command([.control, .shift]) == nil)
        }
        // Ctrl+h/j/k/l as the control characters some events carry.
        #expect(FocusKey.character("\u{08}").command(.control) == .move(.left))
        #expect(FocusKey.character("\n").command(.control) == .move(.down))
        #expect(FocusKey.character("\u{0B}").command(.control) == .move(.up))
        #expect(FocusKey.character("\u{0C}").command(.control) == .move(.right))
        #expect(FocusKey.character("\n").command(none) == nil)
        #expect(FocusKey.returnKey.command(none) == .activate)
        #expect(FocusKey.space.command(none) == .activate)
        #expect(FocusKey.returnKey.command(.command) == nil)
        #expect(FocusKey.escape.command(none) == .escape)
        #expect(FocusKey.character("x").command(none) == nil)
    }

    @Test func hiddenUntilAMoveThenShownOnTheCurrentScheme() {
        var focus = KeyboardFocus(layout: .dropdown)
        #expect(focus.focused == nil)
        #expect(focus.handle(.move(.right), current: "light-medium", schemesDisabled: false) == .handled)
        #expect(focus.focused == .scheme("light-medium"))
        #expect(focus.handle(.move(.right), current: "light-medium", schemesDisabled: false) == .handled)
        #expect(focus.focused == .scheme("light-soft"))
    }

    @Test func activateDoesNothingWhileHidden() {
        var focus = KeyboardFocus(layout: .dropdown)
        #expect(focus.handle(.activate, current: "dark-hard", schemesDisabled: false) == .handled)
        #expect(focus.focused == nil)
    }

    @Test func activateRunsTheFocusedItem() {
        var focus = KeyboardFocus(layout: .dropdown)
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        #expect(focus.handle(.activate, current: "dark-hard", schemesDisabled: false) == .activate(.scheme("dark-hard")))
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        #expect(focus.focused == .openWindow)
        #expect(focus.handle(.activate, current: "dark-hard", schemesDisabled: true) == .activate(.openWindow))
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        #expect(focus.handle(.activate, current: "dark-hard", schemesDisabled: false) == .activate(.quit))
    }

    @Test func aSchemeIsNotActivatedWhileSwitchingIsDisabled() {
        var focus = KeyboardFocus(layout: .gallery)
        _ = focus.handle(.move(.left), current: "dark-medium", schemesDisabled: false)
        #expect(focus.handle(.activate, current: "dark-medium", schemesDisabled: true) == .handled)
        #expect(focus.focused == .scheme("dark-medium"))
    }

    @Test func escapeHidesTheBoxThenClosesTheDropdown() {
        var focus = KeyboardFocus(layout: .dropdown)
        _ = focus.handle(.move(.up), current: "dark-soft", schemesDisabled: false)
        #expect(focus.handle(.escape, current: "dark-soft", schemesDisabled: false) == .handled)
        #expect(focus.focused == nil)
        #expect(focus.handle(.escape, current: "dark-soft", schemesDisabled: false) == .close)
    }

    @Test func escapeInTheGalleryOnlyHides() {
        var focus = KeyboardFocus(layout: .gallery)
        _ = focus.handle(.move(.up), current: "dark-soft", schemesDisabled: false)
        #expect(focus.handle(.escape, current: "dark-soft", schemesDisabled: false) == .handled)
        #expect(focus.handle(.escape, current: "dark-soft", schemesDisabled: false) == .handled)
        #expect(focus.focused == nil)
    }

    @Test func hideForgetsThePositionAndTheNextMoveStartsOnTheCurrentScheme() {
        var focus = KeyboardFocus(layout: .dropdown)
        _ = focus.handle(.move(.right), current: "dark-hard", schemesDisabled: false)
        _ = focus.handle(.move(.right), current: "dark-hard", schemesDisabled: false)
        focus.hide()
        #expect(focus.focused == nil)
        _ = focus.handle(.move(.down), current: "light-hard", schemesDisabled: false)
        #expect(focus.focused == .scheme("light-hard"))
    }
}
