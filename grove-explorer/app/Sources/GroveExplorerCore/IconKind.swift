import Foundation

/// One character of the Grove Icons font and the colour it is drawn in.
public struct Glyph: Equatable, Sendable {
    public let character: Character
    /// As the map writes it: "#7FBBB3".
    public let colorHex: String

    public init(character: Character, colorHex: String) {
        self.character = character
        self.colorHex = colorHex
    }
}

/// The mark cut out of the Grove folder for the folders everyone knows.
public enum FolderMark: String, Sendable, CaseIterable {
    case none, home, developer, documents, downloads, applications, desktop
}

/// Which icon an entry gets.
public enum IconKind: Equatable, Sendable {
    /// The Grove folder.
    case folder(FolderMark)
    /// A Grove Icons glyph.
    case glyph(Glyph)
    /// The icon macOS gives it.
    case system
}

/// The Grove Icons map (the VS Code icon theme file) and the rule that picks
/// an entry's icon from it.
public struct IconMap: Sendable {
    /// One side of the theme, dark or light, with each association already
    /// resolved to its glyph. Keys are lower-case, as the theme writes them.
    private struct GlyphSet: Sendable {
        var extensions: [String: Glyph] = [:]
        var names: [String: Glyph] = [:]
        var languages: [String: Glyph] = [:]
    }

    private let dark: GlyphSet
    private let light: GlyphSet

    /// Reads a VS Code icon theme: `iconDefinitions`, the three tables
    /// (`fileExtensions`, `fileNames`, `languageIds`) and the same three under
    /// `light`. Throws when the data isn't such a file; an association whose
    /// definition is missing or unusable is left out, so the type falls to
    /// macOS's icon.
    public init(themeJSON: Data) throws {
        let theme = try JSONDecoder().decode(Theme.self, from: themeJSON)
        var glyphs: [String: Glyph] = [:]
        for (name, definition) in theme.iconDefinitions {
            glyphs[name] = definition.glyph
        }
        func resolved(_ table: [String: String]?) -> [String: Glyph] {
            (table ?? [:]).compactMapValues { glyphs[$0] }
        }
        func set(_ tables: Theme.Tables) -> GlyphSet {
            GlyphSet(
                extensions: resolved(tables.fileExtensions), names: resolved(tables.fileNames),
                languages: resolved(tables.languageIds))
        }
        let dark = set(theme.tables)
        var light = dark
        // As in VS Code, "light" only overrides: what it leaves out stays.
        if let overrides = theme.light.map(set) {
            light.extensions.merge(overrides.extensions) { $1 }
            light.names.merge(overrides.names) { $1 }
            light.languages.merge(overrides.languages) { $1 }
        }
        self.dark = dark
        self.light = light
    }

    /// The icon for `entry`: a folder is the Grove folder (marked when it is
    /// one of the known ones under `home`, or /Applications); an app, a volume
    /// and an alias keep macOS's icon; a file gets its Grove glyph from the
    /// dark or the light set, and macOS's icon when the set has none.
    ///
    /// A file with a custom icon of its own keeps it too, but that is not in
    /// an `Entry`: whoever draws the icon checks it before asking here.
    public func kind(for entry: Entry, light: Bool, home: URL) -> IconKind {
        switch entry.kind {
        case .folder:
            return .folder(Self.mark(for: entry.url, home: home))
        case .symlink(toFolder: true):
            return .folder(.none)
        case .package, .volume, .alias:
            return .system
        case .file, .symlink(toFolder: false):
            return glyph(forFileNamed: entry.name, in: light ? self.light : dark).map(IconKind.glyph) ?? .system
        }
    }

    // MARK: Folders

    private static func mark(for folder: URL, home: URL) -> FolderMark {
        let path = folder.standardizedFileURL.path
        let home = home.standardizedFileURL
        if path == home.path { return .home }
        if path == "/Applications" { return .applications }
        let inHome: [(String, FolderMark)] = [
            ("Developer", .developer), ("Documents", .documents),
            ("Downloads", .downloads), ("Desktop", .desktop),
        ]
        return inHome.first { path == home.appendingPathComponent($0.0).path }?.1 ?? .none
    }

    // MARK: Files

    /// The extension first, the longest known one ("tar.gz" before "gz"), then
    /// the whole name. The set itself puts the name first; here README.md,
    /// CHANGELOG.md and notes.md are all Markdown.
    private func glyph(forFileNamed name: String, in set: GlyphSet) -> Glyph? {
        let name = name.lowercased()
        let extensions = Self.extensions(of: name)
        if let last = extensions.last, Self.diskImages.contains(last) { return nil }
        for ext in extensions {
            if let glyph = set.extensions[ext] { return glyph }
            if let language = Self.languageOfExtension[ext], let glyph = set.languages[language] { return glyph }
        }
        if let glyph = set.names[name] { return glyph }
        if let language = Self.languageOfName[name], let glyph = set.languages[language] { return glyph }
        return nil
    }

    /// What follows each dot of the name, longest first: "a.tar.gz" gives
    /// "tar.gz" and "gz"; ".gitignore" gives "gitignore"; "Makefile" nothing.
    private static func extensions(of name: String) -> [String] {
        name.indices.filter { name[$0] == "." }
            .map { String(name[name.index(after: $0)...]) }
            .filter { !$0.isEmpty }
    }

    /// A disk image keeps its macOS icon whatever the set says.
    private static let diskImages: Set<String> = ["dmg", "sparseimage", "sparsebundle", "iso"]

    /// VS Code finds these types through the file's language, which the theme
    /// lists under `languageIds` and not under `fileExtensions`. There is no
    /// VS Code here to name the language, so this table does: extension to
    /// the theme's language id. The theme's own extensions are asked first,
    /// so its .h and .kt win over the lines here, and .toml needs none.
    private static let languageOfExtension: [String: String] = [
        "md": "markdown",
        "json": "json",
        "js": "javascript", "jsx": "javascriptreact",
        "ts": "typescript", "tsx": "typescriptreact",
        "py": "python",
        "sh": "shellscript", "bash": "shellscript", "zsh": "shellscript",
        "rb": "ruby",
        "go": "go",
        "rs": "rust",
        "c": "c", "h": "c",
        "cpp": "cpp",
        "html": "html",
        "css": "css",
        "yml": "yaml", "yaml": "yaml",
        "lua": "lua",
        "swift": "swift",
        "java": "java",
        "kt": "kotlin",
        "php": "php",
        "sql": "sql",
        "xml": "xml",
        "gitignore": "ignore",
        "env": "dotenv",
    ]

    /// The same for whole names without an extension.
    private static let languageOfName: [String: String] = [
        "makefile": "makefile", "gnumakefile": "makefile",
        "dockerfile": "dockerfile",
    ]
}

// MARK: The theme file

private struct Theme: Decodable {
    struct Definition: Decodable {
        let fontCharacter: String?
        let fontColor: String?

        /// "\E001" is the character U+E001. Nil without a character or a colour.
        var glyph: Glyph? {
            guard let fontCharacter, let fontColor, fontCharacter.hasPrefix("\\"),
                let code = UInt32(fontCharacter.dropFirst(), radix: 16),
                let scalar = Unicode.Scalar(code)
            else { return nil }
            return Glyph(character: Character(scalar), colorHex: fontColor)
        }
    }

    struct Tables: Decodable {
        let fileExtensions: [String: String]?
        let fileNames: [String: String]?
        let languageIds: [String: String]?
    }

    let iconDefinitions: [String: Definition]
    /// The dark side's tables sit at the top level of the file.
    let tables: Tables
    let light: Tables?

    private enum CodingKeys: String, CodingKey { case iconDefinitions, light }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iconDefinitions = try container.decode([String: Definition].self, forKey: .iconDefinitions)
        light = try container.decodeIfPresent(Tables.self, forKey: .light)
        tables = try Tables(from: decoder)
    }
}
