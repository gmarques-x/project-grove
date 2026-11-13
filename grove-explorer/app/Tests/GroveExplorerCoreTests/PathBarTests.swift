import Foundation
@testable import GroveExplorerCore
import Testing

@Suite struct PathBarTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    private let root = URL(fileURLWithPath: "/", isDirectory: true)
    private let backup = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func parts(_ path: String) -> [PathBar.Part] {
        PathBar.parts(of: folder(path), home: home, volumes: [root, backup])
    }

    /// What macOS calls the startup volume on this Mac ("Macintosh HD").
    private func rootName() throws -> String {
        try #require(try root.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName)
    }

    // MARK: Parts

    @Test func aFolderUnderHomeStartsAtHome() {
        let parts = parts("/Users/someone/Developer/project-grove")
        #expect(parts.map(\.title) == ["Home", "Developer", "project-grove"])
        #expect(parts.map(\.url.path) == [
            "/Users/someone", "/Users/someone/Developer", "/Users/someone/Developer/project-grove",
        ])
    }

    @Test func homeItselfIsOnePart() {
        #expect(parts("/Users/someone").map(\.title) == ["Home"])
        #expect(parts("/Users/someone").map(\.url.path) == ["/Users/someone"])
    }

    @Test func aFolderOnAnotherVolumeStartsAtThatVolume() {
        let parts = parts("/Volumes/Backup/x")
        #expect(parts.map(\.title) == ["Backup", "x"])
        #expect(parts.map(\.url.path) == ["/Volumes/Backup", "/Volumes/Backup/x"])
        #expect(self.parts("/Volumes/Backup").map(\.title) == ["Backup"])
    }

    @Test func aFolderOnTheStartupVolumeStartsAtItsName() throws {
        let name = try rootName()
        let parts = parts("/usr/local")
        #expect(parts.map(\.title) == [name, "usr", "local"])
        #expect(parts.map(\.url.path) == ["/", "/usr", "/usr/local"])
        #expect(self.parts("/").map(\.title) == [name])
    }

    @Test func aFolderBesideHomeIsNotUnderIt() throws {
        // Same first letters, another folder.
        #expect(parts("/Users/someone-else/x").map(\.title)
            == [try rootName(), "Users", "someone-else", "x"])
        #expect(parts("/Users").map(\.title) == [try rootName(), "Users"])
    }

    @Test func aVolumeNotInTheListIsReadFromTheStartupVolume() throws {
        // Mounted a moment ago, or the list is stale: still a path to click.
        #expect(parts("/Volumes/New/x").map(\.title) == [try rootName(), "Volumes", "New", "x"])
    }

    @Test func withoutAnyVolumeThePathStartsAtTheRoot() {
        let parts = PathBar.parts(of: folder("/usr/local"), home: home, volumes: [])
        #expect(parts.map(\.title) == ["/", "usr", "local"])
    }

    @Test func aHomeOnAnotherVolumeStillStartsAtHome() {
        let away = folder("/Volumes/Backup/Users/someone")
        let parts = PathBar.parts(
            of: folder("/Volumes/Backup/Users/someone/Documents"), home: away,
            volumes: [root, backup])
        #expect(parts.map(\.title) == ["Home", "Documents"])
    }

    @Test func thePartsKeepThePathAsGiven() {
        // /var is a link to /private/var: the bar shows what was navigated to.
        let parts = PathBar.parts(of: folder("/private/tmp/x"), home: home, volumes: [])
        #expect(parts.map(\.url.path) == ["/", "/private", "/private/tmp", "/private/tmp/x"])
    }

    @Test func dotsInThePathAreWorkedOutFirst() {
        #expect(parts("/Users/someone/a/../Developer/./x").map(\.title)
            == ["Home", "Developer", "x"])
    }

    // MARK: Cloud places

    private let iCloud = "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs"

    @Test func iCloudDriveStartsTheBarWithItsName() {
        let parts = parts(iCloud)
        #expect(parts.map(\.title) == ["iCloud Drive"])
        #expect(parts.map(\.url.path) == [iCloud])
        #expect(parts.map(\.mark) == [.cloud])
    }

    @Test func aFolderInICloudDriveGoesOnFromIt() {
        let parts = parts(iCloud + "/Notes/2026")
        #expect(parts.map(\.title) == ["iCloud Drive", "Notes", "2026"])
        #expect(parts.map(\.url.path) == [iCloud, iCloud + "/Notes", iCloud + "/Notes/2026"])
        #expect(parts.map(\.mark) == [.cloud, .none, .none])
    }

    @Test func aProvidersFolderStartsTheBarWithItsName() {
        let storage = "/Users/someone/Library/CloudStorage"
        let parts = parts(storage + "/OneDrive-Personal/Documents")
        #expect(parts.map(\.title) == ["OneDrive", "Documents"])
        #expect(parts.first?.url.path == storage + "/OneDrive-Personal")
        #expect(parts.first?.mark == .cloud)
        #expect(self.parts(storage + "/OneDrive-Contoso").map(\.title) == ["OneDrive - Contoso"])
    }

    @Test func homeAndVolumesCarryTheirMarks() {
        #expect(parts("/Users/someone/Library/Mobile Documents").map(\.title)
            == ["Home", "Library", "Mobile Documents"])
        #expect(parts("/Users/someone/Library").map(\.mark) == [.home, .none])
        #expect(parts("/Volumes/Backup/x").map(\.mark) == [.none, .none])
    }

    // MARK: Resolve

    private func resolve(_ typed: String, relativeTo path: String = "/a/b") -> String {
        PathBar.resolve(typed, relativeTo: folder(path), home: home).path
    }

    @Test func aTildeIsHome() {
        #expect(resolve("~") == "/Users/someone")
        #expect(resolve("~/") == "/Users/someone")
        #expect(resolve("~/x") == "/Users/someone/x")
        #expect(resolve("~/x/y z/") == "/Users/someone/x/y z")
    }

    @Test func anAbsolutePathIsItself() {
        #expect(resolve("/usr/local") == "/usr/local")
        #expect(resolve("/usr/local/") == "/usr/local")
        #expect(resolve("/") == "/")
        #expect(resolve("/usr/./local/../bin") == "/usr/bin")
    }

    @Test func aRelativePathStartsAtTheCurrentFolder() {
        #expect(resolve("../y", relativeTo: "/a/b") == "/a/y")
        #expect(resolve("c/d") == "/a/b/c/d")
        #expect(resolve("./c") == "/a/b/c")
        #expect(resolve("..") == "/a")
        #expect(resolve(".") == "/a/b")
    }

    @Test func goingAboveTheRootStaysAtTheRoot() {
        #expect(resolve("../../../..") == "/")
        #expect(resolve("/../x") == "/x")
        #expect(resolve("~/../../../../x") == "/x")
    }

    @Test func spacesRoundWhatWasTypedAreDropped() {
        #expect(resolve("  ~/x \n") == "/Users/someone/x")
        #expect(resolve("") == "/a/b")
        #expect(resolve("   ") == "/a/b")
    }

    @Test func aTildeInsideANameIsOnlyAName() {
        #expect(resolve("~x") == "/a/b/~x")
        #expect(resolve("a/~") == "/a/b/a/~")
        #expect(resolve("/x/~/y") == "/x/~/y")
    }

    @Test func theResultIsAFolderAndKeepsThePathAsTyped() {
        let url = PathBar.resolve("/private/tmp", relativeTo: folder("/a"), home: home)
        #expect(url.path == "/private/tmp")
        #expect(url.hasDirectoryPath)
        #expect(url.isFileURL)
    }

    // MARK: A folder as text

    @Test func aFolderIsWrittenFromHomeWhenItIsUnderIt() {
        #expect(PathBar.text(for: home, home: home) == "~")
        #expect(PathBar.text(for: folder("/Users/someone/Developer/project-grove"), home: home) == "~/Developer/project-grove")
        #expect(PathBar.text(for: folder("/Applications"), home: home) == "/Applications")
        #expect(PathBar.text(for: folder("/Users/someone else/x"), home: home) == "/Users/someone else/x")
        #expect(PathBar.text(for: root, home: home) == "/")
    }

    @Test func theTextOfAFolderResolvesBackToIt() {
        for path in ["/Users/someone", "/Users/someone/a b/c", "/Volumes/Backup", "/"] {
            let text = PathBar.text(for: folder(path), home: home)
            #expect(PathBar.resolve(text, relativeTo: folder("/elsewhere"), home: home).path == path)
        }
    }

    // MARK: Where a path leads

    private func kind(_ url: URL) -> PathBar.ItemKind? {
        ["/a": .folder, "/a/b": .folder, "/a/b/notes.md": .file][url.path]
    }

    @Test func aFolderThatExistsIsWhereToGo() {
        #expect(PathBar.destination(of: folder("/a/b"), kind: kind) == .folder(folder("/a/b")))
    }

    @Test func aFileLeadsToItsFolderWithTheFileToSelect() {
        let file = URL(fileURLWithPath: "/a/b/notes.md")
        #expect(PathBar.destination(of: file, kind: kind) == .item(file, in: folder("/a/b")))
        // Typed in the path bar it comes as a folder's URL: the same answer.
        #expect(PathBar.destination(of: folder("/a/b/notes.md"), kind: kind) == .item(file, in: folder("/a/b")))
    }

    @Test func aPathThatIsNotThereLeadsNowhere() {
        #expect(PathBar.destination(of: folder("/a/x"), kind: kind) == .missing)
        #expect(PathBar.destination(of: folder("/nowhere/at/all"), kind: kind) == .missing)
    }

    // MARK: Completing what is typed

    private func names(_ url: URL) -> [String] {
        ["/Users/someone/Developer": ["project-grove", "project-pine", "Playground", "other"],
         "/Users/someone": ["Developer", "Desktop", "Documents", "Downloads"],
         "/": ["Applications", "Users"]][url.path] ?? []
    }

    private func completed(_ typed: String, from: String = "/Users/someone") -> String? {
        PathBar.completed(typed, relativeTo: folder(from), home: home, folders: names)
    }

    @Test func theOnlyFolderThatStartsSoIsCompletedWithItsSlash() {
        #expect(completed("~/Developer/o") == "~/Developer/other/")
        #expect(completed("/App") == "/Applications/")
        #expect(completed("Dev") == "Developer/")
    }

    @Test func severalCandidatesAreCompletedAsFarAsTheyAgree() {
        #expect(completed("~/Developer/pro") == "~/Developer/project-")
        #expect(completed("~/Do") == nil)
        #expect(completed("~/D") == nil)
    }

    @Test func caseIsIgnoredAndTheFoldersOwnSpellingIsWritten() {
        #expect(completed("~/Developer/OTH") == "~/Developer/other/")
        // "project-grove", "project-pine" and "Playground" agree on "p" only.
        #expect(completed("~/Developer/P") == nil)
        #expect(completed("~/Developer/pl") == "~/Developer/Playground/")
    }

    @Test func nothingToCompleteIsNil() {
        #expect(completed("~/Developer/zzz") == nil)
        #expect(completed("~/Nowhere/x") == nil)
        #expect(completed("~/Developer/") == nil)
        #expect(completed("") == nil)
    }
}
