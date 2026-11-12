import Foundation

/// The sentence a pane shows in place of a folder it couldn't read.
public enum ReadProblem {
    /// For a refused permission it names the one that is missing (spec §6):
    /// the folder's own entry under Privacy & Security › Files and Folders
    /// for the folders macOS guards one by one (Desktop, Documents,
    /// Downloads, iCloud Drive, removable and network volumes), and Full Disk
    /// Access for anything else macOS refuses. `refusedByMode` is for a
    /// folder closed by its own Unix mode, which no privacy setting opens.
    /// `onNetworkVolume` only matters for a folder under /Volumes.
    public static func sentence(
        for error: FolderReadError, folder: URL, home: URL, refusedByMode: Bool, onNetworkVolume: Bool
    ) -> String {
        let name = folder.lastPathComponent
        switch error {
        case .missing: return "\(name) is no longer there"
        case .notAFolder: return "\(name) is not a folder"
        case .other(let words): return words
        case .noPermission:
            if refusedByMode { return "You don't have permission to open \(name)" }
            if let permission = guardedPlace(of: folder, home: home, onNetworkVolume: onNetworkVolume) {
                return "Grove Explorer needs the \(permission) permission to open \(name) (Privacy & Security › Files and Folders)"
            }
            return "Grove Explorer needs Full Disk Access to open \(name) (Privacy & Security › Full Disk Access)"
        }
    }

    /// What Privacy & Security calls the permission that covers `folder`;
    /// nil when it is none of the places guarded one by one.
    private static func guardedPlace(of folder: URL, home: URL, onNetworkVolume: Bool) -> String? {
        let path = folder.standardizedFileURL.path
        func isIn(_ place: String) -> Bool { path == place || path.hasPrefix(place + "/") }
        let home = home.standardizedFileURL.path
        if isIn(home + "/Desktop") { return "Desktop Folder" }
        if isIn(home + "/Documents") { return "Documents Folder" }
        if isIn(home + "/Downloads") { return "Downloads Folder" }
        if isIn(home + "/Library/Mobile Documents") { return "iCloud Drive" }
        if path.hasPrefix("/Volumes/") { return onNetworkVolume ? "Network Volumes" : "Removable Volumes" }
        return nil
    }
}
