import Foundation

/// The path bar: a folder as the parts to click, and typed text as a folder.
public enum PathBar {
    public struct Part: Equatable, Sendable {
        public let title: String
        public let url: URL

        public init(title: String, url: URL) {
            self.title = title
            self.url = url
        }
    }

    /// The folders from the top down to `folder`. The top is `home`, titled
    /// "Home", when the folder is it or under it; otherwise the volume it is
    /// on (the deepest of `volumes` above it), titled with the volume's name.
    /// With no such volume the parts start at `/`.
    ///
    /// The path is taken as given (`/private/tmp` is not shortened to
    /// `/tmp`), with `.` and `..` worked out.
    public static func parts(of folder: URL, home: URL, volumes: [URL]) -> [Part] {
        let names = names(in: folder.path)
        // The folder and each one above it, from `/` down.
        let folders = (0...names.count).map { url(names.prefix($0)) }

        var top = 0
        var title = "/"
        if let index = folders.lastIndex(where: { $0.isSameFolder(as: home) }) {
            top = index
            title = "Home"
        } else if let index = folders.lastIndex(where: { folder in
            volumes.contains { $0.isSameFolder(as: folder) }
        }), let volume = volumes.first(where: { $0.isSameFolder(as: folders[index]) }) {
            top = index
            title = name(ofVolume: volume)
        }

        return [Part(title: title, url: folders[top])]
            + folders.indices.dropFirst(top + 1).map { Part(title: names[$0 - 1], url: folders[$0]) }
    }

    /// The folder that text typed in the path bar means: `~` and `~/x` from
    /// `home`, a path starting with `/` as it is, anything else from
    /// `relativeTo` (`../y`, `x/y`). Nothing typed is `relativeTo` itself.
    /// Whether the folder exists is for the caller to find out.
    public static func resolve(_ typed: String, relativeTo: URL, home: URL) -> URL {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if text == "~" || text.hasPrefix("~/") {
            path = home.path + text.dropFirst()
        } else if text.hasPrefix("/") {
            path = text
        } else {
            path = relativeTo.path + "/" + text
        }
        return url(names(in: path)[...])
    }

    /// A folder as the path field writes it: from `~` when it is `home` or
    /// under it, else whole. `resolve` reads it back to the same folder.
    public static func text(for folder: URL, home: URL) -> String {
        let path = folder.path, homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    // MARK: Where a path leads

    public enum ItemKind: Equatable, Sendable {
        case folder, file
    }

    public enum Destination: Equatable, Sendable {
        /// A folder to show.
        case folder(URL)
        /// A file: its folder to show, and the file to select there.
        case item(URL, in: URL)
        /// Nothing is there.
        case missing
    }

    /// Where a typed path or a link's path leads. `kind` says what is at a
    /// URL (nil: nothing); it is the caller's look at the disk.
    public static func destination(of url: URL, kind: (URL) -> ItemKind?) -> Destination {
        switch kind(url) {
        case .folder: return .folder(url)
        case .file:
            let file = URL(fileURLWithPath: url.path)
            return .item(file, in: file.deletingLastPathComponent())
        case nil: return .missing
        }
    }

    // MARK: Completing

    /// What Tab makes of `typed`: the last name completed to the one folder
    /// that starts with it (then a "/" follows), or as far as the several
    /// that do agree. Case is ignored; the folder's own spelling is written.
    /// Nil when there is nothing to add. `folders` names the folders inside
    /// a folder (the caller's look at the disk).
    public static func completed(
        _ typed: String, relativeTo: URL, home: URL, folders: (URL) -> [String]
    ) -> String? {
        let slash = typed.lastIndex(of: "/")
        let head = slash.map { String(typed[...$0]) } ?? ""
        let start = slash.map { String(typed[typed.index(after: $0)...]) } ?? typed
        guard !start.isEmpty else { return nil }
        let within = resolve(head, relativeTo: relativeTo, home: home)
        let candidates = folders(within).filter {
            $0.range(of: start, options: [.caseInsensitive, .anchored]) != nil
        }
        guard let first = candidates.first else { return nil }
        if candidates.count == 1 { return head + first + "/" }
        var common = first
        for candidate in candidates.dropFirst() {
            common = String(zip(common, candidate).prefix { String($0).lowercased() == String($1).lowercased() }.map(\.0))
        }
        return common.count > start.count ? head + common : nil
    }

    // MARK: Paths

    /// The names along an absolute path, with `.` dropped and `..` taking
    /// the name before it away; `..` at the root stays at the root. Only the
    /// text is looked at: a link is not followed.
    private static func names(in path: String) -> [String] {
        var names: [String] = []
        for name in path.split(separator: "/") {
            switch name {
            case ".": break
            case "..": _ = names.popLast()
            default: names.append(String(name))
            }
        }
        return names
    }

    private static func url(_ names: ArraySlice<String>) -> URL {
        URL(fileURLWithPath: "/" + names.joined(separator: "/"), isDirectory: true)
    }

    /// What macOS calls the volume ("Macintosh HD" for `/`); the name of its
    /// folder when macOS doesn't say.
    private static func name(ofVolume volume: URL) -> String {
        let values = try? volume.resourceValues(forKeys: [.volumeLocalizedNameKey])
        return values?.volumeLocalizedName ?? volume.lastPathComponent
    }
}
