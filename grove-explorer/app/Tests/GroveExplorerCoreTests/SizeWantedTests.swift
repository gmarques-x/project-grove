import Foundation
import GroveExplorerCore
import Testing

@Suite struct SizeWantedTests {
    private func entry(_ path: String, _ kind: Entry.Kind = .folder) -> Entry {
        let url = URL(fileURLWithPath: path, isDirectory: kind == .folder)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: nil, modified: nil, isHidden: false,
            typeDescription: "")
    }

    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    @Test func foldersAndPackagesInTheOrderShown() {
        let pane = SizeWanted.Pane(
            tabFolder: folder("/a"), listedFolder: folder("/a"),
            shown: [entry("/a/one"), entry("/a/file.txt", .file), entry("/a/App.app", .package), entry("/a/two")])
        #expect(SizeWanted.urls(in: [pane]).map(\.path) == ["/a/one", "/a/App.app", "/a/two"])
    }

    /// A pane that has navigated still shows the folder it left until the
    /// new one is read: none of those rows is wanted any more.
    @Test func aPaneBetweenTwoFoldersWantsNothing() {
        let leaving = SizeWanted.Pane(tabFolder: folder("/b"), listedFolder: folder("/a"), shown: [entry("/a/one")])
        let still = SizeWanted.Pane(tabFolder: folder("/big"), listedFolder: folder("/big"), shown: [entry("/big/x")])
        #expect(SizeWanted.urls(in: [leaving, still]).map(\.path) == ["/big/x"])
        let unread = SizeWanted.Pane(tabFolder: folder("/b"), listedFolder: nil, shown: [])
        #expect(SizeWanted.urls(in: [unread]).isEmpty)
    }

    /// The same folder however it is written.
    @Test func theFolderIsComparedByItsStandardizedPath() {
        let pane = SizeWanted.Pane(
            tabFolder: URL(fileURLWithPath: "/a/sub/.."), listedFolder: folder("/a"), shown: [entry("/a/one")])
        #expect(SizeWanted.urls(in: [pane]).map(\.path) == ["/a/one"])
    }

    /// Both panes on one folder: each row once.
    @Test func aRowShownTwiceIsWantedOnce() {
        let pane = SizeWanted.Pane(
            tabFolder: folder("/a"), listedFolder: folder("/a"), shown: [entry("/a/one"), entry("/a/two")])
        #expect(SizeWanted.urls(in: [pane, pane]).map(\.path) == ["/a/one", "/a/two"])
    }
}
