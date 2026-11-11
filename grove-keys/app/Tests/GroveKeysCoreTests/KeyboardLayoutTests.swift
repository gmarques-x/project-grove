import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct KeyboardLayoutTests {
    var caps: [KeyboardLayout.Cap] { KeyboardLayout.rows.flatMap { $0 } }

    @Test func fiveRows() {
        #expect(KeyboardLayout.rows.count == 5)
        #expect(KeyboardLayout.rows[0].first?.name == "backtick")
        #expect(KeyboardLayout.rows[0].last?.name == "backspace")
        #expect(KeyboardLayout.rows[2].first?.legend == "caps")
        #expect(KeyboardLayout.rows[4].map(\.name).compactMap { $0 } == ["space", "left", "up", "down", "right"])
    }

    @Test func everyNameHasAKeyCode() {
        for cap in caps {
            if let name = cap.name { #expect(KeyNames.keyCode(name) != nil, "\(name)") }
        }
    }

    @Test func namesAreUnique() {
        let names = caps.compactMap(\.name)
        #expect(Set(names).count == names.count)
    }

    /// Rows 1–4 of a MacBook ANSI board: 13+1.5, 1.5+12+1, 1.75+11+1.75, 2.25+10+2.25.
    @Test func rowWidths() {
        for row in KeyboardLayout.rows.prefix(4) {
            let sum = row.reduce(0) { $0 + $1.width }
            #expect(abs(sum - 14.5) < 0.01, "\(row.map(\.legend))")
        }
    }

    @Test func modifierCaps() {
        let mods = caps.compactMap(\.modifier)
        #expect(mods.filter { $0 == .shift }.count == 2)
        #expect(mods.filter { $0 == .alt }.count == 2)
        #expect(mods.filter { $0 == .cmd }.count == 2)
        #expect(mods.filter { $0 == .ctrl }.count == 1)
        #expect(caps.filter { $0.modifier != nil }.allSatisfy { $0.name == nil })
    }

    /// Every bare key the shipped keys.toml binds has a cap, except Escape,
    /// which a MacBook has in the function row; the Keyboard tab lists keys
    /// without a cap under the keyboard (mockup §1, Service's "esc reload").
    @Test func shippedKeysAreOnTheKeyboard() throws {
        let keys = try KeysFile(text: fixture("keys.toml"))
        let names = Set(caps.compactMap(\.name))
        var used: Set<String> = []
        for mode in keys.modes {
            for b in mode.bindings {
                if let sc = Shortcut(aerospace: b.key) { used.insert(sc.key) }
            }
        }
        used.formUnion(keys.launch.map(\.key))
        #expect(!used.isEmpty)
        #expect(used.subtracting(names) == ["esc"])
    }

    @Test func heldModifiersPerLayer() {
        #expect(KeyboardLayout.held(layerID: "hyper") == Set(Modifier.allCases))
        #expect(KeyboardLayout.held(layerID: "alt") == [.alt])
        #expect(KeyboardLayout.held(layerID: "alt-shift") == [.alt, .shift])
        #expect(KeyboardLayout.held(layerID: "cmd-ctrl") == [.cmd, .ctrl])
        #expect(KeyboardLayout.held(layerID: "none") == [])
        #expect(KeyboardLayout.held(layerID: "mode:service") == [])
    }

    /// The AeroSpace shortcut a bare key writes in a layer.
    @Test func shortcutPerLayer() {
        #expect(KeyboardLayout.shortcut(layerID: "hyper", key: "t") == "hyper-t")
        #expect(KeyboardLayout.shortcut(layerID: "alt", key: "1") == "alt-1")
        #expect(KeyboardLayout.shortcut(layerID: "alt-shift", key: "semicolon") == "alt-shift-semicolon")
        #expect(KeyboardLayout.shortcut(layerID: "ctrl-alt", key: "x") == "ctrl-alt-x")
        #expect(KeyboardLayout.shortcut(layerID: "none", key: "x") == "x")
        #expect(KeyboardLayout.shortcut(layerID: "mode:service", key: "r") == "r")
        #expect(KeyboardLayout.mode(layerID: "mode:service") == "service")
        #expect(KeyboardLayout.mode(layerID: "alt") == "main")
    }
}

@Suite struct CommandCatalogTests {
    @Test func entriesInOrder() {
        let templates = CommandCatalog.entries.map(\.template)
        #expect(templates == [
            "workspace N", "move-node-to-workspace N",
            "focus left", "focus down", "focus up", "focus right",
            "move left", "move down", "move up", "move right",
            "resize smart -50", "resize smart +50",
            "layout tiles horizontal vertical", "layout accordion horizontal vertical",
            "layout floating tiling", "workspace-back-and-forth",
            "move-workspace-to-monitor --wrap-around next", "mode service",
            "close", "reload-config", "fullscreen",
        ])
        #expect(Set(CommandCatalog.entries.map(\.title)).count == CommandCatalog.entries.count)
    }

    /// N becomes the key's digit, or 1 on a non-digit key.
    @Test func fillsN() {
        #expect(CommandCatalog.command(template: "workspace N", key: "3") == "workspace 3")
        #expect(CommandCatalog.command(template: "move-node-to-workspace N", key: "t") == "move-node-to-workspace 1")
        #expect(CommandCatalog.command(template: "focus left", key: "3") == "focus left")
    }

    /// Every catalog command gets its fixed short label and tint (on key 2).
    @Test func labelsComeFromTheTable() {
        let expected: [(String, BindingKind)] = [
            ("ws 2", .workspace), ("→ ws 2", .workspace),
            ("← focus", .focusMove), ("↓ focus", .focusMove), ("↑ focus", .focusMove), ("→ focus", .focusMove),
            ("← move", .focusMove), ("↓ move", .focusMove), ("↑ move", .focusMove), ("→ move", .focusMove),
            ("resize −", .layout), ("resize +", .layout),
            ("tiles", .layout), ("accordion", .layout), ("float/tile", .layout),
            ("back & forth", .workspace), ("→ monitor", .workspace), ("service", .mode),
            ("close", .other), ("reload", .mode), ("fullscreen", .layout),
        ]
        let got = CommandCatalog.entries.map {
            CommandLabel.label(.string(CommandCatalog.command(template: $0.template, key: "2")))
        }
        #expect(got.map(\.0) == expected.map(\.0))
        #expect(got.map(\.1) == expected.map(\.1))
    }
}

@Suite struct KeyboardNavigationTests {
    typealias L = KeyboardLayout

    @Test func sideways() {
        #expect(L.neighbor(of: "1", .right) == "2")
        #expect(L.neighbor(of: "1", .left) == "backtick")
        #expect(L.neighbor(of: "backtick", .left) == nil)
        #expect(L.neighbor(of: "a", .left) == nil)  // caps has no name
        #expect(L.neighbor(of: "backspace", .right) == nil)
        #expect(L.neighbor(of: "left", .right) == "up")
        #expect(L.neighbor(of: "down", .right) == "right")
        #expect(L.neighbor(of: "right", .left) == "up")
    }

    @Test func upAndDown() {
        #expect(L.neighbor(of: "q", .up) == "1")
        #expect(L.neighbor(of: "1", .down) == "q")
        #expect(L.neighbor(of: "a", .up) == "q")
        #expect(L.neighbor(of: "a", .down) == "z")
        #expect(L.neighbor(of: "z", .down) == "space")
        #expect(L.neighbor(of: "space", .up) != nil)
        #expect(L.neighbor(of: "1", .up) == nil)
        #expect(L.neighbor(of: "up", .down) == "down")
        #expect(L.neighbor(of: "down", .up) == "up")
        #expect(L.neighbor(of: "down", .down) == nil)
        #expect(L.neighbor(of: "enter", .up) == "backslash")
    }

    @Test func unknownKeyStartsAtOne() {
        #expect(L.neighbor(of: "nope", .right) == nil)
        #expect(L.firstKey == "1")
    }
}
