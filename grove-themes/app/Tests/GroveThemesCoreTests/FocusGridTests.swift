import Testing
@testable import GroveThemesCore

/// The two rows as the CLI lists them today.
private let both = ["grove", "avatar"]

extension KeyboardFocus {
    /// `handle` with today's two rows.
    fileprivate mutating func handle(_ command: FocusKey.Command, current: String,
                                     schemesDisabled: Bool) -> Outcome {
        handle(command, current: current, logos: both, wallpapers: both, schemesDisabled: schemesDisabled)
    }
}

@Suite struct FocusGridTests {
    typealias Item = FocusGrid.Item

    /// Moves a fresh grid starting on `start` and returns where it ends.
    func after(_ moves: [FocusGrid.Direction], from start: String,
               layout: FocusGrid.Layout = .dropdown,
               logos: [String] = both, wallpapers: [String] = both) -> Item {
        var grid = FocusGrid(layout: layout, current: start, logos: logos, wallpapers: wallpapers)
        for move in moves { grid.move(move) }
        return grid.focused
    }

    @Test(arguments: ["dark-hard", "dark-medium", "dark-soft", "light-hard", "light-medium", "light-soft"])
    func startsOnTheCurrentScheme(_ scheme: String) {
        #expect(after([], from: scheme, layout: .dropdown) == .scheme(scheme))
        #expect(after([], from: scheme, layout: .gallery) == .scheme(scheme))
    }

    @Test func anUnknownCurrentStartsInTheMiddleOfTheTopRow() {
        #expect(after([], from: "nope") == .scheme("dark-medium"))
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

    /// Below the light row: the "Terminal logo" row, Project Grove under the
    /// left two columns, Avatar under the right one.
    @Test(arguments: [FocusGrid.Layout.dropdown, .gallery])
    func downFromTheBottomRowReachesTheLogoRow(_ layout: FocusGrid.Layout) {
        #expect(after([.down], from: "light-hard", layout: layout) == .logo("grove"))
        #expect(after([.down], from: "light-medium", layout: layout) == .logo("grove"))
        #expect(after([.down], from: "light-soft", layout: layout) == .logo("avatar"))
        #expect(after([.down, .right], from: "light-hard", layout: layout) == .logo("avatar"))
        #expect(after([.down, .left], from: "light-soft", layout: layout) == .logo("grove"))
        #expect(after([.down, .left, .left], from: "light-soft", layout: layout) == .logo("grove"))
        #expect(after([.down, .right, .right], from: "light-hard", layout: layout) == .logo("avatar"))
    }

    @Test(arguments: [FocusGrid.Layout.dropdown, .gallery])
    func upFromTheLogoRowReturnsToTheColumnLastUsed(_ layout: FocusGrid.Layout) {
        #expect(after([.down, .up], from: "light-soft", layout: layout) == .scheme("light-soft"))
        #expect(after([.down, .up], from: "light-medium", layout: layout) == .scheme("light-medium"))
    }

    /// Below the logo row: the wallpaper row, the same two columns.
    @Test(arguments: [FocusGrid.Layout.dropdown, .gallery])
    func downFromTheLogoRowReachesTheWallpaperRow(_ layout: FocusGrid.Layout) {
        #expect(after([.down, .down], from: "light-hard", layout: layout) == .wallpaper("grove"))
        #expect(after([.down, .down], from: "light-soft", layout: layout) == .wallpaper("avatar"))
        #expect(after([.down, .down, .right], from: "light-hard", layout: layout) == .wallpaper("avatar"))
        #expect(after([.down, .right, .down], from: "light-hard", layout: layout) == .wallpaper("avatar"))
        #expect(after([.down, .down, .up], from: "light-soft", layout: layout) == .logo("avatar"))
        #expect(after([.down, .down, .left, .up], from: "light-soft", layout: layout) == .logo("grove"))
    }

    @Test func galleryStopsAtTheWallpaperRow() {
        #expect(after([.down, .down, .down], from: "light-hard", layout: .gallery) == .wallpaper("grove"))
        #expect(after([.down, .down, .down, .down, .down], from: "dark-soft", layout: .gallery) == .wallpaper("avatar"))
    }

    @Test func dropdownGoesDownFromTheWallpaperRowToOpenThenQuit() {
        for scheme in ["light-hard", "light-medium", "light-soft"] {
            #expect(after([.down, .down, .down], from: scheme) == .openWindow)
            #expect(after([.down, .down, .down, .down], from: scheme) == .quit)
            #expect(after([.down, .down, .down, .down, .down], from: scheme) == .quit)
        }
        #expect(after([.down, .down, .down, .down], from: "dark-hard") == .openWindow)
    }

    @Test func menuRowsAreOneColumn() {
        #expect(after([.down, .down, .down, .left], from: "light-hard") == .openWindow)
        #expect(after([.down, .down, .down, .right], from: "light-soft") == .openWindow)
        #expect(after([.down, .down, .down, .down, .left], from: "light-hard") == .quit)
        #expect(after([.down, .down, .down, .down, .up], from: "light-medium") == .openWindow)
    }

    @Test func upFromOpenReturnsToTheWallpaperLastUsed() {
        #expect(after([.down, .down, .down, .up], from: "light-hard") == .wallpaper("grove"))
        #expect(after([.down, .down, .down, .up], from: "light-soft") == .wallpaper("avatar"))
        #expect(after([.down, .down, .down, .up, .up, .up], from: "light-soft") == .scheme("light-soft"))
    }

    /// The wallpaper row is its own list, not the logos again.
    @Test(arguments: [FocusGrid.Layout.dropdown, .gallery])
    func theWallpaperRowUsesItsOwnList(_ layout: FocusGrid.Layout) {
        let papers = ["grove", "avatar", "forest"]
        func end(_ moves: [FocusGrid.Direction], from start: String) -> Item {
            after(moves, from: start, layout: layout, wallpapers: papers)
        }
        #expect(end([.down, .down], from: "light-hard") == .wallpaper("grove"))
        #expect(end([.down, .down, .right], from: "light-hard") == .wallpaper("avatar"))
        #expect(end([.down, .down, .right, .right], from: "light-hard") == .wallpaper("forest"))
        #expect(end([.down, .down, .right, .right, .right], from: "light-hard") == .wallpaper("forest"))
        #expect(end([.down, .down, .right, .right, .left], from: "light-hard") == .wallpaper("avatar"))
        // The shorter logo row shows its last item, and the place is kept.
        #expect(end([.down, .down, .right, .right, .up], from: "light-hard") == .logo("avatar"))
        #expect(end([.down, .down, .right, .right, .up, .down], from: "light-hard") == .wallpaper("forest"))
        #expect(end([.down, .down, .right, .right, .up, .left, .down], from: "light-hard") == .wallpaper("grove"))
    }

    /// Down from a tile lands on the item under it, however many the row has.
    @Test func downFromATileLandsUnderIt() {
        let three = ["a", "b", "c"]
        #expect(after([.down], from: "light-hard", logos: three) == .logo("a"))
        #expect(after([.down], from: "light-medium", logos: three) == .logo("b"))
        #expect(after([.down], from: "light-soft", logos: three) == .logo("c"))
        #expect(after([.down], from: "light-soft", logos: ["only"]) == .logo("only"))
        #expect(after([.down, .right], from: "light-hard", logos: ["only"]) == .logo("only"))
    }

    @Test func anEmptyListHasNoRow() {
        #expect(after([.down], from: "light-soft", logos: []) == .wallpaper("avatar"))
        #expect(after([.down, .up], from: "light-soft", logos: []) == .scheme("light-soft"))
        #expect(after([.down, .down], from: "light-hard", wallpapers: []) == .openWindow)
        #expect(after([.down, .down, .up], from: "light-soft", wallpapers: []) == .logo("avatar"))
        #expect(after([.down], from: "light-hard", logos: [], wallpapers: []) == .openWindow)
        #expect(after([.down], from: "light-hard", layout: .gallery, logos: [], wallpapers: [])
            == .scheme("light-hard"))
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
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        #expect(focus.focused == .openWindow)
        #expect(focus.handle(.activate, current: "dark-hard", schemesDisabled: true) == .activate(.openWindow))
        _ = focus.handle(.move(.down), current: "dark-hard", schemesDisabled: false)
        #expect(focus.handle(.activate, current: "dark-hard", schemesDisabled: false) == .activate(.quit))
    }

    @Test func aLogoIsActivatedLikeAScheme() {
        var focus = KeyboardFocus(layout: .gallery)
        _ = focus.handle(.move(.down), current: "light-soft", schemesDisabled: false)
        _ = focus.handle(.move(.down), current: "light-soft", schemesDisabled: false)
        #expect(focus.focused == .logo("avatar"))
        #expect(focus.handle(.activate, current: "light-soft", schemesDisabled: false) == .activate(.logo("avatar")))
        #expect(focus.handle(.activate, current: "light-soft", schemesDisabled: true) == .handled)
    }

    @Test func aWallpaperIsActivatedLikeAScheme() {
        var focus = KeyboardFocus(layout: .gallery)
        for _ in 0..<3 { _ = focus.handle(.move(.down), current: "light-hard", schemesDisabled: false) }
        #expect(focus.focused == .wallpaper("grove"))
        #expect(focus.handle(.activate, current: "light-hard", schemesDisabled: false) == .activate(.wallpaper("grove")))
        #expect(focus.handle(.activate, current: "light-hard", schemesDisabled: true) == .handled)
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
