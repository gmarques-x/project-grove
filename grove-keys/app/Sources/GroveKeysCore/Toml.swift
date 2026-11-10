import Foundation

/// The TOML subset keys.toml uses: comments, `[a.b]` / `[a."quoted"]` tables,
/// bare and quoted keys, strings, string arrays, integers and booleans.

public enum TomlValue: Equatable, Sendable {
    case string(String)
    case array([String])
    case int(Int)
    case bool(Bool)
}

public struct TomlEntry: Equatable, Sendable {
    public var key: String
    public var value: TomlValue
    public var leadingComments: [String]
    public var trailingComment: String?

    public init(key: String, value: TomlValue, leadingComments: [String] = [], trailingComment: String? = nil) {
        self.key = key
        self.value = value
        self.leadingComments = leadingComments
        self.trailingComment = trailingComment
    }
}

public struct TomlSection: Equatable, Sendable {
    /// `[]` is the top level, before any header.
    public var path: [String]
    public var leadingComments: [String]
    /// A comment on the header line itself, e.g. `[launch]   # Hyper + key`.
    public var trailingComment: String?
    public var entries: [TomlEntry]

    public init(path: [String], leadingComments: [String] = [], entries: [TomlEntry] = [], trailingComment: String? = nil) {
        self.path = path
        self.leadingComments = leadingComments
        self.entries = entries
        self.trailingComment = trailingComment
    }
}

public struct TomlError: Error, Equatable, Sendable {
    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public struct TomlDocument: Equatable, Sendable {
    public var sections: [TomlSection]
    /// Comment lines after the last entry.
    public var trailingComments: [String]

    public init(sections: [TomlSection] = [], trailingComments: [String] = []) {
        self.sections = sections
        self.trailingComments = trailingComments
    }

    public func section(_ path: [String]) -> TomlSection? {
        sections.first { $0.path == path }
    }

    /// Blank lines are not kept; the writer regenerates them.
    public static func parse(_ text: String) throws(TomlError) -> TomlDocument {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var sections: [TomlSection] = []
        var pending: [String] = []
        var i = 0

        while i < lines.count {
            let lineNo = i + 1
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1

            if trimmed.isEmpty {
                // A header comment at the top of the file, set off by a blank
                // line, belongs to the top level rather than to the first table.
                if sections.isEmpty, !pending.isEmpty {
                    sections.append(TomlSection(path: [], leadingComments: pending))
                    pending = []
                }
                continue
            }
            if trimmed.hasPrefix("#") {
                pending.append(trimmed)
                continue
            }

            var scanner = Scanner(Array(trimmed), line: lineNo)
            if trimmed.hasPrefix("[") {
                let path = try scanner.header()
                let comment = try scanner.endOfLine()
                if sections.contains(where: { $0.path == path }) {
                    throw TomlError(line: lineNo, message: "duplicate table [\(path.joined(separator: "."))]")
                }
                sections.append(TomlSection(path: path, leadingComments: pending, trailingComment: comment))
                pending = []
                continue
            }

            let key = try scanner.key()
            try scanner.expectEquals()
            // A multi-line array continues until its brackets balance.
            var value: TomlValue
            let valueStart = scanner.position
            while true {
                do {
                    value = try scanner.value()
                    break
                } catch let e where e.message == Scanner.needMore && i < lines.count {
                    scanner.position = valueStart
                    scanner.append("\n" + lines[i])
                    i += 1
                } catch let e where e.message == Scanner.needMore {
                    throw TomlError(line: lineNo, message: "unterminated array")
                }
            }
            let comment = try scanner.endOfLine()

            if sections.isEmpty {
                sections.append(TomlSection(path: []))
            }
            let last = sections.count - 1
            if sections[last].entries.contains(where: { $0.key == key }) {
                throw TomlError(line: lineNo, message: "duplicate key \"\(key)\"")
            }
            sections[last].entries.append(
                TomlEntry(key: key, value: value, leadingComments: pending, trailingComment: comment))
            pending = []
        }
        return TomlDocument(sections: sections, trailingComments: pending)
    }
}

private struct Scanner {
    static let needMore = "unterminated array"

    private var chars: [Character]
    private var pos = 0
    var position: Int { get { pos } set { pos = newValue } }
    private let line: Int

    init(_ chars: [Character], line: Int) {
        self.chars = chars
        self.line = line
    }

    mutating func append(_ more: String) { chars.append(contentsOf: more) }

    private func fail(_ message: String) -> TomlError { TomlError(line: line, message: message) }

    private var peek: Character? { pos < chars.count ? chars[pos] : nil }

    private mutating func skipSpaces() {
        while let c = peek, c == " " || c == "\t" { pos += 1 }
    }

    /// Whitespace, newlines and comments between array elements.
    private mutating func skipSpacesAndComments() {
        while let c = peek {
            if c == " " || c == "\t" || c == "\n" {
                pos += 1
            } else if c == "#" {
                while let d = peek, d != "\n" { pos += 1 }
            } else {
                break
            }
        }
    }

    private static func isBare(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-")
    }

    /// `[a.b."c d"]`, with `pos` on the opening bracket.
    mutating func header() throws(TomlError) -> [String] {
        pos += 1
        var path: [String] = []
        while true {
            skipSpaces()
            path.append(try keyPart(context: "table name"))
            skipSpaces()
            if peek == "." { pos += 1; continue }
            if peek == "]" { pos += 1; return path }
            throw fail("expected ] to close the table header")
        }
    }

    private mutating func keyPart(context: String) throws(TomlError) -> String {
        guard let c = peek else { throw fail("expected a \(context)") }
        if c == "\"" { return try basicString() }
        if c == "'" { return try literalString() }
        let start = pos
        while let d = peek, Scanner.isBare(d) { pos += 1 }
        if pos == start { throw fail("expected a \(context)") }
        return String(chars[start..<pos])
    }

    mutating func key() throws(TomlError) -> String {
        let k = try keyPart(context: "key")
        skipSpaces()
        if peek == "." { throw fail("dotted keys are not supported") }
        return k
    }

    mutating func expectEquals() throws(TomlError) {
        skipSpaces()
        guard peek == "=" else { throw fail("expected = after the key") }
        pos += 1
        skipSpaces()
    }

    mutating func value() throws(TomlError) -> TomlValue {
        guard let c = peek else { throw fail("missing value after =") }
        switch c {
        case "\"": return .string(try basicString())
        case "'": return .string(try literalString())
        case "[": return .array(try stringArray())
        case "{": throw fail("inline tables are not supported")
        default:
            let start = pos
            while let d = peek, d != " ", d != "\t", d != "#" { pos += 1 }
            let word = String(chars[start..<pos])
            if word == "true" { return .bool(true) }
            if word == "false" { return .bool(false) }
            if let n = Int(word) { return .int(n) }
            throw fail("unsupported value \(word)")
        }
    }

    /// The comment ending a line, if any; anything else is an error.
    mutating func endOfLine() throws(TomlError) -> String? {
        skipSpaces()
        guard let c = peek else { return nil }
        if c == "#" { return String(chars[pos...]) }
        throw fail("unexpected text after the value")
    }

    private mutating func basicString() throws(TomlError) -> String {
        pos += 1
        var out = ""
        while let c = peek {
            pos += 1
            switch c {
            case "\"":
                return out
            case "\\":
                guard let e = peek else { throw fail("unterminated string") }
                pos += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: throw fail("unsupported escape \\\(e)")
                }
            case "\n":
                throw fail("unterminated string")
            default:
                out.append(c)
            }
        }
        throw fail("unterminated string")
    }

    private mutating func literalString() throws(TomlError) -> String {
        pos += 1
        let start = pos
        while let c = peek {
            if c == "'" {
                pos += 1
                return String(chars[start..<(pos - 1)])
            }
            if c == "\n" { break }
            pos += 1
        }
        throw fail("unterminated string")
    }

    private mutating func stringArray() throws(TomlError) -> [String] {
        pos += 1
        var items: [String] = []
        while true {
            skipSpacesAndComments()
            guard let c = peek else { throw fail(Scanner.needMore) }
            if c == "]" { pos += 1; return items }
            guard c == "\"" || c == "'" else { throw fail("arrays must hold strings") }
            items.append(c == "\"" ? try basicString() : try literalString())
            skipSpacesAndComments()
            guard let d = peek else { throw fail(Scanner.needMore) }
            if d == "," { pos += 1 } else if d != "]" { throw fail("expected , or ] in the array") }
        }
    }
}
