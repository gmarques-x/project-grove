import Foundation
import GroveThemesCore

/// monitors.toml as the app sees it: this Mac's workspace → monitor table,
/// a validated TomlDocument like KeysFile (comments and unknown tables are
/// kept). The file sits next to keys.toml but is not tracked by git, so each
/// Mac has its own and no machine name is needed. No file means no assignments.
public struct MonitorsFile: Equatable, Sendable {
    public static let unreadable = "monitors.toml can't be read"
    /// What the app starts from on the first change in the Monitors panel.
    static let fresh = """
        # Grove Keys: the monitor each AeroSpace workspace goes to, on this Mac only.
        # Not tracked by git. Edit here or in the Grove Keys window; both write this file.

        [monitors] # workspace → "main" | "secondary" | "built-in" | a display name

        """

    public private(set) var document: TomlDocument

    /// No assignments yet: the comment header and an empty `[monitors]`.
    public init() {
        try! self.init(text: Self.fresh)
    }

    public init(document: TomlDocument) throws(TomlError) {
        try MonitorsFile.validate(document)
        self.document = document
    }

    public init(text: String) throws(TomlError) {
        try self.init(document: TomlDocument.parse(text))
    }

    /// The file at `url`, or no assignments when it isn't there. A file that
    /// is there but can't be read (or isn't UTF-8) is a line-0 error.
    public static func read(from url: URL) throws(TomlError) -> MonitorsFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return MonitorsFile() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw TomlError(line: 0, message: unreadable)
        }
        return try MonitorsFile(text: text)
    }

    /// File order.
    public var assignments: [(workspace: String, target: String)] {
        (document.section(["monitors"])?.entries ?? []).compactMap { e in
            if case .string(let s) = e.value { return (workspace: e.key, target: s) }
            return nil
        }
    }

    public mutating func set(workspace: String, target: String) {
        let s: Int
        if let i = document.sections.firstIndex(where: { $0.path == ["monitors"] }) {
            s = i
        } else {
            document.sections.append(TomlSection(path: ["monitors"]))
            s = document.sections.count - 1
        }
        if let e = document.sections[s].entries.firstIndex(where: { $0.key == workspace }) {
            document.sections[s].entries[e].value = .string(target)
        } else {
            document.sections[s].entries.append(TomlEntry(key: workspace, value: .string(target)))
        }
    }

    private static func validate(_ doc: TomlDocument) throws(TomlError) {
        for e in doc.section(["monitors"])?.entries ?? [] {
            guard case .string = e.value else {
                throw TomlError(line: e.line, message: "workspace \(e.key) must be assigned a monitor in quotes")
            }
        }
    }
}
