import Foundation

/// What the window's file commands decide before the runner is asked: which
/// operation a paste is, the name of a new folder, what the rename field
/// selects, the text of what goes to the pasteboard or to Finder.
public enum FileCommands {
    /// What pasting `items` into `folder` is. Items of that folder itself
    /// are duplicated, as Finder does (a copy onto itself is no copy); the
    /// others are copied there. A move takes only what is elsewhere; when
    /// everything is already there it is made as asked, and the runner
    /// refuses it with its sentence.
    public static func paste(_ items: [URL], into folder: URL, moving: Bool) -> [Operation] {
        guard !items.isEmpty else { return [] }
        let here = folder.standardizedFileURL.path
        let fromHere = items.filter { $0.standardizedFileURL.deletingLastPathComponent().path == here }
        let fromElsewhere = items.filter { $0.standardizedFileURL.deletingLastPathComponent().path != here }
        if moving {
            return [.move(items: fromElsewhere.isEmpty ? items : fromElsewhere, to: folder)]
        }
        var operations: [Operation] = []
        if !fromElsewhere.isEmpty { operations.append(.copy(items: fromElsewhere, to: folder)) }
        if !fromHere.isEmpty { operations.append(.duplicate(items: fromHere)) }
        return operations
    }

    /// Whether the conflict prompt is shown for the names that exist: for a
    /// copy and a move. A rename and a new folder never replace anything
    /// (the runner fails them on a name in use), and the others have no target.
    public static func asksAboutNames(_ operation: Operation) -> Bool {
        switch operation {
        case .copy, .move: true
        case .duplicate, .rename, .newFolder, .trash: false
        }
    }

    /// The item of a copy or a move that goes to the name `existing` has.
    public static func incoming(for existing: URL, in operation: Operation) -> URL? {
        switch operation {
        case let .copy(items, _), let .move(items, _):
            items.first { $0.lastPathComponent == existing.lastPathComponent }
        case .duplicate, .rename, .newFolder, .trash:
            nil
        }
    }

    /// ⌘⇧N's name: "untitled folder", or the first of "untitled folder 2",
    /// "untitled folder 3"… that none of `taken` (the names the pane lists)
    /// is, in any capitals. Should the disk have the name all the same, the
    /// runner fails the new folder; nothing is ever replaced.
    public static func newFolderName(taken: [String]) -> String {
        let name = "untitled folder"
        let keys = Set(taken.map { Conflict.nameKey($0, caseSensitive: false) })
        let isTaken = { (candidate: String) in keys.contains(Conflict.nameKey(candidate, caseSensitive: false)) }
        // `taken` is a list, not the disk: some number is free.
        return isTaken(name) ? Conflict.freeName(for: name, isFolder: true, taken: isTaken) : name
    }

    /// How much of `name` the rename field selects, from its start, in
    /// UTF-16 units (as a text field counts): the name without its
    /// extension; the whole name of a folder and of a name with nothing
    /// before or after its last dot.
    public static func renameSelectionLength(of name: String, isFolder: Bool) -> Int {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex,
            name.index(after: dot) != name.endIndex
        else { return name.utf16.count }
        return name[..<dot].utf16.count
    }

    /// ⌘⌥C: the paths, one to a line.
    public static func pathsText(_ items: [URL]) -> String {
        items.map(\.path).joined(separator: "\n")
    }

    /// The AppleScript that has Finder open `item`'s information window. The
    /// path is written as a string of the script: a quote or a backslash in
    /// a name can't end it.
    public static func getInfoScript(for item: URL) -> String {
        let path = item.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"Finder\" to open information window of (POSIX file \"\(path)\" as alias)"
    }
}
