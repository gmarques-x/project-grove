import Foundation

/// Which folder totals the window still wants: what the size walks are
/// asked for, and what a walk on its way is cancelled for not being among.
public enum SizeWanted {
    /// One pane: the folder its tab is on, the folder its rows are of (nil
    /// before the first read), and the rows.
    public struct Pane {
        public let tabFolder: URL
        public let listedFolder: URL?
        public let shown: [Entry]

        public init(tabFolder: URL, listedFolder: URL?, shown: [Entry]) {
            self.tabFolder = tabFolder
            self.listedFolder = listedFolder
            self.shown = shown
        }
    }

    /// Whether an entry's size is a total to be worked out (a package's
    /// comes from the calculator like a folder's).
    public static func isMeasured(_ entry: Entry) -> Bool {
        switch entry.kind {
        case .folder, .package: true
        case .file, .symlink, .alias, .volume: false
        }
    }

    /// The folders and packages shown by the panes whose rows are of the
    /// folder their tab is on, in the order shown, the first pane's first,
    /// each once. A pane that has navigated keeps the rows of the folder it
    /// left until the new one is read: none of those is wanted.
    public static func urls(in panes: [Pane]) -> [URL] {
        var seen: Set<URL> = []
        var wanted: [URL] = []
        for pane in panes {
            guard let listed = pane.listedFolder,
                listed.standardizedFileURL.path == pane.tabFolder.standardizedFileURL.path
            else { continue }
            for entry in pane.shown where isMeasured(entry) && seen.insert(entry.url).inserted {
                wanted.append(entry.url)
            }
        }
        return wanted
    }
}
