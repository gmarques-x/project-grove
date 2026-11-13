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

    /// How many folders open in place a pane watches at most (spec §16):
    /// one watcher each, and a tree opened wide must not cost hundreds.
    public static let openFolderLimit = 64

    /// Of the open folders a pane shows (`Tree.reachable`), the ones it
    /// watches: the `openFolderLimit` whose rows come first in `rows`, then
    /// (under a filter an open folder may have no row) the others by path.
    /// `beyond`: those past the limit, read again when the tab's own folder
    /// changes or their rows come into view instead.
    public static func openFolders(_ open: Set<URL>, rows: [TreeItem]) -> (watched: [URL], beyond: [URL]) {
        guard !open.isEmpty else { return ([], []) }
        var wanted = Dictionary(open.map { ($0.standardizedPath, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [URL] = []
        for case .row(let row) in rows where row.entry.kind == .folder {
            if let url = wanted.removeValue(forKey: row.entry.url.standardizedPath) { ordered.append(url) }
            if wanted.isEmpty { break }
        }
        ordered += wanted.sorted { $0.key < $1.key }.map(\.value)
        return (Array(ordered.prefix(openFolderLimit)), Array(ordered.dropFirst(openFolderLimit)))
    }
}
