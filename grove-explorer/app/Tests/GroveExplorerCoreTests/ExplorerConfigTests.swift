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

    @Test func theLocalTextRoundTripsThroughLoad() throws {
        let favourites = [
            Favourite(id: "home", url: home, title: "Home"),
            Favourite(id: "work", url: folder("/Users/someone/Developer/project grove"), title: "Work \"now\""),
            Favourite(id: "disk 2", url: folder("/Volumes/Disk 2"), title: "Disk 2"),
            Favourite(id: "namesake", url: folder("/Users/someone else/Music"), title: "Music"),
        ]
        let text = try ExplorerConfig.localText(favourites: favourites, home: home, keeping: nil)
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

    @Test func theLocalTextOfNoFavouritesStillReplacesTheTrackedList() throws {
        let text = try ExplorerConfig.localText(favourites: [], home: home, keeping: nil)
        #expect(text == "[favourites]\n")
        let config = load(local: text)
        #expect(config.favourites.isEmpty)
        #expect(config.problem == nil)
    }

    // MARK: Keeping what else the local file holds

    @Test func addingAFavouriteKeepsTheLocalFilesGeneralSettings() throws {
        let existing = """
            # mine
            [general]
            show_hidden = true # always

            """
        let favourites = [Favourite(id: "music", url: folder("/Users/someone/Music"), title: "Music")]
        let text = try ExplorerConfig.localText(favourites: favourites, home: home, keeping: existing)
        #expect(text == """
            # mine
            [general]
            show_hidden = true # always

            [favourites.music]
            path = "~/Music"
            title = "Music"

            """)
        let config = load(local: text)
        #expect(config.showHidden == true)
        #expect(config.favourites == favourites)
        #expect(config.problem == nil)
    }

    @Test func theFavouritesTablesAreReplacedWhereTheyStoodAndTheRestStays() throws {
        let existing = """
            [favourites.old]
            path = "/old"

            [general]
            two_panes = true
            start = "~/Developer"

            [favourites.older]
            path = "/older"

            """
        let favourites = [
            Favourite(id: "a", url: folder("/a"), title: "a"),
            Favourite(id: "b", url: folder("/b"), title: "B"),
        ]
        let text = try ExplorerConfig.localText(favourites: favourites, home: home, keeping: existing)
        #expect(text == """
            [favourites.a]
            path = "/a"
            title = "a"

            [favourites.b]
            path = "/b"
            title = "B"

            [general]
            two_panes = true
            start = "~/Developer"

            """)
        let config = load(local: text)
        #expect(config.twoPanes == true)
        #expect(config.start == folder("/Users/someone/Developer"))
        #expect(config.favourites.map(\.id) == ["a", "b"])
    }

    @Test func noFavouritesBesideOtherSettingsIsTheBareTable() throws {
        let text = try ExplorerConfig.localText(
            favourites: [], home: home, keeping: "[general]\nshow_hidden = true\n\n[favourites.x]\npath = \"/x\"\n")
        #expect(text == "[general]\nshow_hidden = true\n\n[favourites]\n")
        let config = load(local: text)
        #expect(config.favourites.isEmpty)
        #expect(config.showHidden == true)
    }

    @Test func anEmptyOrMissingLocalFileGivesTheFavouritesAlone() throws {
        let favourites = [Favourite(id: "a", url: folder("/a"), title: "a")]
        let alone = try ExplorerConfig.localText(favourites: favourites, home: home, keeping: nil)
        #expect(try ExplorerConfig.localText(favourites: favourites, home: home, keeping: "") == alone)
        #expect(alone == "[favourites.a]\npath = \"/a\"\ntitle = \"a\"\n")
    }

    @Test func aBrokenLocalFileIsNotWrittenOver() {
        let favourites = [Favourite(id: "a", url: folder("/a"), title: "a")]
        let broken = "[general]\nshow_hidden = tru\n"
        #expect(throws: ConfigWriteRefused(
            description: "explorer.local.toml line 2 can't be read, so it was left as it is and the favourites were not saved"
        )) {
            try ExplorerConfig.localText(favourites: favourites, home: home, keeping: broken)
        }
    }

    @Test func aLocalFileTheAppWouldNotReadIsNotWrittenOverEither() {
        // It parses as TOML, but the config refuses it (an unknown table):
        // rewriting it would be rewriting something not understood.
        #expect(throws: ConfigWriteRefused.self) {
            try ExplorerConfig.localText(favourites: [], home: home, keeping: "[colours]\nred = true\n")
        }
    }

    // MARK: The favourites as the files give them

    @Test func allFavouritesAreTheMergedListWhetherTheirFoldersExistOrNot() {
        #expect(ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: nil, home: home).map(\.id)
            == ["applications", "home", "developer", "documents", "downloads"])
        let local = "[favourites.disk]\npath = \"/Volumes/Away/work\"\n\n[favourites.music]\npath = \"~/Music\"\n"
        #expect(ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: local, home: home).map(\.id)
            == ["disk", "music"])
        // A local file that can't be read counts for nothing, as in `load`.
        #expect(ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: "[favourites.x\n", home: home).count == 5)
    }

    /// The window's list leaves out a favourite on a disk that isn't
    /// mounted. Removing another one must not write that shortened list.
    @Test func aFavouriteWhoseFolderIsNotThereSurvivesTheRemovalOfAnother() throws {
        let local = """
            [favourites.disk]
            path = "/Volumes/Away/work"

            [favourites.music]
            path = "~/Music"

            [favourites.films]
            path = "~/Movies"

            """
        let mounted: (URL) -> Bool = { !$0.path.hasPrefix("/Volumes/Away") }
        // What the sidebar shows: the disk's favourite is left out.
        #expect(load(local: local, exists: mounted).favourites.map(\.id) == ["music", "films"])

        let kept = ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: local, home: home)
            .filter { $0.id != "music" }
        let text = try ExplorerConfig.localText(favourites: kept, home: home, keeping: local)
        #expect(ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: text, home: home).map(\.id)
            == ["disk", "films"])
        // The disk comes back: its favourite is in the sidebar again.
        #expect(load(local: text).favourites.map(\.url.path) == ["/Volumes/Away/work", "/Users/someone/Movies"])
    }

    @Test func removingATrackedFavouriteWritesTheOthersToTheLocalFile() throws {
        let kept = ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: nil, home: home)
            .filter { $0.id != "developer" }
        let text = try ExplorerConfig.localText(favourites: kept, home: home, keeping: nil)
        // Nothing exists but Home: the window shows one, the file still holds four.
        #expect(load(local: text, exists: { $0 == self.home }).favourites.map(\.id) == ["home"])
        #expect(ExplorerConfig.allFavourites(tracked: ExplorerConfig.builtIn, local: text, home: home).map(\.id)
            == ["applications", "home", "documents", "downloads"])
    }
}
