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
}
