public enum TapAction: String, Sendable {
    case escape, none
}

public struct HyperSettings: Equatable, Sendable {
    public var enabled = true
    public var tap: TapAction = .escape
    public var tapMs = 200
    public var cheatsheetMs = 500

    public init() {}
}

/// keys.toml as the app sees it: a validated TomlDocument with typed readers
/// and mutators. The document keeps comments and unknown sections.
public struct KeysFile: Equatable, Sendable {
    public private(set) var document: TomlDocument

    public init(document: TomlDocument) throws(TomlError) {
        try KeysFile.validate(document)
        self.document = document
    }

    public init(text: String) throws(TomlError) {
        try self.init(document: TomlDocument.parse(text))
    }

    // MARK: Reading

    public var hyper: HyperSettings {
        var h = HyperSettings()
        for e in document.section(["hyper"])?.entries ?? [] {
            switch (e.key, e.value) {
            case ("enabled", .bool(let b)): h.enabled = b
            case ("tap", .string(let s)): h.tap = TapAction(rawValue: s) ?? h.tap
            case ("tap_ms", .int(let n)): h.tapMs = n
            case ("cheatsheet_ms", .int(let n)): h.cheatsheetMs = n
            default: break
            }
        }
        return h
    }

    public var launch: [(key: String, bundleID: String)] {
        (document.section(["launch"])?.entries ?? []).compactMap { e in
            if case .string(let s) = e.value { return (key: e.key, bundleID: s) }
            return nil
        }
    }

    /// File order, with `main` first if present.
    public var modes: [(name: String, bindings: [(key: String, value: TomlValue)])] {
        let all = document.sections.filter { $0.path.count == 2 && $0.path[0] == "aerospace" }
        let ordered = all.filter { $0.path[1] == "main" } + all.filter { $0.path[1] != "main" }
        return ordered.map { s in (name: s.path[1], bindings: s.entries.map { (key: $0.key, value: $0.value) }) }
    }

    public func monitors(host: String) -> [(workspace: String, target: String)] {
        (document.section(["monitors", host])?.entries ?? []).compactMap { e in
            if case .string(let s) = e.value { return (workspace: e.key, target: s) }
            return nil
        }
    }

    // MARK: Writing

    public mutating func setHyper(_ h: HyperSettings) {
        set(["hyper"], "tap", .string(h.tap.rawValue))
        set(["hyper"], "tap_ms", .int(h.tapMs))
        set(["hyper"], "cheatsheet_ms", .int(h.cheatsheetMs))
        set(["hyper"], "enabled", .bool(h.enabled))
    }

    public mutating func setLaunch(key: String, bundleID: String) {
        set(["launch"], key, .string(bundleID))
    }

    public mutating func removeLaunch(key: String) {
        remove(["launch"], key)
    }

    public mutating func setBinding(mode: String, key: String, value: TomlValue) {
        set(["aerospace", mode], key, value)
    }

    public mutating func removeBinding(mode: String, key: String) {
        remove(["aerospace", mode], key)
    }

    public mutating func setMonitor(host: String, workspace: String, target: String) {
        set(["monitors", host], workspace, .string(target))
    }

    private mutating func set(_ path: [String], _ key: String, _ value: TomlValue) {
        let s = sectionIndex(path)
        if let e = document.sections[s].entries.firstIndex(where: { $0.key == key }) {
            document.sections[s].entries[e].value = value
        } else {
            document.sections[s].entries.append(TomlEntry(key: key, value: value))
        }
    }

    private mutating func remove(_ path: [String], _ key: String) {
        guard let s = document.sections.firstIndex(where: { $0.path == path }) else { return }
        document.sections[s].entries.removeAll { $0.key == key }
    }

    /// The section's index, creating it in the file's fixed order
    /// (hyper, launch, aerospace modes, then monitors and anything else).
    private mutating func sectionIndex(_ path: [String]) -> Int {
        if let i = document.sections.firstIndex(where: { $0.path == path }) { return i }
        func rank(_ p: [String]) -> Int {
            switch p.first {
            case "hyper": return 0
            case "launch": return 1
            case "aerospace": return 2
            default: return 3
            }
        }
        let after = document.sections.lastIndex { !$0.path.isEmpty && rank($0.path) <= rank(path) }
        let at: Int
        if let after {
            at = after + 1
        } else {
            at = document.sections.first?.path.isEmpty == true ? 1 : 0
        }
        document.sections.insert(TomlSection(path: path), at: at)
        return at
    }

    // MARK: Validation

    private static func validate(_ doc: TomlDocument) throws(TomlError) {
        for section in doc.sections {
            switch section.path.first {
            case "hyper" where section.path.count == 1:
                for e in section.entries { try validateHyper(e) }
            case "launch" where section.path.count == 1:
                for e in section.entries {
                    guard case .string = e.value else {
                        throw TomlError(line: e.line, message: "\"\(e.key)\" in [launch] must be an app bundle ID in quotes")
                    }
                }
            case "aerospace" where section.path.count == 2:
                for e in section.entries {
                    switch e.value {
                    case .string, .array: break
                    default:
                        throw TomlError(line: e.line, message: "\"\(e.key)\" must be a command in quotes, or a list of them")
                    }
                }
            case "monitors" where section.path.count == 2:
                for e in section.entries {
                    guard case .string = e.value else {
                        throw TomlError(line: e.line, message: "workspace \(e.key) must be assigned a monitor in quotes")
                    }
                }
            default:
                break
            }
        }
    }

    private static func validateHyper(_ e: TomlEntry) throws(TomlError) {
        switch (e.key, e.value) {
        case ("key", .string): break
        case ("enabled", .bool): break
        case ("tap", .string(let s)):
            guard TapAction(rawValue: s) != nil else {
                throw TomlError(line: e.line, message: "tap must be \"escape\" or \"none\"")
            }
        case ("tap_ms", .int(let n)), ("cheatsheet_ms", .int(let n)):
            guard n >= 0 else { throw TomlError(line: e.line, message: "\(e.key) can't be negative") }
        case ("key", _), ("enabled", _), ("tap", _), ("tap_ms", _), ("cheatsheet_ms", _):
            throw TomlError(line: e.line, message: "\(e.key) in [hyper] has the wrong kind of value")
        default:
            throw TomlError(line: e.line, message: "unknown setting \"\(e.key)\" in [hyper]")
        }
    }
}
