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

    /// The bindings listed under the keyboard, four to a row.
    @Test func theListedBindingsFollowTheBottomRow() {
        let extras = ["alt-shift-h", "alt-shift-j", "alt-shift-k", "alt-shift-l", "esc"]
        func n(_ name: String, _ d: L.Direction) -> String? { L.neighbor(of: name, d, extras: extras) }
        // Down from the bottom row: the column under the cap.
        #expect(n("space", .down) == "alt-shift-j")
        #expect(n("left", .down) == "alt-shift-l")
        #expect(n("down", .down) == "alt-shift-l")
        #expect(n("up", .down) == "down")
        // Inside the list.
        #expect(n("alt-shift-h", .right) == "alt-shift-j")
        #expect(n("alt-shift-h", .left) == nil)
        #expect(n("alt-shift-l", .right) == nil)
        #expect(n("alt-shift-h", .down) == "esc")
        #expect(n("alt-shift-j", .down) == nil)
        #expect(n("esc", .up) == "alt-shift-h")
        #expect(n("esc", .right) == nil)
        #expect(n("esc", .down) == nil)
        // Back up to the keyboard: the cap over the column.
        #expect(n("alt-shift-h", .up) == "space")
        #expect(n("alt-shift-j", .up) == "space")
        #expect(n("alt-shift-l", .up) == "up")
        // The caps move as without a list; with none, the bottom row is the end.
        #expect(n("1", .right) == "2")
        #expect(n("z", .down) == "space")
        #expect(L.neighbor(of: "space", .down, extras: []) == nil)
        // One listed binding: every column leads to it.
        #expect(L.neighbor(of: "right", .down, extras: ["esc"]) == "esc")
        #expect(L.neighbor(of: "esc", .up, extras: ["esc"]) == "space")
    }
}

@Suite struct KeyboardShapeTests {
    typealias L = KeyboardLayout

    @Test func isoRowsAddUpAndMatchTheSpec() {
        for shape in KeyboardShape.allCases {
            for row in L.rows(for: shape).prefix(4) {
                let sum = row.reduce(0) { $0 + $1.width }
                #expect(abs(sum - 14.5) < 0.01, "\(shape) \(row.map(\.legend))")
            }
            #expect(L.rows(for: shape).count == 5)
        }
        let iso = L.rows(for: .iso)
        #expect(iso[0].first?.name == "section")
        #expect(iso[0].first?.keyCode == 10)
        #expect(iso[0].first?.width == 1)
        #expect(iso[0].last?.name == "backspace" && iso[0].last?.width == 1.5)

        let row2 = iso[1]
        #expect(row2.first?.name == "tab" && row2.first?.width == 1.5)
        #expect(row2.count == 14)
        #expect(row2.last?.name == "enter" && row2.last?.tall == .top && row2.last?.width == 1)
        #expect(row2[row2.count - 2].name == "rightSquareBracket")

        let row3 = iso[2]
        #expect(row3.first?.legend == "caps" && row3.first?.width == 1.75)
        #expect(Array(row3.suffix(4).map(\.name)) == ["semicolon", "quote", "backslash", "enter"])
        #expect(row3[row3.count - 2].keyCode == 42)
        #expect(row3.last?.tall == .bottom && row3.last?.width == 0.75)

        let row4 = iso[3]
        #expect(row4.map(\.name) == [nil, "backtick", "z", "x", "c", "v", "b", "n", "m",
                                      "comma", "period", "slash", nil])
        #expect(row4.first?.modifier == .shift && row4.first?.width == 1.25)
        #expect(row4[1].keyCode == 50)
        #expect(row4.last?.modifier == .shift && row4.last?.width == 2.25)

        #expect(iso[4] == L.rows[4])
        // Nothing else is tall.
        #expect(iso.flatMap { $0 }.filter { $0.tall != nil }.count == 2)
        #expect(L.rows.flatMap { $0 }.allSatisfy { $0.tall == nil })
    }

    @Test func ansiRowsAreToday() {
        #expect(L.rows(for: .ansi) == L.rows)
        #expect(L.rows(for: .ansi).map { $0.map(\.name) } == L.rows.map { $0.map(\.name) })
        #expect(L.rows(for: .ansi)[0].first?.name == "backtick")
    }

    @Test func namesPerShape() {
        #expect(L.names(for: .iso).contains("section"))
        #expect(!L.names(for: .ansi).contains("section"))
        #expect(L.names(for: .iso).contains("backtick"))
        #expect(L.names(for: .ansi).contains("backtick"))
        #expect(L.names(for: .ansi) == L.names)
        #expect(L.names(for: .iso) == L.names.union(["section"]))
    }

    @Test func everyNamedCapHasItsKeyCode() {
        for shape in KeyboardShape.allCases {
            for cap in L.rows(for: shape).flatMap({ $0 }) {
                if let name = cap.name {
                    #expect(cap.keyCode != nil, "\(name)")
                    #expect(cap.keyCode == KeyNames.code(for: name), "\(name)")
                } else {
                    #expect(cap.keyCode == nil, "\(cap.legend)")
                }
            }
        }
        #expect(KeyNames.code(for: "section") == 10)
        #expect(KeyNames.name(10) == "section")
    }

    @Test func tallReturnNavigation() {
        func n(_ name: String, _ d: L.Direction) -> String? { L.neighbor(of: name, d, shape: .iso) }
        #expect(n("rightSquareBracket", .right) == "enter")
        #expect(n("backslash", .right) == "enter")
        #expect(n("enter", .left) == "rightSquareBracket")
        #expect(n("enter", .right) == nil)
        #expect(n("enter", .up) == "backspace")
        #expect(n("enter", .down) == "slash")
        #expect(n("backspace", .down) == "enter")
        #expect(n("quote", .right) == "backslash")
        #expect(n("backslash", .left) == "quote")
        // The rest of the ISO board.
        #expect(n("1", .left) == "section")
        #expect(n("section", .down) == "tab")
        #expect(n("z", .left) == "backtick")
        #expect(n("backtick", .left) == nil)
        #expect(n("a", .down) == "backtick")
        // ANSI is unchanged through the shape-taking call.
        #expect(L.neighbor(of: "enter", .up, shape: .ansi) == "backslash")
        #expect(L.neighbor(of: "section", .right, shape: .ansi) == nil)
    }

    @Test func tallReturnWithTheListedBindings() {
        let extras = ["esc"]
        #expect(L.neighbor(of: "enter", .left, extras: extras, shape: .iso) == "rightSquareBracket")
        #expect(L.neighbor(of: "space", .down, extras: extras, shape: .iso) == "esc")
        #expect(L.neighbor(of: "esc", .up, extras: extras, shape: .iso) == "space")
        // `section` is on the ISO board, not a listed binding.
        #expect(L.neighbor(of: "section", .right, extras: ["section"], shape: .iso) == "1")
    }

    /// `KBGetLayoutType` returns a four-character code: kKeyboardISO is
    /// 'ISO ' (0x49534F20) in Carbon; ANSI, JIS and unknown are ANSI here.
    @Test func shapeFromLayoutType() {
        #expect(KeyboardShape.from(layoutType: 0x4953_4F20) == .iso)    // 'ISO '
        #expect(KeyboardShape.from(layoutType: 0x414E_5349) == .ansi)   // 'ANSI'
        #expect(KeyboardShape.from(layoutType: 0x4A49_5320) == .ansi)   // 'JIS '
        #expect(KeyboardShape.from(layoutType: 0x3F3F_3F3F) == .ansi)   // '????'
        #expect(KeyboardShape.from(layoutType: 0) == .ansi)
        #expect(KeyboardShape.from(layoutType: 1) == .ansi)
        #expect(KeyboardShape.from(layoutType: 2) == .ansi)
    }
}
