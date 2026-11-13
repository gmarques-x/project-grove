import Foundation
import Testing
@testable import GroveKeysCore

/// Legends from a recorded `legends-*.json` fixture (scripts/record-legends.swift).
func fixtureLegends(_ name: String) throws -> Legends {
    let raw = try JSONDecoder().decode([String: RawTranslation].self, from: Data(fixture(name).utf8))
    return Legends(raw: Dictionary(uniqueKeysWithValues: raw.map { (UInt16($0.key)!, $0.value) }))
}

@Suite struct LegendsTests {
    @Test func ptLetterIsOneCapital() throws {
        let pt = try fixtureLegends("legends-pt-PT.json")
        #expect(pt.legend(keyCode: 41) == Legend(base: "Ç", shift: nil))
        #expect(pt.legend(keyCode: 0) == Legend(base: "A", shift: nil))
    }

    @Test func ptBaseAndShift() throws {
        let pt = try fixtureLegends("legends-pt-PT.json")
        #expect(pt.legend(keyCode: 18) == Legend(base: "1", shift: "!"))
        #expect(pt.legend(keyCode: 50) == Legend(base: "<", shift: ">"))
        #expect(pt.legend(keyCode: 10) == Legend(base: "§", shift: "±"))
    }

    @Test func deadKeysShowTheirAccent() throws {
        let pt = try fixtureLegends("legends-pt-PT.json")
        #expect(pt.legend(keyCode: 30) == Legend(base: "´", shift: "`"))
        #expect(pt.legend(keyCode: 39) == Legend(base: "~", shift: "^"))
        for code: UInt16 in [30, 39] {
            let legend = try #require(pt.legend(keyCode: code))
            for text in [legend.base, legend.shift ?? ""] {
                #expect(!text.isEmpty)
                #expect(!text.unicodeScalars.contains { $0.properties.generalCategory == .nonspacingMark })
            }
        }
    }

    @Test func combiningMarksShowTheirSpacingAccent() {
        let legends = Legends(raw: Self.letters.merging([33: RawTranslation(base: "\u{301}", shift: "\u{300}")]) { $1 })
        #expect(legends.legend(keyCode: 33) == Legend(base: "´", shift: "`"))
        let others = Legends(raw: Self.letters.merging([
            33: RawTranslation(base: "\u{302}", shift: "\u{303}"),
            30: RawTranslation(base: "\u{308}", shift: "\u{30A}"),
        ]) { $1 })
        #expect(others.legend(keyCode: 33) == Legend(base: "^", shift: "~"))
        #expect(others.legend(keyCode: 30) == Legend(base: "¨", shift: "\u{A0}\u{30A}"))
    }

    @Test func sameShiftShowsBaseOnly() {
        let legends = Legends(raw: Self.letters.merging([24: RawTranslation(base: "+", shift: "+")]) { $1 })
        #expect(legends.legend(keyCode: 24) == Legend(base: "+", shift: nil))
    }

    @Test func nothingPrintableIsNil() {
        let bases: [String?] = ["\t", "\r", " ", "\u{7f}", "", nil]
        for base in bases {
            let legends = Legends(raw: Self.letters.merging([24: RawTranslation(base: base, shift: "+")]) { $1 })
            #expect(legends.legend(keyCode: 24) == nil, "base \(String(describing: base))")
        }
        let us = Legends.us
        #expect(us.legend(keyCode: 36) == nil)
        #expect(us.legend(keyCode: 48) == nil)
        #expect(us.legend(keyCode: 49) == nil)
        #expect(us.legend(keyCode: 53) == nil)
    }

    @Test func noTableFallsBackToUS() {
        #expect(Legends(raw: [:]) == .us)
        // Nine letter keys print; the rest type nothing.
        var few: [UInt16: RawTranslation] = [:]
        for name in "abcdefghi" { few[KeyNames.code(for: String(name))!] = RawTranslation(base: String(name), shift: nil) }
        for name in "jklmnopqrstuvwxyz" { few[KeyNames.code(for: String(name))!] = RawTranslation(base: "", shift: "") }
        #expect(Legends(raw: few) == .us)
        // Ten is enough.
        few[KeyNames.code(for: "j")!] = RawTranslation(base: "j", shift: "J")
        #expect(Legends(raw: few) != .us)
    }

    @Test func usLegendsMatchTodaysCaps() throws {
        for cap in KeyboardLayout.rows(for: .ansi).flatMap({ $0 }) {
            // The arrows (123–126) aren't translated; they keep their glyphs.
            guard let code = cap.keyCode, code <= 50, cap.legend.count == 1 else { continue }
            let legend = try #require(Legends.us.legend(keyCode: code), "\(cap.legend)")
            #expect(legend.base == cap.legend.uppercased(), "\(cap.legend)")
        }
    }

    @Test func usMatchesItsFixture() throws {
        #expect(try fixtureLegends("legends-US.json") == .us)
    }

    @Test func symbolForKey() throws {
        let pt = try fixtureLegends("legends-pt-PT.json")
        #expect(pt.symbol(forKey: "semicolon") == "Ç")
        #expect(pt.symbol(forKey: "a") == "A")
        #expect(pt.symbol(forKey: "quote") == "~")
        #expect(pt.symbol(forKey: "space") == nil)
        #expect(pt.symbol(forKey: "left") == nil)
        #expect(pt.symbol(forKey: "nope") == nil)
        #expect(Legends.us.symbol(forKey: "semicolon") == ";")
    }

    /// Every letter key typing its letter, so a table isn't taken for "no table".
    static let letters: [UInt16: RawTranslation] = Dictionary(uniqueKeysWithValues:
        "abcdefghijklmnopqrstuvwxyz".map { c in
            (KeyNames.code(for: String(c))!, RawTranslation(base: String(c), shift: String(c).uppercased()))
        })
}
