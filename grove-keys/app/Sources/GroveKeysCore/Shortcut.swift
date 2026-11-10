public enum Modifier: String, Sendable, CaseIterable {
    case cmd, ctrl, alt, shift
}

/// An AeroSpace shortcut such as `alt-shift-1` or `hyper-t`.
public struct Shortcut: Hashable, Sendable {
    public var modifiers: Set<Modifier>
    public var key: String

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses `mod-mod-key`; `hyper` stands for all four modifiers. Nil for an
    /// empty key or an unknown modifier.
    public init?(aerospace text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }
        var mods: Set<Modifier> = []
        for p in parts.dropLast() {
            if p == "hyper" {
                mods.formUnion(Modifier.allCases)
            } else if let m = Modifier(rawValue: p) {
                mods.insert(m)
            } else {
                return nil
            }
        }
        self.init(modifiers: mods, key: key)
    }

    public var isHyper: Bool { modifiers == Set(Modifier.allCases) }

    /// AeroSpace's order is cmd-ctrl-alt-shift; all four are written as `hyper-`.
    public var aerospace: String {
        if isHyper { return "hyper-" + key }
        let order: [Modifier] = [.cmd, .ctrl, .alt, .shift]
        return (order.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "-")
    }

    /// Mac order ⌃⌥⇧⌘, a space, then the key: `⌃⌥⇧⌘ T`, `⌥⇧ 1`, `Esc`.
    public var symbols: String {
        let glyphs: [(Modifier, String)] = [(.ctrl, "⌃"), (.alt, "⌥"), (.shift, "⇧"), (.cmd, "⌘")]
        let mods = glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return mods.isEmpty ? keySymbol : mods + " " + keySymbol
    }

    private var keySymbol: String {
        switch key {
        case "minus": return "-"
        case "equal": return "="
        case "leftSquareBracket": return "["
        case "rightSquareBracket": return "]"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "quote": return "'"
        case "comma": return ","
        case "period": return "."
        case "slash": return "/"
        case "backtick": return "`"
        case "tab": return "⇥"
        case "enter": return "↩"
        case "esc": return "Esc"
        case "backspace": return "⌫"
        case "space": return "Space"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        default: return key.count == 1 ? key.uppercased() : key
        }
    }
}
