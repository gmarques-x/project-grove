import GroveThemesCore

/// One line of the Bindings tab: a shortcut and its action, or a folded 1…9 run.
public struct BindingRow: Equatable, Sendable {
    public var shortcuts: String
    public var action: String
    /// The toml keys this row stands for (nine for a folded run).
    public var keys: [String]
    public var count: Int
}

public enum BindingRows {
    /// The shortcuts are written with `legends`, the keys' characters on
    /// the current input source (`⌥⇧ Ç` on Portuguese).
    public static func rows(mode: [(key: String, value: TomlValue)], folded: Bool,
                            legends: Legends = .us) -> [BindingRow] {
        var runs: [String: [Int]] = [:]  // "<mods>|<command>" → entry indices, indexed by digit-1
        var runOf: [Int: String] = [:]
        if folded {
            var candidates: [String: [Int: Int]] = [:]
            for (i, entry) in mode.enumerated() {
                guard let (prefix, digit) = split(entry.key), case .string(let v) = entry.value,
                      let (cmd, n) = split(v, separator: " "), n == digit else { continue }
                candidates[prefix + "|" + cmd, default: [:]][digit] = i
            }
            for (id, byDigit) in candidates where byDigit.count == 9 {
                runs[id] = (1...9).map { byDigit[$0]! }
                for i in byDigit.values { runOf[i] = id }
            }
        }

        var out: [BindingRow] = []
        var emitted: Set<String> = []
        for (i, entry) in mode.enumerated() {
            if let id = runOf[i] {
                guard emitted.insert(id).inserted else { continue }
                let idx = runs[id]!
                let parts = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let first = symbols(mode[idx[0]].key, legends)
                out.append(BindingRow(shortcuts: first + " … 9", action: parts[1] + " 1 … 9",
                                      keys: idx.map { mode[$0].key }, count: 9))
            } else {
                out.append(BindingRow(shortcuts: symbols(entry.key, legends), action: describe(entry.value),
                                      keys: [entry.key], count: 1))
            }
        }
        return out
    }

    // MARK: Selection

    /// ↑ (−1) and ↓ (1) on the Bindings tab, over the rows' ids in the order
    /// they are shown (the groups one after another): stops at the first and
    /// the last row. With no row selected (or one that is gone), ↓ selects
    /// the first and ↑ the last.
    public static func step(from current: String?, by step: Int, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let at = ids.firstIndex(of: current) else { return step > 0 ? ids.first : ids.last }
        return ids[min(max(at + step, 0), ids.count - 1)]
    }

    /// The row to select when `id` is removed: the one after it, else the
    /// one before; nil when it was the only one (or isn't listed).
    public static func neighbor(ofRemoved id: String, in ids: [String]) -> String? {
        guard let at = ids.firstIndex(of: id) else { return nil }
        if ids.indices.contains(at + 1) { return ids[at + 1] }
        return at > 0 ? ids[at - 1] : nil
    }

    private static func symbols(_ key: String, _ legends: Legends) -> String {
        Shortcut(aerospace: key)?.symbols(using: legends) ?? key
    }

    private static func describe(_ v: TomlValue) -> String {
        switch v {
        case .string(let s): return s
        case .array(let a): return a.joined(separator: ", ")
        case .int(let n): return String(n)
        case .bool(let b): return String(b)
        }
    }

    /// "alt-3" → ("alt", 3); "workspace 3" → ("workspace", 3). Digit 1…9 only.
    private static func split(_ text: String, separator: Character = "-") -> (String, Int)? {
        guard let at = text.lastIndex(of: separator) else { return nil }
        let tail = text[text.index(after: at)...]
        guard tail.count == 1, let d = Int(tail), (1...9).contains(d) else { return nil }
        let head = String(text[..<at])
        return head.isEmpty ? nil : (head, d)
    }
}
