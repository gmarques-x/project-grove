import Foundation
@testable import GroveExplorerCore
import Testing

/// Which panes' watchers are not on the folder the pane shows.
@Suite struct WatchPlanTests {
    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    @Test func aPaneWatchingItsOwnFolderIsLeftAlone() {
        #expect(WatchPlan.stale(watched: [.left: "/a", .right: "/b"], shown: [.left: folder("/a"), .right: folder("/b")]) == [])
    }

    @Test func aPaneWithoutAWatcherNeedsOne() {
        #expect(WatchPlan.stale(watched: [.right: "/b"], shown: [.left: folder("/a"), .right: folder("/b")]) == [.left])
    }

    /// The pane went onto a disk while it was being ejected: nothing could
    /// be watched there, and the watcher it has is its last folder's.
    @Test func aPaneWhoseWatcherIsOnAnotherFolderNeedsANewOne() {
        let stale = WatchPlan.stale(
            watched: [.left: "/Users/me", .right: "/b"],
            shown: [.left: folder("/Volumes/Backup/x"), .right: folder("/b")])
        #expect(stale == [.left])
    }

    @Test func foldersAreComparedHoweverTheyAreWritten() {
        #expect(WatchPlan.stale(watched: [.left: "/a/b"], shown: [.left: URL(fileURLWithPath: "/a/c/../b/")]) == [])
    }

    @Test func bothPanesComeLeftFirstAndAPaneThatIsNotThereIsNotAsked() {
        #expect(WatchPlan.stale(watched: [:], shown: [.right: folder("/b"), .left: folder("/a")]) == [.left, .right])
        // One pane now: the watcher still kept for the right is nobody's.
        #expect(WatchPlan.stale(watched: [.left: "/a", .right: "/b"], shown: [.left: folder("/a")]) == [])
    }

    // MARK: Folders open in place

    private func row(_ path: String, depth: Int, fold: TreeRow.Fold = .open) -> TreeItem {
        let url = folder(path)
        return .row(TreeRow(
            entry: Entry(url: url, name: url.lastPathComponent, kind: .folder, size: nil, modified: nil, isHidden: false,
                typeDescription: "Folder"),
            depth: depth, fold: fold, isContext: false))
    }

    @Test func openFoldersAreWatchedNearestTheTopFirst() {
        let rows: [TreeItem] = [row("/t/b", depth: 0), row("/t/b/c", depth: 1), row("/t/a", depth: 0, fold: .loading),
            .loading(under: folder("/t/a"), depth: 1)]
        let plan = WatchPlan.openFolders([folder("/t/a"), folder("/t/b/c"), folder("/t/b")], rows: rows)
        #expect(plan.watched.map(\.path) == ["/t/b", "/t/b/c", "/t/a"])
        #expect(plan.beyond.isEmpty)
    }

    /// Under a filter an open folder can have no row, and still be looked
    /// through: watched after those that show, by path.
    @Test func anOpenFolderWithoutARowComesLast() {
        let plan = WatchPlan.openFolders(
            [folder("/t/z"), folder("/t/y"), folder("/t/b")], rows: [row("/t/b", depth: 0)])
        #expect(plan.watched.map(\.path) == ["/t/b", "/t/y", "/t/z"])
    }

    @Test func atMost64OpenFoldersAreWatched() {
        let folders = (0..<100).map { folder(String(format: "/t/f%03d", $0)) }
        let rows = folders.reversed().map { row($0.path, depth: 0) }
        let plan = WatchPlan.openFolders(Set(folders), rows: rows)
        #expect(WatchPlan.openFolderLimit == 64)
        #expect(plan.watched.count == 64)
        // The top of the list: here the last names.
        #expect(plan.watched.first?.path == "/t/f099")
        #expect(plan.watched.last?.path == "/t/f036")
        #expect(Set(plan.beyond.map(\.path)) == Set((0..<36).map { String(format: "/t/f%03d", $0) }))
    }
}
