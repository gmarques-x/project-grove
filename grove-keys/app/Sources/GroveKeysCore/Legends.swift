/// What `UCKeyTranslate` gave for one key with no modifiers and with Shift,
/// dead keys not composed. Nil when the call failed.
public struct RawTranslation: Codable, Sendable, Equatable {
    public var base: String?
    public var shift: String?

    public init(base: String?, shift: String?) {
        self.base = base
        self.shift = shift
    }
}

/// What a cap shows: its base character and, above it, its Shift character.
public struct Legend: Sendable, Equatable {
    public var base: String
    /// Nil for a one-line cap (a letter, or Shift typing the same).
    public var shift: String?

    public init(base: String, shift: String?) {
        self.base = base
        self.shift = shift
    }
}

/// The current input source's characters for each key, from its raw
/// translations. Keys that type nothing printable have no legend, so the cap
/// keeps its name (tab, return, space…).
public struct Legends: Sendable, Equatable {
    private var table: [UInt16: Legend]

    private init(table: [UInt16: Legend]) {
        self.table = table
    }

    /// A table in which fewer than 10 of the letter keys print (no key table,
    /// as with some input methods) gives the US legends.
    public init(raw: [UInt16: RawTranslation]) {
        let table = Self.legends(raw)
        let printingLetters = Self.letterCodes.filter { table[$0] != nil }.count
        self.table = printingLetters >= 10 ? table : Self.us.table
    }

    /// The US layout (recorded in Tests/…/Fixtures/legends-US.json).
    public static let us = Legends(table: legends(usRaw.mapValues { RawTranslation(base: $0.0, shift: $0.1) }))

    public func legend(keyCode: UInt16) -> Legend? { table[keyCode] }

    /// The single character a shortcut shows for an AeroSpace key name (`Ç`,
    /// `;`); nil to fall back to the name table (special keys, unknown names).
    public func symbol(forKey name: String) -> String? {
        guard let code = KeyNames.code(for: name), let base = table[code]?.base, base.count == 1 else { return nil }
        return base
    }

    // MARK: Raw translations to legends

    private static let letterCodes: [UInt16] = "abcdefghijklmnopqrstuvwxyz".compactMap { KeyNames.code(for: String($0)) }

    private static func legends(_ raw: [UInt16: RawTranslation]) -> [UInt16: Legend] {
        raw.compactMapValues(legend)
    }

    private static func legend(_ raw: RawTranslation) -> Legend? {
        guard let base = printable(raw.base) else { return nil }
        let shift = printable(raw.shift)
        if shift == nil || shift == base { return Legend(base: base, shift: nil) }
        if shift == base.uppercased() { return Legend(base: shift!, shift: nil) }
        return Legend(base: base, shift: shift)
    }

    /// The text spaced out for a cap; nil when empty, a control character or
    /// whitespace.
    private static func printable(_ text: String?) -> String? {
        guard let text = text.map(spacing), !text.isEmpty else { return nil }
        let scalars = text.unicodeScalars
        if scalars.contains(where: { $0.properties.generalCategory == .control }) { return nil }
        if scalars.allSatisfy(\.properties.isWhitespace) { return nil }
        return text
    }

    private static let spacingAccents: [Unicode.Scalar: String] = [
        "\u{301}": "´", "\u{300}": "`", "\u{302}": "^", "\u{303}": "~", "\u{308}": "¨",
    ]

    /// A combining mark on its own shows as its spacing accent, or after a
    /// no-break space when it has none.
    private static func spacing(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, isCombining(first) else { return text }
        if text.unicodeScalars.count == 1, let accent = spacingAccents[first] { return accent }
        return "\u{A0}" + text
    }

    private static func isCombining(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// From legends-US.json, as `UCKeyTranslate` gave it: (base, shift).
    private static let usRaw: [UInt16: (String, String)] = [
        0: ("a", "A"), 1: ("s", "S"), 2: ("d", "D"), 3: ("f", "F"),
        4: ("h", "H"), 5: ("g", "G"), 6: ("z", "Z"), 7: ("x", "X"),
        8: ("c", "C"), 9: ("v", "V"), 10: ("§", "±"), 11: ("b", "B"),
        12: ("q", "Q"), 13: ("w", "W"), 14: ("e", "E"), 15: ("r", "R"),
        16: ("y", "Y"), 17: ("t", "T"), 18: ("1", "!"), 19: ("2", "@"),
        20: ("3", "#"), 21: ("4", "$"), 22: ("6", "^"), 23: ("5", "%"),
        24: ("=", "+"), 25: ("9", "("), 26: ("7", "&"), 27: ("-", "_"),
        28: ("8", "*"), 29: ("0", ")"), 30: ("]", "}"), 31: ("o", "O"),
        32: ("u", "U"), 33: ("[", "{"), 34: ("i", "I"), 35: ("p", "P"),
        36: ("\r", "\r"), 37: ("l", "L"), 38: ("j", "J"), 39: ("'", "\""),
        40: ("k", "K"), 41: (";", ":"), 42: ("\\", "|"), 43: (",", "<"),
        44: ("/", "?"), 45: ("n", "N"), 46: ("m", "M"), 47: (".", ">"),
        48: ("\t", "\t"), 49: (" ", " "), 50: ("`", "~"),
    ]
}
