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
