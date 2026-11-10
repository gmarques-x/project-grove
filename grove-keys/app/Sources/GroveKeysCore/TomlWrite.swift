import Foundation

extension TomlDocument {
    /// Writes the document back out: strings in `"…"`, arrays as `["a", "b"]`,
    /// one blank line before each header except the first thing in the file,
    /// comments where they were. Always ends with a newline.
    public func serialized() -> String {
        var out: [String] = []
        for section in sections {
            if !out.isEmpty { out.append("") }
            out.append(contentsOf: section.leadingComments)
            if !section.path.isEmpty {
                var header = "[" + section.path.enumerated().map { i, part in
                    TomlDocument.headerPart(part, first: i == 0)
                }.joined(separator: ".") + "]"
                if let c = section.trailingComment { header += " " + c }
                out.append(header)
            }
            for entry in section.entries {
                out.append(contentsOf: entry.leadingComments)
                var line = TomlDocument.keyText(entry.key) + " = " + TomlDocument.valueText(entry.value)
                if let c = entry.trailingComment { line += " " + c }
                out.append(line)
            }
        }
        out.append(contentsOf: trailingComments)
        return out.joined(separator: "\n") + "\n"
    }

    private static func isBare(_ s: String, allowHyphen: Bool) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || (allowHyphen && $0 == "-")) }
    }

    private static func keyText(_ key: String) -> String {
        isBare(key, allowHyphen: true) ? key : quoted(key)
    }

    /// Names after the first (a mode, a host name) are quoted when they hold
    /// anything but letters, digits and underscores, as in `[monitors."Mac-Air"]`.
    private static func headerPart(_ part: String, first: Bool) -> String {
        isBare(part, allowHyphen: first) ? part : quoted(part)
    }

    private static func quoted(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.append(c)
            }
        }
        return out + "\""
    }

    private static func valueText(_ v: TomlValue) -> String {
        switch v {
        case .string(let s): return quoted(s)
        case .array(let items): return "[" + items.map(quoted).joined(separator: ", ") + "]"
        case .int(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        }
    }
}
