import Foundation
@testable import GroveExplorerCore
import Testing

/// The config from its two files' texts. No test touches a real folder:
/// `home` is made up and `exists` is the test's own.
@Suite struct ExplorerConfigTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func load(tracked: String? = ExplorerConfig.builtIn, local: String? = nil,
                      exists: (URL) -> Bool = { _ in true }) -> ExplorerConfig {
        ExplorerConfig.load(tracked: tracked, local: local, home: home, exists: exists)
    }

    // MARK: The shipped file

    @Test func theShippedFileGivesTheFiveFavouritesInOrder() {
        let config = load()
        #expect(config.favourites == [
            Favourite(id: "applications", url: folder("/Applications"), title: "Applications"),
            Favourite(id: "home", url: home, title: "Home"),
            Favourite(id: "developer", url: folder("/Users/someone/Developer"), title: "Developer"),
            Favourite(id: "documents", url: folder("/Users/someone/Documents"), title: "Documents"),
            Favourite(id: "downloads", url: folder("/Users/someone/Downloads"), title: "Downloads"),
        ])
        #expect(config.start == home)
        #expect(config.showHidden == false)
        #expect(config.twoPanes == false)
        #expect(config.problem == nil)
    }

    @Test func theTrackedFileOnDiskIsTheBuiltInText() throws {
        // …/grove-explorer/app/Tests/GroveExplorerCoreTests/<this file>
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let dotfiles = repo.appendingPathComponent("grove-dotfiles")
        // The package built away from the repo has no file to hold to.
        guard FileManager.default.fileExists(atPath: dotfiles.path) else { return }
        let file = dotfiles.appendingPathComponent("config/grove-explorer/explorer.toml")
        #expect(try String(contentsOf: file, encoding: .utf8) == ExplorerConfig.builtIn)
    }

    @Test func aMissingTrackedFileGivesTheBuiltInDefaultsQuietly() {
        #expect(load(tracked: nil) == load())
    }

    // MARK: Favourites

    @Test func aFavouriteWhoseFolderIsNotThereIsLeftOut() {
        let config = load(exists: { $0.path != "/Users/someone/Developer" })
        #expect(config.favourites.map(\.id) == ["applications", "home", "documents", "downloads"])
        #expect(config.problem == nil)
    }

    @Test func aFavouriteWithoutATitleIsCalledByItsFolder() {
        let config = load(tracked: """
            [favourites.work]
            path = "~/Developer/project grove"
            """)
        #expect(config.favourites == [
            Favourite(id: "work", url: folder("/Users/someone/Developer/project grove"), title: "project grove"),
        ])
    }

    @Test func tildeIsTheHomePassedInAndNoOtherPathStartsThere() {
        let config = load(tracked: """
            [general]
            start = "~/Documents"

            [favourites.tilde]
            path = "/Volumes/~"
            """)
        #expect(config.start == folder("/Users/someone/Documents"))
        #expect(config.favourites.map(\.url) == [folder("/Volumes/~")])
    }

    @Test func anyFavouriteInTheLocalFileReplacesTheWholeList() {
        let config = load(local: """
            [favourites.music]
            path = "~/Music"
            title = "Songs"
            """)
        #expect(config.favourites == [
            Favourite(id: "music", url: folder("/Users/someone/Music"), title: "Songs"),
        ])
        #expect(config.problem == nil)
    }

    @Test func aLocalFileWithoutFavouritesKeepsTheTrackedList() {
        let config = load(local: "[general]\ntwo_panes = true\n")
        #expect(config.favourites.count == 5)
    }

    // MARK: [general]

    @Test func localGeneralKeysOverrideOneByOne() {
        let tracked = """
            [general]
            start = "~/Documents"
            show_hidden = true
            two_panes = false
            """
        let one = load(tracked: tracked, local: "[general]\ntwo_panes = true\n")
        #expect(one.start == folder("/Users/someone/Documents"))
        #expect(one.showHidden == true)
        #expect(one.twoPanes == true)

        let other = load(tracked: tracked, local: "[general]\nstart = \"/Applications\"\nshow_hidden = false\n")
        #expect(other.start == folder("/Applications"))
        #expect(other.showHidden == false)
        #expect(other.twoPanes == false)
    }

    @Test func aKeyTheTrackedFileLeavesOutHasItsBuiltInValue() {
        let config = load(tracked: "[general]\nshow_hidden = true\n")
        #expect(config.start == home)
        #expect(config.showHidden == true)
        #expect(config.twoPanes == false)
        #expect(config.favourites.isEmpty)
        #expect(config.problem == nil)
    }

    @Test func aStartFolderThatIsNotThereGivesHome() {
        let config = load(tracked: "[general]\nstart = \"/Volumes/Gone\"\n", exists: { $0.path != "/Volumes/Gone" })
        #expect(config.start == home)
        #expect(config.problem == nil)
    }

    // MARK: Broken files

    @Test func aBrokenTrackedFileGivesTheBuiltInDefaultsAndNamesTheLine() {
        let config = load(tracked: """
            [general]
            start = "/Applications"
            show_hidden = true

            [favourites.music]
            path = "~/Music
            """)
        #expect(config.problem == "explorer.toml line 6: unterminated string")
        var expected = load()
        expected.problem = config.problem
        #expect(config == expected)
    }

    @Test func aBrokenLocalFileGivesTheTrackedValuesAndNamesTheLine() {
        let tracked = """
            [general]
            two_panes = true

            [favourites.music]
            path = "~/Music"
            """
        let config = load(tracked: tracked, local: "[general]\nshow_hidden = true\nstart = \n")
        #expect(config.problem == "explorer.local.toml line 3: missing value after =")
        var expected = load(tracked: tracked)
        expected.problem = config.problem
        #expect(config == expected)
    }

    @Test func aLocalFileStillCountsOverABrokenTrackedOne() {
        let config = load(tracked: "[general", local: "[general]\ntwo_panes = true\n")
        #expect(config.problem == "explorer.toml line 1: expected ] to close the table header")
        #expect(config.twoPanes == true)
        #expect(config.favourites.count == 5)
    }

    @Test(arguments: [
        ("[general]\nshow_hidden = \"yes\"\n", "explorer.toml line 2: \"show_hidden\" must be true or false"),
        ("[general]\ntwo_panes = 1\n", "explorer.toml line 2: \"two_panes\" must be true or false"),
        ("[general]\nstart = true\n", "explorer.toml line 2: \"start\" must be a string"),
        ("[general]\nstart = \"Documents\"\n", "explorer.toml line 2: \"start\" must start with / or ~/"),
        ("[general]\nstart = \"~someone\"\n", "explorer.toml line 2: \"start\" must start with / or ~/"),
        ("[general]\ncolour = \"green\"\n", "explorer.toml line 2: unknown key \"colour\""),
        ("start = \"~\"\n", "explorer.toml line 1: \"start\" is outside a table"),
        ("[favorites.music]\npath = \"~/Music\"\n", "explorer.toml line 2: unknown table [favorites.music]"),
        ("[favourites.a.b]\npath = \"~/Music\"\n", "explorer.toml line 2: unknown table [favourites.a.b]"),
        ("[favourites]\npath = \"~/Music\"\n", "explorer.toml line 2: a favourite is a table of its own: [favourites.name]"),
        ("[favourites.music]\npath = \"\"\n", "explorer.toml line 2: \"path\" must start with / or ~/"),
        ("[favourites.music]\npath = [\"~/Music\"]\n", "explorer.toml line 2: \"path\" must be a string"),
        ("[favourites.music]\npath = \"~/Music\"\ntitle = \"\"\n",
         "explorer.toml line 3: \"title\" must be a string with text in it"),
        ("[favourites.music]\npath = \"~/Music\"\nicon = \"note\"\n", "explorer.toml line 3: unknown key \"icon\""),
        ("[favourites.music]\ntitle = \"Songs\"\n", "explorer.toml line 2: [favourites.music] has no \"path\""),
        ("[general]\n\n[favourites.music]\n", "explorer.toml: [favourites.music] has no \"path\""),
    ])
    func whatAFileMayNotHold(text: String, problem: String) {
        let config = load(tracked: text)
        #expect(config.problem == problem)
        #expect(config.favourites.count == 5)
    }

    // MARK: The local file's text

    @Test func theLocalTextRoundTripsThroughLoad() {
        let favourites = [
            Favourite(id: "home", url: home, title: "Home"),
            Favourite(id: "work", url: folder("/Users/someone/Developer/project grove"), title: "Work \"now\""),
            Favourite(id: "disk 2", url: folder("/Volumes/Disk 2"), title: "Disk 2"),
            Favourite(id: "namesake", url: folder("/Users/someone else/Music"), title: "Music"),
        ]
        let text = ExplorerConfig.localText(favourites: favourites, home: home)
        #expect(text == """
            [favourites.home]
            path = "~"
            title = "Home"

            [favourites.work]
            path = "~/Developer/project grove"
            title = "Work \\"now\\""

            [favourites."disk 2"]
            path = "/Volumes/Disk 2"
            title = "Disk 2"

            [favourites.namesake]
            path = "/Users/someone else/Music"
            title = "Music"

            """)
        let config = load(local: text)
        #expect(config.favourites == favourites)
        #expect(config.problem == nil)
    }

    @Test func theLocalTextOfNoFavouritesStillReplacesTheTrackedList() {
        let text = ExplorerConfig.localText(favourites: [], home: home)
        #expect(text == "[favourites]\n")
        let config = load(local: text)
        #expect(config.favourites.isEmpty)
        #expect(config.problem == nil)
    }
}
