/// One line of the Bindings tab: a shortcut and its action, or a folded 1…9 run.
public struct BindingRow: Equatable, Sendable {
    public var shortcuts: String
    public var action: String
    /// The toml keys this row stands for (nine for a folded run).
    public var keys: [String]
    public var count: Int
}

public enum BindingRows {
    public static func rows(mode: [(key: String, value: TomlValue)], folded: Bool) -> [BindingRow] {
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
                let first = symbols(mode[idx[0]].key)
                out.append(BindingRow(shortcuts: first + " … 9", action: parts[1] + " 1 … 9",
                                      keys: idx.map { mode[$0].key }, count: 9))
            } else {
                out.append(BindingRow(shortcuts: symbols(entry.key), action: describe(entry.value),
                                      keys: [entry.key], count: 1))
            }
        }
        return out
    }

    private static func symbols(_ key: String) -> String {
        Shortcut(aerospace: key)?.symbols ?? key
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
