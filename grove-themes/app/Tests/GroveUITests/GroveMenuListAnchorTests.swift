import AppKit
import GroveThemesCore
import Testing
@testable import GroveUI

/// A view's Grove menu: the right-click that opens it (and what doesn't),
/// where it opens, and GroveSelect's rows. On a host whose panels are never
/// put on screen.
@MainActor @Suite(.serialized) struct GroveMenuListAnchorTests {
    let host = GroveMenuListHost(showsPanels: false, isActive: { true }, activate: {})
    let window: NSWindow
    let anchor = GroveMenuListAnchorView(frame: NSRect(x: 40, y: 60, width: 200, height: 24))

    init() {
        let screen = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        anchor.host = host
        anchor.rightClick = true
        anchor.rows = { [GroveMenuListRow(id: "record", title: "Record shortcut"),
                         GroveMenuListRow(id: "remove", title: "Remove")] }
        window.contentView!.addSubview(anchor)
    }

    /// A click at `point` in the window's coordinates.
    func click(_ type: NSEvent.EventType, at point: NSPoint, _ flags: NSEvent.ModifierFlags = [],
               in target: NSWindow? = nil) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                           windowNumber: (target ?? window).windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    /// The anchor's middle, in the window.
    var middle: NSPoint { NSPoint(x: anchor.frame.midX, y: anchor.frame.midY) }

    @Test func aRightClickOnTheViewOpensItsMenuAtThePointer() throws {
        #expect(anchor.rightClicked(click(.rightMouseDown, at: middle)))
        let open = try #require(host.current)
        #expect(open.model.levels.first?.rows.map(\.title) == ["Record shortcut", "Remove"])
        // Its top-left at the click.
        let onScreen = window.convertPoint(toScreen: middle)
        #expect(abs(Double(open.panels[0].frame.minX - onScreen.x)) <= 1)
        #expect(abs(Double(open.panels[0].frame.maxY - onScreen.y)) <= 1)
        host.close()
    }

    @Test func aControlClickIsARightClickAndOtherClicksAreNot() {
        #expect(GroveMenuListAnchorView.isMenuClick(click(.leftMouseDown, at: middle, .control)))
        #expect(!GroveMenuListAnchorView.isMenuClick(click(.leftMouseDown, at: middle)))
        #expect(!GroveMenuListAnchorView.isMenuClick(click(.leftMouseDown, at: middle, [.control, .command])))
        #expect(!anchor.rightClicked(click(.leftMouseDown, at: middle)))
        #expect(!host.isOpen)
    }

    @Test func aRightClickElsewhereGoesOn() {
        #expect(!anchor.rightClicked(click(.rightMouseDown, at: NSPoint(x: 10, y: 10))))
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                             backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        #expect(!anchor.rightClicked(click(.rightMouseDown, at: middle, in: other)))
        anchor.isHidden = true
        #expect(!anchor.rightClicked(click(.rightMouseDown, at: middle)))
        #expect(!host.isOpen)
    }

    @Test func noRowsIsNoMenuAndTheClickGoesOn() {
        anchor.rows = { [] }
        #expect(!anchor.rightClicked(click(.rightMouseDown, at: middle)))
        #expect(!host.isOpen)
    }

    @Test func aViewWithoutRightClickLeavesItsClicksAlone() {
        anchor.rightClick = false
        #expect(!anchor.rightClicked(click(.rightMouseDown, at: middle)))
        #expect(!host.isOpen)
    }

    @Test func aQuickRightClickDoesNotChooseTheRowUnderIt() throws {
        var chosen: [String] = []
        anchor.onChoose = { chosen.append($0) }
        let down = click(.rightMouseDown, at: middle)
        #expect(anchor.rightClicked(down))
        // The release of that same press, right away, over the first row.
        let open = try #require(host.current)
        let row = open.model.levels[0].layout.rows[0]
        let panel = open.panels[0].frame
        let over = NSPoint(x: panel.minX + row.midX, y: panel.maxY - row.midY)
        let up = NSEvent.mouseEvent(with: .rightMouseUp, location: over, modifierFlags: [], timestamp: 0.05,
                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        _ = host.handle(up)
        #expect(chosen.isEmpty)
        #expect(host.isOpen)
        host.close()
    }

    @Test func underTheViewIsWhereADropdownOpens() throws {
        var chosen: [String] = []
        anchor.showUnder(gap: 4, rows: [GroveMenuListRow(id: "0", title: "Escape")], onChoose: { chosen.append($0) })
        let open = try #require(host.current)
        // Its top at the view's bottom, 4 pt lower; its left at the view's.
        let bottomLeft = window.convertPoint(toScreen: NSPoint(x: anchor.frame.minX, y: anchor.frame.minY))
        #expect(Double(open.panels[0].frame.maxY) == Double(bottomLeft.y - 4))
        #expect(Double(open.panels[0].frame.minX) == Double(bottomLeft.x))
        _ = host.handle(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 125)!)
        _ = host.handle(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        #expect(chosen == ["0"])
    }

    // MARK: GroveSelect

    enum Tap: Hashable { case escape, none }
    static let options = [GroveSelectOption(Tap.escape, "Escape"), GroveSelectOption(Tap.none, "None")]

    @Test func aSelectsRowsAreItsOptionsWithTheCurrentOneTicked() {
        let rows = GroveSelectOption.menuRows(Self.options, selection: Tap.none)
        #expect(rows.map(\.title) == ["Escape", "None"])
        #expect(rows.map(\.id) == ["0", "1"])
        #expect(rows.map(\.checked) == [false, true])
        #expect(rows.allSatisfy { $0.kind == .action && $0.enabled })
        // Nothing selected: nothing ticked.
        #expect(GroveSelectOption.menuRows(Self.options, selection: nil).allSatisfy { !$0.checked })
    }

    @Test func aChosenRowIsItsOptionsValue() {
        #expect(GroveSelectOption.value(of: "0", in: Self.options) == .escape)
        #expect(GroveSelectOption.value(of: "1", in: Self.options) == Tap.none)
        #expect(GroveSelectOption.value(of: "2", in: Self.options) == nil)
        #expect(GroveSelectOption.value(of: "x", in: Self.options) == nil)
    }
}
