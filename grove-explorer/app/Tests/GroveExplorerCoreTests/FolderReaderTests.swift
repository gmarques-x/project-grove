import Foundation
import GroveExplorerCore
import Testing

/// Reading real folders: each test gets its own temporary folder, removed
/// when the test ends, passed or failed.
@Suite final class FolderReaderTests {
    private let root: URL
    private let files = FileManager.default

    init() throws {
        root = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-reader-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func path(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func makeFile(_ name: String, _ contents: String = "") throws {
        try Data(contents.utf8).write(to: path(name))
    }

    private func makeFolder(_ name: String) throws {
        try files.createDirectory(at: path(name), withIntermediateDirectories: true)
    }

    /// The folder's entries by name (the reader promises no order).
    private func read() throws -> [String: Entry] {
        let entries = try FolderReader().read(root)
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    }

    @Test func anEmptyFolderHasNoEntries() throws {
        #expect(try FolderReader().read(root).isEmpty)
    }

    @Test func aFileHasItsSizeAndItsNameWithTheExtension() throws {
        try makeFile("notes.md", "hello")
        let entries = try read()
        let notes = try #require(entries["notes.md"])
        #expect(entries.count == 1)
        #expect(notes.kind == .file)
        #expect(notes.size == 5)
        #expect(notes.isHidden == false)
        #expect(notes.url.path == path("notes.md").path)
        #expect(notes.typeDescription == (try path("notes.md").resourceValues(forKeys: [.localizedTypeDescriptionKey])).localizedTypeDescription)
        #expect(notes.typeDescription.isEmpty == false)
        let modified = try #require(notes.modified)
        #expect(abs(modified.timeIntervalSinceNow) < 60)
    }

    @Test func aFolderHasNoSize() throws {
        try makeFolder("Projects")
        try makeFile("Projects/inside.txt", "not counted")
        let projects = try #require(try read()["Projects"])
        #expect(projects.kind == .folder)
        #expect(projects.size == nil)
        #expect(projects.isHidden == false)
        #expect(projects.modified != nil)
    }

    /// An app is a folder on disk and one item in the list.
    @Test func anAppIsAPackageNotAFolder() throws {
        try makeFolder("Demo.app/Contents")
        try makeFile(
            "Demo.app/Contents/Info.plist",
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleIdentifier</key><string>com.projectgrove.explorer.test-demo</string>
            </dict></plist>
            """
        )
        let app = try #require(try read()["Demo.app"])
        #expect(app.kind == .package)
        #expect(app.size == nil)
        #expect(app.name == "Demo.app")
    }

    @Test func aDotFileIsHidden() throws {
        try makeFile(".gitignore", ".build/\n")
        try makeFolder(".cache")
        let entries = try read()
        #expect(entries[".gitignore"]?.isHidden == true)
        #expect(entries[".gitignore"]?.kind == .file)
        #expect(entries[".gitignore"]?.size == 8)
        #expect(entries[".cache"]?.isHidden == true)
        #expect(entries[".cache"]?.kind == .folder)
    }

    /// Finder's hidden flag (`chflags hidden`) hides a name with no dot.
    @Test func theHiddenFlagHides() throws {
        try makeFile("flagged.txt", "x")
        var flagged = path("flagged.txt")
        var values = URLResourceValues()
        values.isHidden = true
        try flagged.setResourceValues(values)
        #expect(try read()["flagged.txt"]?.isHidden == true)
    }

    /// A link is listed as a link: its kind says what it points at, and its
    /// size is its own, never the target's.
    @Test func aSymlinkToAFileIsALinkWithItsOwnSize() throws {
        try makeFile("target.bin", String(repeating: "x", count: 4_096))
        try files.createSymbolicLink(atPath: path("link-to-file").path, withDestinationPath: "target.bin")
        let link = try #require(try read()["link-to-file"])
        #expect(link.kind == .symlink(toFolder: false))
        #expect(link.size != 4_096)
        #expect(link.size == Int64("target.bin".utf8.count))
        #expect(link.isHidden == false)
    }

    @Test func aSymlinkToAFolderIsALinkNotAFolder() throws {
        try makeFolder("Real")
        try files.createSymbolicLink(atPath: path("link-to-folder").path, withDestinationPath: "Real")
        let entries = try read()
        #expect(entries["link-to-folder"]?.kind == .symlink(toFolder: true))
        #expect(entries["Real"]?.kind == .folder)
    }

    @Test func aBrokenSymlinkIsStillListed() throws {
        try files.createSymbolicLink(atPath: path("dangling").path, withDestinationPath: "nowhere")
        let dangling = try #require(try read()["dangling"])
        #expect(dangling.kind == .symlink(toFolder: false))
        #expect(dangling.modified != nil)
    }

    /// Two links that point at each other: listed, and reading returns.
    @Test func aSymlinkLoopIsListedAndDoesNotHang() throws {
        try files.createSymbolicLink(atPath: path("a").path, withDestinationPath: "b")
        try files.createSymbolicLink(atPath: path("b").path, withDestinationPath: "a")
        let entries = try read()
        #expect(entries["a"]?.kind == .symlink(toFolder: false))
        #expect(entries["b"]?.kind == .symlink(toFolder: false))
    }

    /// A Finder alias (a bookmark file) is its own kind, whatever it points at.
    @Test func anAliasIsAnAlias() throws {
        try makeFolder("Original")
        let bookmark = try path("Original").bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: path("Original alias"))
        let alias = try #require(try read()["Original alias"])
        #expect(alias.kind == .alias)
        #expect(alias.size != nil)
    }

    /// Each item is described as macOS describes it, also when several
    /// share a type and when their types differ.
    @Test func typeDescriptionsAreTheSystemsOwn() throws {
        try makeFile("a.txt", "a")
        try makeFile("b.txt", "b")
        try makeFile("c.png")
        try makeFile("no-extension")
        try makeFile("odd.grove-unknown-ext")
        try makeFolder("Folder")
        try makeFolder("Other Folder")
        try files.createSymbolicLink(atPath: path("link").path, withDestinationPath: "a.txt")
        let entries = try read()
        #expect(entries.count == 8)
        for (name, entry) in entries {
            let system = try path(name).resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription
            #expect(entry.typeDescription == system, "\(name)")
        }
        #expect(entries["Folder"]?.typeDescription != entries["a.txt"]?.typeDescription)
        #expect(entries["c.png"]?.typeDescription != entries["a.txt"]?.typeDescription)
    }

    @Test func everyItemIsListedOnce() throws {
        try makeFile("a.txt")
        try makeFile(".hidden")
        try makeFolder("Folder")
        try makeFile("Folder/deep.txt")
        try files.createSymbolicLink(atPath: path("link").path, withDestinationPath: "a.txt")
        let names = try FolderReader().read(root).map(\.name).sorted()
        #expect(names == [".hidden", "Folder", "a.txt", "link"])
    }

    /// A link to a folder can be opened: its target's items are read.
    @Test func readingThroughASymlinkToAFolder() throws {
        try makeFolder("Real")
        try makeFile("Real/inside.txt", "abc")
        try files.createSymbolicLink(atPath: path("link").path, withDestinationPath: "Real")
        let entries = try FolderReader().read(path("link"))
        #expect(entries.map(\.name) == ["inside.txt"])
        // The entry stays under the path it was reached by, not the target's.
        #expect(entries.first?.url.path == path("link").appendingPathComponent("inside.txt").path)
        #expect(entries.first?.size == 3)
    }

    @Test func aBrokenLinkAsTheFolderThrowsMissing() throws {
        try files.createSymbolicLink(atPath: path("dangling").path, withDestinationPath: "nowhere")
        #expect(throws: FolderReadError.missing) {
            try FolderReader().read(self.path("dangling"))
        }
    }

    @Test func aLinkToAFileAsTheFolderThrowsNotAFolder() throws {
        try makeFile("plain.txt", "x")
        try files.createSymbolicLink(atPath: path("link").path, withDestinationPath: "plain.txt")
        #expect(throws: FolderReadError.notAFolder) {
            try FolderReader().read(self.path("link"))
        }
    }

    /// A folder's URL ends in a slash and a file's doesn't, as Foundation's own do.
    @Test func entryURLsAreTheFolderPlusTheName() throws {
        try makeFile("a.txt")
        try makeFolder("Folder")
        let entries = try read()
        #expect(entries["a.txt"]?.url == root.appendingPathComponent("a.txt", isDirectory: false))
        #expect(entries["Folder"]?.url == root.appendingPathComponent("Folder", isDirectory: true))
        #expect(entries["Folder"]?.url.hasDirectoryPath == true)
    }

    @Test func aMissingFolderThrowsMissing() {
        #expect(throws: FolderReadError.missing) {
            try FolderReader().read(self.path("not-here"))
        }
    }

    @Test func aFileThrowsNotAFolder() throws {
        try makeFile("plain.txt", "x")
        #expect(throws: FolderReadError.notAFolder) {
            try FolderReader().read(self.path("plain.txt"))
        }
    }

    @Test func anUnreadableFolderThrowsNoPermission() throws {
        try makeFolder("Locked")
        try makeFile("Locked/secret.txt", "x")
        let locked = path("Locked")
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        // Back to readable before the test's folder is removed, passed or failed.
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(throws: FolderReadError.noPermission) {
            try FolderReader().read(locked)
        }
        // Its parent still lists it, as a folder.
        #expect(try read()["Locked"]?.kind == .folder)
    }

    /// The spec's limit: a folder of 50,000 items opens without a visible pause.
    @Test func reads50kEntriesUnderTwoSeconds() throws {
        let count = 50_000
        let directory = open(root.path, O_RDONLY | O_DIRECTORY)
        try #require(directory >= 0)
        for index in 0..<count {
            let file = openat(directory, "file-\(index).txt", O_CREAT | O_WRONLY | O_EXCL, 0o644)
            if file >= 0 { close(file) }
        }
        close(directory)

        var entries: [Entry] = []
        let clock = ContinuousClock()
        let elapsed = try clock.measure { entries = try FolderReader().read(root) }
        #expect(entries.count == count)
        #expect(entries.allSatisfy { $0.kind == .file && $0.size == 0 })
        #expect(elapsed < .seconds(2), "reading \(count) entries took \(elapsed)")
    }
}
