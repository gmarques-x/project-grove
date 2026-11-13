import Foundation
import GroveExplorerCore
import Testing

/// Looking into real folders: each test gets its own temporary folder,
/// removed when the test ends, passed or failed. (The timing test is in
/// `TimingTests`.)
@Suite final class FolderPeekTests {
    private let root: URL
    private let files = FileManager.default

    init() throws {
        root = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-peek-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func path(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func makeFolder(_ name: String) throws -> URL {
        let folder = path(name)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeFile(_ name: String) throws {
        try Data("x".utf8).write(to: path(name))
    }

    @Test func anEmptyFolderHasNothing() throws {
        let empty = try makeFolder("Empty")
        #expect(FolderPeek.hasContents(empty, showHidden: false) == false)
        #expect(FolderPeek.hasContents(empty, showHidden: true) == false)
    }

    @Test func oneFileIsSomething() throws {
        let folder = try makeFolder("One")
        try makeFile("One/a.txt")
        #expect(FolderPeek.hasContents(folder, showHidden: false) == true)
    }

    @Test func onlyADotFileIsSomethingOnlyWhileHiddenItemsShow() throws {
        let folder = try makeFolder("Dotted")
        try makeFile("Dotted/.gitignore")
        #expect(FolderPeek.hasContents(folder, showHidden: false) == false)
        #expect(FolderPeek.hasContents(folder, showHidden: true) == true)
    }

    /// The hidden flag hides as a dot does (`Entry.isHidden`'s rule).
    @Test func onlyAFileWithTheHiddenFlagIsSomethingOnlyWhileHiddenItemsShow() throws {
        let folder = try makeFolder("Flagged")
        try makeFile("Flagged/secret.txt")
        var values = URLResourceValues()
        values.isHidden = true
        var file = path("Flagged/secret.txt")
        try file.setResourceValues(values)
        #expect(FolderPeek.hasContents(folder, showHidden: false) == false)
        #expect(FolderPeek.hasContents(folder, showHidden: true) == true)
    }

    @Test func oneSubfolderIsSomething() throws {
        let folder = try makeFolder("Outer")
        _ = try makeFolder("Outer/Inner")
        #expect(FolderPeek.hasContents(folder, showHidden: false) == true)
    }

    @Test func aFolderThatCannotBeReadHasNoAnswer() throws {
        let locked = try makeFolder("Locked")
        try makeFile("Locked/secret.txt")
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        // Back to readable before the test's folder is removed, passed or failed.
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(FolderPeek.hasContents(locked, showHidden: false) == nil)
    }

    @Test func aFolderThatIsNotThereHasNoAnswer() {
        #expect(FolderPeek.hasContents(path("Gone"), showHidden: false) == nil)
    }

    /// The list gives links no chevron, so a link is never looked through.
    @Test func aLinkToAFolderIsNotFollowed() throws {
        let target = try makeFolder("Target")
        try makeFile("Target/a.txt")
        let link = path("Link")
        try files.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(FolderPeek.hasContents(link, showHidden: false) == nil)
    }

    /// A link inside the folder is an item that shows, wherever it leads.
    @Test func aLinkInsideIsSomething() throws {
        let folder = try makeFolder("Holder")
        try files.createSymbolicLink(atPath: path("Holder/broken").path, withDestinationPath: "/nowhere/at/all")
        #expect(FolderPeek.hasContents(folder, showHidden: false) == true)
    }

    /// A folder reached through a link on its way (`/var` is `/private/var`)
    /// is looked into: only the last part of the path is not followed.
    @Test func aFolderBehindALinkedParentIsLookedInto() throws {
        let real = try makeFolder("Real/Inside")
        try makeFile("Real/Inside/a.txt")
        try files.createSymbolicLink(at: path("Via"), withDestinationURL: path("Real"))
        #expect(FolderPeek.hasContents(path("Via/Inside"), showHidden: false) == true)
        #expect(FolderPeek.hasContents(real, showHidden: false) == true)
    }
}
