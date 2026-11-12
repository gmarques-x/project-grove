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
}
