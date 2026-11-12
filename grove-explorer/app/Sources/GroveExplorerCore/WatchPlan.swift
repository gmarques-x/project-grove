import Foundation

/// Which panes' folder watchers need making again.
public enum WatchPlan {
    /// The sides whose watcher is not on the folder the pane shows: it has
    /// none, or one left on another folder (a pane that went onto a disk
    /// while it was being ejected could not be watched there). `watched`
    /// is each watcher's folder by its standardized path; `shown` each
    /// pane's folder. Left first.
    public static func stale(watched: [Side: String], shown: [Side: URL]) -> [Side] {
        [Side.left, .right].filter { side in
            guard let folder = shown[side] else { return false }
            return watched[side] != folder.standardizedFileURL.path
        }
    }
}
