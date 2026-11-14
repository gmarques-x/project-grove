import AppKit
import GroveThemesCore
import Testing
@testable import GroveUI

/// The pop-up host: one menu at a time, never key, the keys and clicks it
/// takes, what closes it, `onClose` once, submenus beside their row, and
/// the menu as the accessibility server sees it. Its panels are made and
/// placed but never put on screen (`showsPanels: false`).
@MainActor @Suite(.serialized) struct GroveMenuListHostTests {
    static let rows: [GroveMenuListRow] = [
        GroveMenuListRow(id: "open", title: "Open"),
        GroveMenuListRow(id: "rename", title: "Rename", enabled: false),
        GroveMenuListRow(id: "with", title: "Open With", separator: true, kind: .submenu([
            GroveMenuListRow(id: "with.mail", title: "Mail"),
            GroveMenuListRow(id: "with.music", title: "Música", checked: true),
        ])),
        GroveMenuListRow(id: "tag", title: "Tagged", checked: true),
    ]

    /// What one `popUp` was told.
    final class Calls {
        var chosen: [String] = []
        var closed = 0
        var order: [String] = []
    }

    /// In front, as when a menu is right-clicked open: tests of a menu
    /// popped up in the background make their own.
    let host = GroveMenuListHost(showsPanels: false, isActive: { true }, activate: {})
    let window: NSWindow
    let calls = Calls()

    init() {
        let screen = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 600, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    func popUp(_ rows: [GroveMenuListRow] = Self.rows, at point: NSPoint = NSPoint(x: 50, y: 400),
               in view: NSView? = nil, opening: NSEvent? = nil) {
        let calls = calls
        host.popUp(rows: rows, at: point, in: view ?? window.contentView!, theme: .fallback, opening: opening,
                   onChoose: { calls.chosen.append($0); calls.order.append("choose") },
                   onClose: { calls.closed += 1; calls.order.append("close") })
    }

    func key(_ code: UInt16, _ characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func click(_ type: NSEvent.EventType, in target: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0,
                           windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: 1)!
    }

    /// An attribute as the accessibility server asks for it: by the
    /// (deprecated) attribute-name messages, sent by selector.
    static func value(_ element: NSObject, _ attribute: NSAccessibility.Attribute) -> Any? {
        element.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: attribute.rawValue)?
            .takeUnretainedValue()
    }

    static func names(_ element: NSObject) -> [String] {
        (element.perform(NSSelectorFromString("accessibilityAttributeNames"))?.takeUnretainedValue() as? [String]) ?? []
    }

    /// A press or a release at `point` on the screen (AppKit's, y up), at `time`.
    func mouse(_ type: NSEvent.EventType, at point: NSPoint, time: TimeInterval) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// The middle of a row of a level's panel, on the screen.
    func middle(of row: Int, depth: Int = 0) throws -> NSPoint {
        let open = try #require(host.current)
        let frame = open.panels[depth].frame, rect = open.model.levels[depth].layout.rows[row]
        return NSPoint(x: frame.minX + rect.midX, y: frame.maxY - rect.midY)
    }

    /// The right-click that opened the menu, at the window's point (50, 400).
    func rightClick(at time: TimeInterval) -> NSEvent {
        NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 400), modifierFlags: [], timestamp: time,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: 1)!
    }

    static let escape: UInt16 = 53, down: UInt16 = 125, right: UInt16 = 124, enter: UInt16 = 36

    // MARK: The panel

    @Test func itOpensAPanelThatNeverTakesTheKeyboard() throws {
        popUp()
        #expect(host.isOpen)
        let panel = try #require(host.current?.panels.first)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.level == .popUpMenu)
        #expect(calls.closed == 0)
    }

    @Test func itsTopLeftIsAtThePointAndItFitsItsRows() throws {
        popUp(at: NSPoint(x: 50, y: 400))
        let open = try #require(host.current)
        let panel = try #require(open.panels.first)
        let point = window.convertPoint(toScreen: window.contentView!.convert(NSPoint(x: 50, y: 400), to: nil))
        #expect(panel.frame.minX == point.x.rounded(.down))
        #expect(panel.frame.maxY == point.y.rounded(.up) || panel.frame.maxY == point.y.rounded(.down))
        #expect(panel.frame.size == open.model.levels[0].layout.size)
        #expect(panel.frame.width >= GroveMenuListMetrics.submenu)
    }

    @Test func aMenuWithNoRowsShowsNothingAndClosesAtOnce() {
        popUp([])
        #expect(!host.isOpen)
        #expect(calls.closed == 1)
    }

    // MARK: One at a time

    @Test func aSecondPopUpClosesTheFirst() {
        popUp()
        let first = calls
        let second = Calls()
        host.popUp(rows: Self.rows, at: NSPoint(x: 80, y: 300), in: window.contentView!, theme: .fallback,
                   onChoose: { second.chosen.append($0) }, onClose: { second.closed += 1 })
        #expect(first.closed == 1)
        #expect(second.closed == 0)
        #expect(host.isOpen)
        #expect(host.current?.panels.count == 1)
        host.close()
        #expect(first.closed == 1)
        #expect(second.closed == 1)
    }

    // MARK: Keys

    @Test func everyKeyIsTheMenusAndNoneGoesOn() {
        popUp()
        #expect(!host.handle(key(Self.down)))
        #expect(host.current?.model.levels[0].highlighted == 0)
        // A key the menu has no use for (Tab, ⌘C) is swallowed all the same.
        #expect(!host.handle(key(48, "\t")))
        let copy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: "c",
                                    charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        #expect(!host.handle(copy))
        #expect(host.isOpen)
        #expect(calls.chosen.isEmpty)
    }

    @Test func returnChoosesTheRowThenTheMenuCloses() {
        popUp()
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.enter, "\r"))
        #expect(!host.isOpen)
        #expect(calls.chosen == ["open"])
        #expect(calls.order == ["choose", "close"])
        #expect(host.current == nil)
    }

    @Test func escapeClosesTheSubmenuThenTheMenu() {
        popUp()
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        #expect(host.current?.panels.count == 2)
        _ = host.handle(key(Self.escape, "\u{1b}"))
        #expect(host.isOpen)
        #expect(host.current?.panels.count == 1)
        _ = host.handle(key(Self.escape, "\u{1b}"))
        #expect(!host.isOpen)
        #expect(calls.chosen.isEmpty)
        #expect(calls.closed == 1)
    }

    @Test func returnWithNothingHighlightedPutsItAway() {
        popUp()
        _ = host.handle(key(Self.enter, "\r"))
        #expect(!host.isOpen)
        #expect(calls.chosen.isEmpty && calls.closed == 1)
    }

    // MARK: Submenus

    @Test func aSubmenuIsAPanelBesideItsRow() throws {
        popUp()
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        let open = try #require(host.current)
        #expect(open.panels.count == 2)
        let menu = open.panels[0].frame, submenu = open.panels[1].frame
        #expect(!open.panels[1].canBecomeKey)
        // The shared outline, at its right (there is room in a window near
        // the screen's left).
        #expect(submenu.minX == menu.maxX - 1)
        // Its first row level with "Open With" (y down: from the tops).
        let row = open.model.levels[0].layout.rows[2]
        let rowTop = Double(menu.maxY) - row.minY, firstRowTop = Double(submenu.maxY) - GroveMenuListMetrics.layout.edge
        #expect(rowTop == firstRowTop)
        // ← closes it.
        _ = host.handle(key(123))
        #expect(open.panels.count == 1)
    }

    @Test func aFilledSubmenuIsAskedWhenItOpens() throws {
        var asked = 0
        popUp([GroveMenuListRow(id: "with", title: "Open With", kind: .submenu([]), fill: {
            asked += 1
            return [GroveMenuListRow(id: "with.preview", title: "Preview")]
        })])
        #expect(asked == 0)
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        #expect(asked == 1)
        let open = try #require(host.current)
        #expect(open.panels.count == 2)
        #expect(open.model.levels[1].rows.map(\.title) == ["Preview"])
        _ = host.handle(key(Self.enter, "\r"))
        #expect(calls.chosen == ["with.preview"])
    }

    // MARK: What closes it

    @Test func aClickOutsideClosesItAndOnlyARightClickGoesOn() {
        popUp()
        #expect(!host.handle(click(.leftMouseDown, in: window)))
        #expect(!host.isOpen && calls.closed == 1)
        popUp()
        // A right-click goes on: the view under it opens its own menu, and
        // that `popUp` replaces nothing (this one is closed already).
        #expect(host.handle(click(.rightMouseDown, in: window)))
        #expect(!host.isOpen && calls.closed == 2)
        #expect(calls.chosen.isEmpty)
    }

    @Test func aClickInItsPanelsGoesToThem() throws {
        popUp()
        let panel = try #require(host.current?.panels.first)
        #expect(host.handle(click(.leftMouseDown, in: panel)))
        #expect(host.isOpen)
    }

    @Test func theWindowClosingWithASubmenuOpenClosesBothOnce() {
        popUp()
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        let panels = host.current?.panels ?? []
        #expect(panels.count == 2)
        window.close()
        #expect(!host.isOpen)
        #expect(calls.closed == 1)
        #expect(panels.allSatisfy { !$0.isVisible })
        #expect(host.current == nil)
        // Nothing left watching: another close is nothing.
        host.close()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(calls.closed == 1)
    }

    @Test func theAppGoingToTheBackgroundClosesIt() {
        popUp()
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!host.isOpen)
        #expect(calls.closed == 1)
        #expect(calls.chosen.isEmpty)
    }

    @Test func theWindowLosingTheKeyboardClosesIt() {
        popUp()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!host.isOpen && calls.closed == 1)
    }

    @Test func anotherWindowClosingLeavesItOpen() {
        popUp()
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
                             backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.close()
        #expect(host.isOpen)
        host.close()
        #expect(calls.closed == 1)
    }

    // MARK: Press, hold, release

    @Test func aPressHeldAndReleasedOverARowChoosesIt() throws {
        popUp(opening: rightClick(at: 100))
        // "Tagged": the release after a hold, and a move from the press.
        let up = mouse(.rightMouseUp, at: try middle(of: 3), time: 101)
        #expect(!host.handle(up))
        #expect(calls.chosen == ["tag"])
        #expect(calls.order == ["choose", "close"])
    }

    @Test func aQuickRightClickLeavesTheMenuOpen() throws {
        popUp(opening: rightClick(at: 100))
        // Released at once, even over a row: the click only opened it.
        #expect(host.handle(mouse(.rightMouseUp, at: try middle(of: 0), time: 100.1)))
        #expect(host.isOpen)
        #expect(calls.chosen.isEmpty)
        // A later press and release in the menu is a click on its row.
        #expect(!host.handle(mouse(.rightMouseUp, at: try middle(of: 0), time: 103)))
        #expect(calls.chosen == ["open"])
    }

    @Test func aReleaseOverADisabledRowOrOutsideChoosesNothing() throws {
        popUp(opening: rightClick(at: 100))
        // Over "Rename", disabled: used up, nothing chosen.
        #expect(!host.handle(mouse(.rightMouseUp, at: try middle(of: 1), time: 101)))
        #expect(host.isOpen && calls.chosen.isEmpty)
        // Outside the panels: it goes on to what was pressed.
        #expect(host.handle(mouse(.leftMouseUp, at: NSPoint(x: 1, y: 1), time: 102)))
        #expect(host.isOpen && calls.chosen.isEmpty)
    }

    @Test func aReleaseInASubmenuChoosesItsRow() throws {
        popUp(opening: rightClick(at: 100))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        #expect(!host.handle(mouse(.rightMouseUp, at: try middle(of: 0, depth: 1), time: 102)))
        #expect(calls.chosen == ["with.mail"])
    }

    // MARK: In the background

    @Test func aMenuPoppedUpInTheBackgroundBringsTheAppForward() throws {
        var asked = 0
        let background = GroveMenuListHost(showsPanels: false, isActive: { false }, activate: { asked += 1 })
        background.popUp(rows: Self.rows, at: NSPoint(x: 50, y: 400), in: window.contentView!, theme: .fallback,
                         opening: nil, onChoose: { _ in }, onClose: {})
        #expect(asked == 1)
        // The panel still never takes the keyboard.
        #expect(background.current?.panels.first?.canBecomeKey == false)
        background.close()
        // In front already: nothing to do.
        popUp()
        let front = GroveMenuListHost(showsPanels: false, isActive: { true }, activate: { asked += 1 })
        front.popUp(rows: Self.rows, at: NSPoint(x: 50, y: 400), in: window.contentView!, theme: .fallback,
                    opening: nil, onChoose: { _ in }, onClose: {})
        #expect(asked == 1)
        front.close()
    }

    // MARK: Odd cases

    @Test func aPopUpFromTheOldMenusOnCloseLeavesOneMenu() {
        let view = window.contentView!
        var nested = 0
        // The old menu's onClose pops up a menu of its own.
        host.popUp(rows: Self.rows, at: NSPoint(x: 50, y: 400), in: view, theme: .fallback, opening: nil,
                   onChoose: { _ in }, onClose: { [host] in
                       host.popUp(rows: Self.rows, at: NSPoint(x: 60, y: 300), in: view, theme: .fallback,
                                  opening: nil, onChoose: { _ in }, onClose: { nested += 1 })
                   })
        popUp()
        // The nested one was closed by the newest call, once; one is open.
        #expect(nested == 1)
        #expect(host.isOpen)
        #expect(host.current?.panels.count == 1)
        host.close()
        #expect(calls.closed == 1)
    }

    @Test func theViewLeavingItsWindowClosesTheMenu() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 450))
        window.contentView!.addSubview(view)
        popUp(in: view)
        _ = host.handle(key(Self.down))
        view.removeFromSuperview()
        // The next event finds it gone: closed, nothing chosen, the event goes on.
        #expect(host.handle(key(Self.enter, "\r")))
        #expect(!host.isOpen)
        #expect(calls.chosen.isEmpty && calls.closed == 1)
    }

    @Test func aChoiceAfterTheViewLeftChoosesNothing() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 450))
        window.contentView!.addSubview(view)
        popUp(in: view)
        let items = try #require(host.current?.panels[0].levelMenu?.items)
        view.removeFromSuperview()
        // VoiceOver's press doesn't go through `handle`.
        _ = items[0].accessibilityPerformPress()
        #expect(!host.isOpen)
        #expect(calls.chosen.isEmpty && calls.closed == 1)
    }

    @Test func scrollingOutsideTheMenuIsSwallowed() throws {
        popUp()
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3,
                                      wheel2: 0, wheel3: 0))
        let scroll = try #require(NSEvent(cgEvent: cg))
        #expect(scroll.type == .scrollWheel)
        #expect(!host.handle(scroll))
        #expect(host.isOpen)
    }

    // MARK: Accessibility

    @Test func aSubmenuPanelShowingAnotherRowsSubmenuIsAnotherMenu() throws {
        var rows = Self.rows
        rows.append(GroveMenuListRow(id: "more", title: "More", kind: .submenu([
            GroveMenuListRow(id: "more.a", title: "Alpha"),
        ])))
        popUp(rows)
        var posts: [String] = []
        host.onPost = { depth, note in posts.append("\(depth) \(note.rawValue)") }
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.down))
        _ = host.handle(key(Self.right))
        #expect(posts == ["1 AXMenuOpened"])
        // A click on "More" while "Open With" is open: the same panel, its
        // rows another submenu's.
        let open = try #require(host.current)
        let more = open.model.levels[0].layout.rows[4]
        posts = []
        open.model.click(0, at: CGPoint(x: more.midX, y: more.midY))
        #expect(open.panels.count == 2)
        #expect(open.model.levels[1].rows.map(\.id) == ["more.a"])
        #expect(posts == ["1 AXMenuClosed", "1 AXMenuOpened"])
        posts = []
        host.close()
        #expect(posts == ["1 AXMenuClosed", "0 AXMenuClosed"])
    }

    @Test func itIsAMenuOfMenuItemsToTheAccessibilityServer() throws {
        popUp()
        let open = try #require(host.current)
        let menu = try #require(open.panels[0].levelMenu)
        #expect(open.panels[0].contentView === menu)
        #expect(menu.isAccessibilityElement())
        #expect(menu.accessibilityRole() == .menu)
        let items = menu.items
        #expect(items.map { $0.accessibilityRole() } == Array(repeating: .menuItem, count: 4))
        #expect(items.map { $0.accessibilityTitle() } == ["Open", "Rename", "Open With", "Tagged"])
        #expect(items.map { $0.isAccessibilityEnabled() } == [true, false, true, true])
        let mark = GroveMenuListAccessibleItem.markChar
        #expect(Self.value(items[3], mark) as? String == "\u{2713}")
        #expect(Self.value(items[0], mark) == nil)
        #expect(Self.names(items[3]).contains(mark.rawValue))
        // A submenu's row has a menu as its child, open or not.
        #expect((items[2].accessibilityChildren()?.first as? NSAccessibilityElement)?.accessibilityRole() == .menu)
        #expect(items[0].accessibilityChildren()?.isEmpty ?? true)
        // The rows' frames are where they are drawn.
        #expect(items[0].accessibilityFrameInParentSpace() == open.model.levels[0].layout.rows[0])
    }

    @Test func anOpenSubmenuIsItsRowsChildAndThePressIsTheRowsClick() throws {
        popUp()
        let open = try #require(host.current)
        let items = try #require(open.panels[0].levelMenu?.items)
        // VoiceOver's press on "Open With" opens it, the keys in it.
        #expect(items[2].accessibilityPerformPress())
        host.refreshAccessibility()
        #expect(open.panels.count == 2)
        let submenu = try #require(open.panels[1].levelMenu)
        #expect(items[2].accessibilityChildren()?.first as? GroveMenuListAccessibleMenu === submenu)
        #expect(submenu.items.map { $0.accessibilityTitle() } == ["Mail", "Música"])
        #expect(Self.value(submenu.items[1], GroveMenuListAccessibleItem.markChar) as? String == "\u{2713}")
        #expect(submenu.items[0].isAccessibilitySelected())
        // A disabled row's press does nothing.
        #expect(!items[1].accessibilityPerformPress())
        #expect(submenu.items[1].accessibilityPerformPress())
        #expect(calls.chosen == ["with.music"])
        #expect(calls.closed == 1)
    }

    @Test func theHighlightedRowIsSelected() throws {
        popUp()
        _ = host.handle(key(Self.down))
        host.refreshAccessibility()
        let items = try #require(host.current?.panels[0].levelMenu?.items)
        #expect(items.map { $0.isAccessibilitySelected() } == [true, false, false, false])
    }
}
