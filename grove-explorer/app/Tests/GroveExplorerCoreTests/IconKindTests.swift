import Foundation
import GroveExplorerCore
import Testing

@Suite struct IconKindTests {
    /// Never the real home: the named folders are matched against this one.
    private let home = URL(fileURLWithPath: "/Users/fern")

    /// A trimmed copy of grove-dotfiles/config/vscode/grove-icons/grove-icon-theme.json.
    private func fixtureMap() throws -> IconMap {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/grove-icon-theme.json")
        return try IconMap(themeJSON: Data(contentsOf: file))
    }

    private func entry(_ path: String, _ kind: Entry.Kind = .file) -> Entry {
        let url = URL(fileURLWithPath: path)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: nil, modified: nil,
            isHidden: false, typeDescription: "")
    }

    /// The icon of a file called `name`, by the fixture.
    private func icon(_ name: String, light: Bool = false) throws -> IconKind {
        try fixtureMap().kind(for: entry("/tmp/grove/\(name)"), light: light, home: home)
    }

    private func glyph(_ scalar: UInt32, _ colorHex: String) -> IconKind {
        .glyph(Glyph(character: Character(Unicode.Scalar(scalar)!), colorHex: colorHex))
    }

    // The fixture's values, as the real map has them (dark, then light).
    private var swiftDark: IconKind { glyph(0xE092, "#E69875") }
    private var swiftLight: IconKind { glyph(0xE092, "#F57D26") }
    private var markdownDark: IconKind { glyph(0xE060, "#7FBBB3") }
    private var markdownLight: IconKind { glyph(0xE060, "#3A94C5") }

    // MARK: Folders

    @Test func aFolderGetsTheGroveFolder() throws {
        let map = try fixtureMap()
        #expect(map.kind(for: entry("/tmp/grove/src", .folder), light: false, home: home) == .folder(.none))
        #expect(map.kind(for: entry("/tmp/grove/src", .folder), light: true, home: home) == .folder(.none))
        // A folder is a folder whatever its name says.
        #expect(map.kind(for: entry("/tmp/grove/notes.md", .folder), light: false, home: home) == .folder(.none))
    }

    @Test func theKnownFoldersAreMarkedByTheirPath() throws {
        let map = try fixtureMap()
        let marks: [(String, FolderMark)] = [
            ("/Users/fern", .home),
            ("/Users/fern/Developer", .developer),
            ("/Users/fern/Documents", .documents),
            ("/Users/fern/Downloads", .downloads),
            ("/Users/fern/Desktop", .desktop),
            ("/Applications", .applications),
        ]
        for (path, mark) in marks {
            #expect(map.kind(for: entry(path, .folder), light: false, home: home) == .folder(mark), "\(path)")
        }
    }

    @Test func aFolderOnlyNamedLikeAKnownOneIsPlain() throws {
        let map = try fixtureMap()
        for path in [
            "/Users/fern/work/Developer", "/Users/other/Documents", "/Users/fern/Applications",
            "/Volumes/Backup/Applications", "/Users", "/Users/fern/Downloads/Desktop",
        ] {
            #expect(map.kind(for: entry(path, .folder), light: false, home: home) == .folder(.none), "\(path)")
        }
    }

    @Test func theHomePassedInDecidesNotTheRealOne() throws {
        let map = try fixtureMap()
        let real = FileManager.default.homeDirectoryForCurrentUser
        #expect(map.kind(for: entry(real.path, .folder), light: false, home: home) == .folder(.none))
        #expect(map.kind(for: entry(real.path, .folder), light: false, home: real) == .folder(.home))
    }

    @Test func knownFolderPathsAreComparedStandardized() throws {
        let map = try fixtureMap()
        let untidyHome = URL(fileURLWithPath: "/Users/fern/Desktop/../", isDirectory: true)
        let untidy = Entry(
            url: URL(fileURLWithPath: "/Users/./fern/Documents/../Downloads/", isDirectory: true),
            name: "Downloads", kind: .folder, size: nil, modified: nil, isHidden: false, typeDescription: "Folder")
        #expect(map.kind(for: untidy, light: false, home: untidyHome) == .folder(.downloads))
    }

    @Test func aLinkToAFolderGetsThePlainFolderAndALinkToAFileItsNamesIcon() throws {
        let map = try fixtureMap()
        #expect(map.kind(for: entry("/tmp/grove/current", .symlink(toFolder: true)), light: false, home: home) == .folder(.none))
        // The link is not the known folder, even when it sits at its path.
        #expect(map.kind(for: entry("/Users/fern/Documents", .symlink(toFolder: true)), light: false, home: home) == .folder(.none))
        #expect(map.kind(for: entry("/tmp/grove/main.swift", .symlink(toFolder: false)), light: false, home: home) == swiftDark)
        #expect(map.kind(for: entry("/tmp/grove/gone", .symlink(toFolder: false)), light: false, home: home) == .system)
    }

    // MARK: What keeps its macOS icon

    @Test func aPackageAVolumeAndAnAliasKeepTheirMacOSIcon() throws {
        let map = try fixtureMap()
        #expect(map.kind(for: entry("/Applications/Notes.app", .package), light: false, home: home) == .system)
        #expect(map.kind(for: entry("/Volumes/Backup", .volume), light: false, home: home) == .system)
        #expect(map.kind(for: entry("/tmp/grove/Notes alias", .alias), light: false, home: home) == .system)
        // Not a folder and not a file: neither the path nor the name counts.
        #expect(map.kind(for: entry("/Applications", .package), light: false, home: home) == .system)
        #expect(map.kind(for: entry("/tmp/grove/main.swift", .alias), light: false, home: home) == .system)
        #expect(map.kind(for: entry("/tmp/grove/thing.swift", .package), light: true, home: home) == .system)
    }

    @Test func aDiskImageKeepsItsMacOSIconEvenWhenTheMapKnowsIt() throws {
        #expect(try icon("Grove.dmg") == .system)
        // A map that does give .dmg a glyph: the rule is Grove Explorer's, not the map's.
        let map = try IconMap(themeJSON: Data(Self.smallTheme.utf8))
        #expect(map.kind(for: entry("/tmp/grove/Grove.dmg"), light: false, home: home) == .system)
        #expect(map.kind(for: entry("/tmp/grove/GROVE.DMG"), light: true, home: home) == .system)
        #expect(map.kind(for: entry("/tmp/grove/dmg"), light: false, home: home) == glyph(0xE003, "#333333"))
    }

    // MARK: Grove glyphs

    @Test func aSwiftFileGetsTheSwiftGlyphInTheSchemesColour() throws {
        #expect(try icon("main.swift") == swiftDark)
        #expect(try icon("main.swift", light: true) == swiftLight)
    }

    @Test func theExtensionWinsOverTheName() throws {
        // By name the set gives README.md the info glyph and CHANGELOG.md the clock.
        for name in ["README.md", "CHANGELOG.md", "notes.md"] {
            #expect(try icon(name) == markdownDark, "\(name)")
            #expect(try icon(name, light: true) == markdownLight, "\(name)")
        }
        // karma.conf.js has a glyph of its own by name; it is a JavaScript file.
        #expect(try icon("karma.conf.js") == icon("app.js"))
    }

    @Test func aNameWithoutAKnownExtensionGetsItsNamesGlyph() throws {
        #expect(try icon("Makefile") == glyph(0xE05F, "#E69875"))
        #expect(try icon("Makefile", light: true) == glyph(0xE05F, "#F57D26"))
        #expect(try icon("Dockerfile") == glyph(0xE025, "#7FBBB3"))
        // From the map's own names table.
        #expect(try icon("README") == glyph(0xE04D, "#7FBBB3"))
        #expect(try icon("README", light: true) == glyph(0xE04D, "#3A94C5"))
        #expect(try icon("LICENSE") == glyph(0xE05A, "#DBBC7F"))
        // .lock and .txt mean nothing to the set; the whole name does.
        #expect(try icon("yarn.lock") != .system)
        #expect(try icon("todo.txt") != .system)
    }

    @Test func caseIsIgnored() throws {
        #expect(try icon("MAIN.SWIFT") == swiftDark)
        #expect(try icon("Notes.MD") == markdownDark)
        #expect(try icon("makefile") == icon("Makefile"))
        #expect(try icon("Readme") == icon("README"))
    }

    @Test func theMapsOwnExtensionsComeBeforeTheLanguageOnes() throws {
        // .h is in the map's extensions (purple); as the C language it would be blue.
        #expect(try icon("grove.h") == glyph(0xE00C, "#D699B6"))
        #expect(try icon("grove.c") == glyph(0xE00C, "#7FBBB3"))
        #expect(try icon("grove.toml") == glyph(0xE019, "#859289"))
        #expect(try icon("shot.png") == glyph(0xE04C, "#D699B6"))
        #expect(try icon("shot.png", light: true) == glyph(0xE04C, "#DF69BA"))
    }

    @Test func aDotFileIsKnownByWhatFollowsTheDot() throws {
        #expect(try icon(".gitattributes") == glyph(0xE034, "#7A8478"))
        #expect(try icon(".gitignore") == glyph(0xE034, "#7A8478"))
    }

    @Test func anUnknownTypeIsLeftToMacOS() throws {
        #expect(try icon("x.unknownext") == .system)
        #expect(try icon("x.unknownext", light: true) == .system)
        #expect(try icon("plain") == .system)
        #expect(try icon("ends-with-a-dot.") == .system)
        #expect(try icon(".") == .system)
    }

    // MARK: Compound extensions

    @Test func aCompoundExtensionIsTriedLongestFirst() throws {
        let map = try IconMap(themeJSON: Data(Self.smallTheme.utf8))
        func kind(_ name: String, light: Bool = false) -> IconKind {
            map.kind(for: entry("/tmp/grove/\(name)"), light: light, home: home)
        }
        #expect(kind("a.tar.gz") == glyph(0xE001, "#111111"))
        #expect(kind("a.tar.gz", light: true) == glyph(0xE001, "#AAAAAA"))
        #expect(kind("a.gz") == glyph(0xE002, "#222222"))
        // "txt.gz" isn't known, so it falls to "gz".
        #expect(kind("a.txt.gz") == glyph(0xE002, "#222222"))
        // "tar" alone isn't known and the name isn't either.
        #expect(kind("a.tar") == .system)
    }

    @Test func theRealMapsCompoundExtensions() throws {
        // A test file is the orange TypeScript, a plain one the blue.
        #expect(try icon("list.spec.ts") == glyph(0xE099, "#E69875"))
        #expect(try icon("list.ts") == glyph(0xE099, "#7FBBB3"))
        #expect(try icon("site.css.map") == icon("site.css"))
    }

    // MARK: Reading the map

    @Test func aLightTableWithoutAnEntryFallsBackToTheDarkOne() throws {
        // VS Code does the same: "light" only overrides.
        let map = try IconMap(themeJSON: Data(Self.smallTheme.utf8))
        let kind = map.kind(for: entry("/tmp/grove/a.onlydark"), light: true, home: home)
        #expect(kind == glyph(0xE002, "#222222"))
    }

    @Test func anAssociationWithoutAUsableDefinitionIsLeftToMacOS() throws {
        let map = try IconMap(themeJSON: Data(Self.smallTheme.utf8))
        for name in ["a.nodef", "a.nochar", "a.nocolor", "a.badchar"] {
            #expect(map.kind(for: entry("/tmp/grove/\(name)"), light: false, home: home) == .system, "\(name)")
        }
    }

    @Test func whatIsNotAnIconThemeIsRefused() {
        #expect(throws: (any Error).self) { try IconMap(themeJSON: Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try IconMap(themeJSON: Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try IconMap(themeJSON: Data(#"{"fileExtensions": {}}"#.utf8)) }
    }

    @Test func aThemeWithOnlyDefinitionsIsEnough() throws {
        let map = try IconMap(themeJSON: Data(#"{"iconDefinitions": {}}"#.utf8))
        #expect(map.kind(for: entry("/tmp/grove/main.swift"), light: true, home: home) == .system)
        #expect(map.kind(for: entry("/tmp/grove", .folder), light: true, home: home) == .folder(.none))
    }

    // MARK: The real map

    @Test func theRealMapResolvesTheWellKnownTypes() throws {
        // …/grove-explorer/app/Tests/GroveExplorerCoreTests/<this file>
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let dotfiles = repo.appendingPathComponent("grove-dotfiles")
        // The package built away from the repo has no file to hold to.
        guard FileManager.default.fileExists(atPath: dotfiles.path) else { return }
        let file = dotfiles.appendingPathComponent("config/vscode/grove-icons/grove-icon-theme.json")
        let map = try IconMap(themeJSON: Data(contentsOf: file))
        func kind(_ name: String, light: Bool = false) -> IconKind {
            map.kind(for: entry("/tmp/grove/\(name)"), light: light, home: home)
        }

        #expect(kind("main.swift") == swiftDark)
        #expect(kind("main.swift", light: true) == swiftLight)
        #expect(kind("README.md") == markdownDark)
        #expect(kind("README.md", light: true) == markdownLight)
        #expect(kind("Makefile") == glyph(0xE05F, "#E69875"))
        #expect(kind("x.unknownext") == .system)
        #expect(kind("Grove.dmg") == .system)

        // Every type Grove Explorer resolves through a language of the map has a
        // glyph in both sets: a language renamed in the map shows here.
        let names = [
            "a.md", "a.json", "a.js", "a.jsx", "a.ts", "a.tsx", "a.py", "a.sh", "a.bash", "a.zsh",
            "a.rb", "a.go", "a.rs", "a.c", "a.h", "a.cpp", "a.html", "a.css", "a.yml", "a.yaml",
            "a.toml", "a.lua", "a.swift", "a.java", "a.kt", "a.php", "a.sql", "a.xml",
            ".gitignore", ".env", "Makefile", "GNUmakefile", "Dockerfile",
            // And a few the map knows by itself.
            "a.png", "a.pdf", "a.zip", "LICENSE", "README",
        ]
        for name in names {
            for light in [false, true] {
                #expect(kind(name, light: light) != .system, "\(name), light: \(light)")
            }
            #expect(kind(name) != kind(name, light: true), "\(name): the light set has its own colour")
        }
    }

    /// Not the real map: what the real one has no case of.
    private static let smallTheme = #"""
        {
          "iconDefinitions": {
            "_targz": { "fontCharacter": "\\E001", "fontColor": "#111111" },
            "_targz_light": { "fontCharacter": "\\E001", "fontColor": "#AAAAAA" },
            "_gz": { "fontCharacter": "\\E002", "fontColor": "#222222" },
            "_gz_light": { "fontCharacter": "\\E002", "fontColor": "#BBBBBB" },
            "_disk": { "fontCharacter": "\\E003", "fontColor": "#333333" },
            "_nochar": { "fontColor": "#444444" },
            "_nocolor": { "fontCharacter": "\\E004" },
            "_badchar": { "fontCharacter": "\\XYZ", "fontColor": "#555555" }
          },
          "file": "_gz",
          "fileExtensions": {
            "tar.gz": "_targz", "gz": "_gz", "dmg": "_disk", "onlydark": "_gz",
            "nodef": "_missing", "nochar": "_nochar", "nocolor": "_nocolor", "badchar": "_badchar"
          },
          "fileNames": { "dmg": "_disk" },
          "languageIds": {},
          "light": {
            "file": "_gz_light",
            "fileExtensions": { "tar.gz": "_targz_light", "gz": "_gz_light", "dmg": "_disk" }
          }
        }
        """#
}
