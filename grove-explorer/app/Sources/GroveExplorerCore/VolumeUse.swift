import Foundation

/// Whether a disk is in use by the window's own file commands: ejecting it
/// under a copy would fail the rest of the copy item by item.
public enum VolumeUse {
    /// A file command in hand or waiting, as far as a disk is concerned.
    public enum Command: Equatable, Sendable {
        case operation(Operation)
        /// What an undo or a redo will touch is the undo stack's to know.
        case undo, redo
    }

    /// Whether `url` is the volume's root or below it: by standardized
    /// path, on a whole path component ("/Volumes/Backup 2" is not on
    /// "/Volumes/Backup").
    public static func isOn(_ url: URL, volume: URL) -> Bool {
        let path = url.standardizedFileURL.path
        var root = volume.standardizedFileURL.path
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        if root == "/" { return true }
        return path == root || path.hasPrefix(root + "/")
    }

    /// Whether the operation reads from or writes to the volume: any of
    /// its items, or the folder it goes to, is on it.
    public static func touches(_ operation: Operation, volume: URL) -> Bool {
        let places: [URL]
        switch operation {
        case let .copy(items, folder), let .move(items, folder): places = items + [folder]
        case let .duplicate(items), let .trash(items): places = items
        case let .rename(item, _): places = [item]
        case let .newFolder(folder, _): places = [folder]
        }
        return places.contains { isOn($0, volume: volume) }
    }

    /// Why the volume called `name` is not ejected now, as a sentence for
    /// under its row; nil when it may be. `commands`: the one in hand,
    /// then those waiting. Refused while any of them touches the volume,
    /// and during an undo or a redo whatever it touches.
    public static func ejectRefusal(of name: String, at volume: URL, commands: [Command]) -> String? {
        for command in commands {
            switch command {
            case .undo: return "\(name) can't be ejected during an undo: wait for it"
            case .redo: return "\(name) can't be ejected during a redo: wait for it"
            case let .operation(operation):
                if touches(operation, volume: volume) {
                    return "\(name) is in use by \(noun(operation)): wait for it or cancel it"
                }
            }
        }
        return nil
    }

    private static func noun(_ operation: Operation) -> String {
        switch operation {
        case .copy: "a copy"
        case .move: "a move"
        case .duplicate: "a duplicate"
        case .rename: "a rename"
        case .newFolder: "a new folder"
        case .trash: "a move to the Trash"
        }
    }
}
