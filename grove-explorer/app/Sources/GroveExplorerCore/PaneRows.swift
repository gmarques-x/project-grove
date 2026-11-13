import Foundation

/// Whose rows a pane has. A pane's tab can be on a folder whose rows are
/// not there yet (it has just navigated, the read is on its way): rows of
/// the folder before are then nothing a command may act on, and what was
/// selected among them is selected no more.
public enum PaneRows {
    /// Whether rows read from `listed` are the rows of a tab on
    /// `tabFolder`: the same folder, however its path is spelled. Never
    /// without rows or without a tab.
    public static func areCurrent(listed: URL?, tabFolder: URL?) -> Bool {
        guard let listed, let tabFolder else { return false }
        return listed.standardizedFileURL.path == tabFolder.standardizedFileURL.path
    }

    /// What a read of a folder open in place (spec §16) was begun for:
    /// the tab, the folder it was on, and the open folder read.
    public struct ChildRead: Equatable, Sendable {
        public let tab: UUID
        public let tabFolder: URL
        public let folder: URL

        public init(tab: UUID, tabFolder: URL, folder: URL) {
            self.tab = tab
            self.tabFolder = tabFolder
            self.folder = folder
        }
    }

    /// Whether the entries `read` came back with go into the pane's
    /// listing now: the pane still shows that tab (`tab`), on that folder,
    /// its rows are of it (`listed`, as `areCurrent`), and the folder read
    /// is still among `open`, the tab's open folders that show
    /// (`Tree.reachable`). A read that lands after the folder was closed
    /// (or a folder it is in), renamed or deleted, after the tab went to
    /// another folder, or after the pane switched to another tab, is
    /// dropped: its rows are nothing the user can see.
    public static func isCurrent(_ read: ChildRead, tab: Tab?, listed: URL?, open: Set<URL>) -> Bool {
        guard let tab, tab.id == read.tab, tab.folder.isSameFolder(as: read.tabFolder),
            areCurrent(listed: listed, tabFolder: tab.folder)
        else { return false }
        return open.contains { $0.isSameFolder(as: read.folder) }
    }

    /// The tabs of both `was` and `now` that show another folder in `now`:
    /// their selection was of the folder they left. (A tab that is new has
    /// none yet; one that closed takes its own with it.)
    public static func tabsThatMoved(from was: Browser, to now: Browser) -> Set<UUID> {
        var folders: [UUID: String] = [:]
        for tab in was.panes.flatMap(\.tabs) { folders[tab.id] = tab.folder.standardizedFileURL.path }
        var moved: Set<UUID> = []
        for tab in now.panes.flatMap(\.tabs) {
            if let before = folders[tab.id], before != tab.folder.standardizedFileURL.path { moved.insert(tab.id) }
        }
        return moved
    }
}
