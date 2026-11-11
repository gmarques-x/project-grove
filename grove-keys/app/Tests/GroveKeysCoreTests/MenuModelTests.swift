import Foundation
import Testing
@testable import GroveKeysCore

/// A menu tree in memory: each title path maps to its items.
final class FakeMenuSource: MenuSource, @unchecked Sendable {
    var tree: [[String]: [RawItem]]
    private(set) var pressed: [[String]] = []

    init(_ tree: [[String]: [RawItem]]) { self.tree = tree }

    func items(at path: MenuPath) -> [RawItem]? { tree[path.steps.map(\.title)] }

    func press(_ path: MenuPath) -> Bool {
        // The item must still be there, at its index among equal titles.
        guard let last = path.steps.last,
              let siblings = tree[path.steps.dropLast().map(\.title)]
        else { return false }
        let equal = siblings.filter { $0.title == last.title }
        guard last.index < equal.count else { return false }
        pressed.append(path.steps.map(\.title))
        return true
    }
}

func item(_ title: String?, enabled: Bool = true, mark: String? = nil, char: String? = nil,
          mods: Int? = nil, glyph: Int? = nil, children: Bool = false) -> RawItem {
    RawItem(title: title, enabled: enabled, markChar: mark, cmdChar: char, cmdModifiers: mods,
            cmdGlyph: glyph, hasChildren: children)
}

@Suite struct MenuModelTests {
    let source = FakeMenuSource([
        []: [item("Apple", children: true), item("Ghostty", children: true), item("File", children: true),
             item("View", children: true)],
        ["File"]: [item("New Window", char: "N", mods: 0), item("", enabled: false, mods: 8),
                   item("Close Window", char: "W", mods: 1), item("Export", enabled: false)],
        ["View"]: [item("Show Tab Bar", mark: "✓"), item("Show Tab Bar"), item("Zoom", children: true)],
    ])

    @Test func topLevelMenusAreSubmenus() throws {
        let nodes = try #require(MenuModel.nodes(at: MenuPath(steps: []), from: source))
        #expect(nodes.map(\.title) == ["Apple", "Ghostty", "File", "View"])
        let allMenus = nodes.allSatisfy { $0.hasChildren }
        #expect(allMenus)
        #expect(nodes[2].path == MenuPath(steps: [.init(title: "File", index: 0)]))
    }

    @Test func itemsCarryStateShortcutsAndSeparators() throws {
        let file = MenuPath(steps: [.init(title: "File", index: 0)])
        let nodes = try #require(MenuModel.nodes(at: file, from: source))
        #expect(nodes[0].title == "New Window")
        #expect(nodes[0].shortcut == "⌘N")
        #expect(nodes[0].enabled)
        #expect(nodes[1].isSeparator)
        #expect(nodes[2].shortcut == "⇧⌘W")
        #expect(!nodes[3].enabled)
        #expect(nodes[3].shortcut == nil)
        #expect(nodes[2].path == MenuPath(steps: [.init(title: "File", index: 0), .init(title: "Close Window", index: 0)]))
    }

    @Test func equalTitlesAreToldApartByIndex() throws {
        let view = MenuPath(steps: [.init(title: "View", index: 0)])
        let nodes = try #require(MenuModel.nodes(at: view, from: source))
        #expect(nodes[0].checked)
        #expect(!nodes[1].checked)
        #expect(nodes[0].path.steps.last == .init(title: "Show Tab Bar", index: 0))
        #expect(nodes[1].path.steps.last == .init(title: "Show Tab Bar", index: 1))
        #expect(nodes[2].hasChildren)
    }

    @Test func aMenuThatCantBeReadIsNil() {
        #expect(MenuModel.nodes(at: MenuPath(steps: [.init(title: "Gone", index: 0)]), from: source) == nil)
    }

    @Test func pressingAVanishedItemFails() {
        let gone = MenuPath(steps: [.init(title: "File", index: 0), .init(title: "Print", index: 0)])
        #expect(!source.press(gone))
        let second = MenuPath(steps: [.init(title: "View", index: 0), .init(title: "Show Tab Bar", index: 2)])
        #expect(!source.press(second))
    }
}

@Suite struct MenuShortcutTests {
    @Test func modifierBitsBecomeGlyphsInMenuOrder() {
        #expect(MenuShortcut.text(char: "N", modifiers: 0, glyph: nil) == "⌘N")
        #expect(MenuShortcut.text(char: "N", modifiers: 1, glyph: nil) == "⇧⌘N")
        #expect(MenuShortcut.text(char: "T", modifiers: 2, glyph: nil) == "⌥⌘T")
        #expect(MenuShortcut.text(char: "W", modifiers: 3, glyph: nil) == "⌥⇧⌘W")
        #expect(MenuShortcut.text(char: "F", modifiers: 6, glyph: nil) == "⌃⌥⌘F")
        #expect(MenuShortcut.text(char: "Q", modifiers: 8, glyph: nil) == "Q")
        #expect(MenuShortcut.text(char: "q", modifiers: nil, glyph: nil) == "⌘Q")
    }

    @Test func specialKeysUseTheirGlyph() {
        #expect(MenuShortcut.text(char: nil, modifiers: 0, glyph: 11) == "⌘↩")
        #expect(MenuShortcut.text(char: nil, modifiers: 1, glyph: 23) == "⇧⌘⌫")
        #expect(MenuShortcut.text(char: nil, modifiers: 0, glyph: 100) == "⌘←")
        #expect(MenuShortcut.text(char: nil, modifiers: 8, glyph: 111) == "F1")
    }

    @Test func noShortcutIsNil() {
        #expect(MenuShortcut.text(char: nil, modifiers: nil, glyph: nil) == nil)
        #expect(MenuShortcut.text(char: nil, modifiers: 8, glyph: nil) == nil)
        #expect(MenuShortcut.text(char: "", modifiers: 0, glyph: nil) == nil)
    }
}
