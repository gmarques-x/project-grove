import Foundation

/// Ghostty's keys for the cheat sheet, from what `ghostty +list-keybinds`
/// prints: a line per binding, `keybind = super+shift+d=new_split:down`.
public enum GhosttyKeybinds {
    public static let binary = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    public static let arguments = ["+list-keybinds"]

    private struct Binding {
        var modifiers: Set<Modifier>
        var key: String
        var name: String
        var parameters: String
        var action: String { parameters.isEmpty ? name : name + ":" + parameters }
    }

    /// A readable subset of the listing (it has some ninety lines), in its order:
    /// - a key needs ⌃, ⌥ or ⌘ (so not the Copy and Paste keys, Escape, or
    ///   ⇧ with the arrows, which select text as everywhere);
    /// - not the `digit_N` twins of ⌘ 1 … 8, nor the bindings that send bytes
    ///   to the shell (`text:`, `esc:`, `csi:`), nor `unbind` and `ignore`;
    /// - an action bound to several keys is listed once, under the key with
    ///   the fewest modifiers (the first of them when equal);
    /// - `goto_tab:1` … `goto_tab:8` on ⌘ 1 … 8 fold into one row.
    /// Key sequences (`ctrl+a>n`) and lines that aren't bindings are skipped.
    public static func rows(listing: String, legends: Legends = .us) -> [CheatRow] {
        var kept: [Binding] = []
        for line in listing.split(whereSeparator: \.isNewline) {
            guard let binding = parse(String(line)),
                  !binding.modifiers.isDisjoint(with: [.ctrl, .alt, .cmd]),
                  !binding.key.hasPrefix("digit_"),
                  !["text", "esc", "csi", "unbind", "ignore"].contains(binding.name) else { continue }
            if let at = kept.firstIndex(where: { $0.action == binding.action }) {
                if binding.modifiers.count < kept[at].modifiers.count { kept[at] = binding }
            } else {
                kept.append(binding)
            }
        }

        var rows: [CheatRow] = []
        var folded: Set<String> = []
        for binding in kept {
            let run = kept.filter {
                $0.name == binding.name && $0.modifiers == binding.modifiers && $0.key == $0.parameters
                    && Int($0.key) != nil
            }
            // 1, 2, 3 … in a row, each on its own digit.
            let last = run.count
            if binding.key == binding.parameters, last >= 3, run.map(\.key) == (1...last).map(String.init) {
                guard folded.insert(binding.name).inserted else { continue }
                rows.append(CheatRow(id: "ghostty/\(binding.name)", keys: symbols(run[0], legends) + " … \(last)",
                                     text: words(binding.name, "1 … \(last)"),
                                     detail: binding.name))
            } else {
                rows.append(CheatRow(id: "ghostty/\(binding.action)", keys: symbols(binding, legends),
                                     text: words(binding.name, binding.parameters), detail: binding.action))
            }
        }
        return rows
    }

    /// `keybind = <prefix:>mod+mod+key=action:parameters`. The key can be `=`
    /// or `+` itself (`super+==increase_font_size:1`), so the trigger is read
    /// a part at a time.
    private static func parse(_ line: String) -> Binding? {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts[0] == "keybind" else { return nil }
        var rest = Substring(parts[1])
        for prefix in ["global:", "all:", "unconsumed:", "performable:"] {
            while rest.hasPrefix(prefix) { rest = rest.dropFirst(prefix.count) }
        }
        var names: [String] = []
        while true {
            guard let next = rest.first else { return nil }
            let part = next == "+" || next == "=" ? rest.prefix(1) : rest.prefix { $0 != "+" && $0 != "=" }
            names.append(String(part))
            rest = rest.dropFirst(part.count)
            guard let separator = rest.first else { return nil }
            rest = rest.dropFirst()
            if separator == "=" { break }
            guard separator == "+" else { return nil }
        }
        guard let key = names.last, !key.contains(">"), !rest.isEmpty else { return nil }
        var modifiers: Set<Modifier> = []
        for name in names.dropLast() {
            switch name {
            case "super", "cmd", "command": modifiers.insert(.cmd)
            case "ctrl", "control": modifiers.insert(.ctrl)
            case "alt", "opt", "option": modifiers.insert(.alt)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        let action = rest.split(separator: ":", maxSplits: 1).map(String.init)
        return Binding(modifiers: modifiers, key: key, name: action[0], parameters: action.count > 1 ? action[1] : "")
    }

    /// The key as the rest of the sheet writes one: `⌥⌘ ↑`.
    ///
    /// Ghostty matches a one-character trigger (`w`, `,`, `[`, `1`) by the
    /// character typed, wherever the layout puts it, so it is written as it
    /// is (a letter as a capital). A longer name (`backquote`, `arrow_up`)
    /// is a W3C physical key, a place on the keyboard: it is written with
    /// `legends`, what that place types (`⌃ <` for `ctrl+backquote` on a
    /// Portuguese ISO Mac).
    private static func symbols(_ binding: Binding, _ legends: Legends) -> String {
        if binding.key.count == 1 {
            // The US legends write a one-character name as itself.
            return Shortcut(modifiers: binding.modifiers, key: binding.key).symbols(using: .us)
        }
        let names = [
            "arrow_left": "left", "arrow_right": "right", "arrow_up": "up", "arrow_down": "down",
            "escape": "esc", "backquote": "backtick", "grave_accent": "backtick",
            "bracket_left": "leftSquareBracket", "bracket_right": "rightSquareBracket",
            "page_up": "Page Up", "page_down": "Page Down", "home": "Home", "end": "End",
        ]
        return Shortcut(modifiers: binding.modifiers, key: names[binding.key] ?? binding.key).symbols(using: legends)
    }

    /// `new_split` and `right` are "New split: right".
    private static func words(_ name: String, _ parameters: String) -> String {
        let said = name.replacingOccurrences(of: "goto_", with: "go_to_").replacingOccurrences(of: "_", with: " ")
        let title = said.prefix(1).uppercased() + said.dropFirst()
        guard !parameters.isEmpty else { return title }
        let list = parameters.split(separator: ",").joined(separator: ", ").replacingOccurrences(of: "_", with: " ")
        return title + ": " + list
    }
}
