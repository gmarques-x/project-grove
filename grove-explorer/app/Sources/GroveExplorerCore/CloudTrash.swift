import Foundation

/// macOS refuses `trashItem` for items inside a File Provider domain (iCloud
/// Drive, the CloudStorage providers) from an app that doesn't hold that
/// permission; Finder can do it. These are the pure pieces of the fallback.
public enum CloudTrash {
    /// Whether `url` lies under `~/Library/Mobile Documents` or
    /// `~/Library/CloudStorage` of `home`. Compared by path components after
    /// standardising, so `Mobile Documents2` and `CloudStorageX` don't match.
    public static func isCloudItem(_ url: URL, home: URL) -> Bool {
        let item = url.standardizedFileURL.pathComponents
        let base = home.standardizedFileURL.pathComponents
        return ["Mobile Documents", "CloudStorage"].contains { folder in
            let root = base + ["Library", folder]
            return item.count > root.count && Array(item.prefix(root.count)) == root
        }
    }

    /// The AppleScript that has Finder move `url` to the Trash and answer with
    /// the item's POSIX path there. The path is written as a string of the
    /// script: a quote or a backslash in a name can't end it.
    public static func finderScript(for url: URL) -> String {
        let path = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return [
            "tell application \"Finder\"",
            "set t to delete (POSIX file \"\(path)\")",
            "return POSIX path of (t as alias)",
            "end tell",
        ].joined(separator: "\n")
    }

    public static let notAllowed = "Allow Grove Explorer to control Finder in Privacy Settings to move cloud items to the Trash"

    public static func finderFailed(_ message: String) -> String {
        "Finder couldn't move it to the Trash: \(message)"
    }
}

/// Moves an item to the Trash through Finder, answering where it landed.
public protocol FinderTrash: Sendable {
    func trash(_ url: URL) -> Result<URL, FinderTrashError>
}

public enum FinderTrashError: Error, Equatable {
    /// Control of Finder isn't allowed (Apple Event error -1743).
    case notAllowed
    /// Finder refused, with its message.
    case failed(String)
    /// The item is in the Trash, but Finder's answer didn't say where.
    case unknownLocation
}
