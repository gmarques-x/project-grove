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
