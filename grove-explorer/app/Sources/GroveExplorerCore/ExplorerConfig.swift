import Foundation
import GroveThemesCore

/// A folder in the sidebar's list.
public struct Favourite: Equatable, Sendable, Identifiable {
    /// Its table's name in the file: `[favourites.<id>]`.
    public let id: String
    public let url: URL
    public let title: String

    public init(id: String, url: URL, title: String) {
        self.id = id
        self.url = url
        self.title = title
    }
}

/// The app's settings, from `~/.config/grove-explorer/explorer.toml` (tracked)
/// and the user's `explorer.local.toml` beside it. `[general]` holds `start`,
/// `show_hidden` and `two_panes`; a `[favourites.<id>]` table is a favourite,
/// with a `path` and, when it isn't to be called by its folder, a `title`.
/// Favourites keep the order of their tables. A path is whole (`/…`) or
/// starts at the home folder (`~`, `~/…`). A `[servers.<id>]` table is a
/// share saved in the sidebar, with its `url` and its `order`; only the
/// local file's count, as only that file may name a host.
public struct ExplorerConfig: Equatable, Sendable {
    /// Where a new window opens.
    public var start: URL
    public var showHidden: Bool
    public var twoPanes: Bool
    public var favourites: [Favourite]
    /// The saved shares, by their `order` (those without one after, in
    /// file order). The local file's alone.
    public var servers: [SharedServer]
    /// What is wrong with a file that couldn't be used, with its line:
    /// "explorer.toml line 7: …". The tracked file's when both are at fault.
    public var problem: String?

    /// The shipped `explorer.toml`, word for word: what stands in for a
    /// tracked file that is missing or can't be used.
    public static let builtIn = """
        [general]
        start = "~"
        show_hidden = false
        two_panes = false

        [favourites.applications]
        path = "/Applications"

        [favourites.home]
        path = "~"
        title = "Home"

        [favourites.developer]
        path = "~/Developer"

        [favourites.documents]
        path = "~/Documents"

        [favourites.downloads]
        path = "~/Downloads"

        """

    /// The config the two files' texts give (nil for a file that isn't
    /// there). The local file's `[general]` keys override the tracked ones
    /// one by one; any favourites table in it replaces the tracked list. A
    /// file with an error counts for nothing and is named in `problem`: the
    /// tracked one gives way to `builtIn`, the local one is left out. A
    /// favourite whose folder doesn't exist is left out, and a `start` that
    /// doesn't exist is `home`.
    public static func load(tracked: String?, local: String?, home: URL, exists: (URL) -> Bool) -> ExplorerConfig {
        var problem: String?
        func layer(_ text: String?, file: String) -> Layer? {
            guard let text else { return nil }
            do { return try Layer(text, home: home) } catch {
                problem = problem ?? error.description(file: file)
                return nil
            }
        }
        let base = layer(tracked, file: "explorer.toml") ?? (try? Layer(builtIn, home: home)) ?? Layer()
        let over = layer(local, file: "explorer.local.toml") ?? Layer()

        let start = over.start ?? base.start ?? home
        return ExplorerConfig(
            start: exists(start) ? start : home,
            showHidden: over.showHidden ?? base.showHidden ?? false,
            twoPanes: over.twoPanes ?? base.twoPanes ?? false,
            favourites: (over.favourites ?? base.favourites ?? []).filter { exists($0.url) },
            servers: over.servers,
            problem: problem)
    }

    /// Every favourite the two files give, merged as `load` merges them,
    /// whether its folder exists or not. This is the list to change and
    /// write back: `load`'s own leaves out the folders that weren't there
    /// when it was read (a disk not mounted), and writing that one would
    /// drop them from the file for good.
    public static func allFavourites(tracked: String?, local: String?, home: URL) -> [Favourite] {
        load(tracked: tracked, local: local, home: home, exists: { _ in true }).favourites
    }

    /// What the app writes to `explorer.local.toml` to keep `favourites`
    /// and `servers`; nil for either leaves its tables as they are.
    ///
    /// Favourites are a table each, in order, with folders under `home`
    /// written from `~`. No favourites at all is a bare `[favourites]`
    /// table, which still replaces the tracked list. Servers are a
    /// `[servers.<id>]` table each with its `url` and its `order` (from 1);
    /// no servers is no table. A password in a url is left out.
    ///
    /// `existing` is the local file as it is now (nil: there is none). Its
    /// other tables and keys, and their comments, are kept as they are; only
    /// the tables of what is written are replaced, where the first of them
    /// stood (at the end when it had none). A file the config can't read is
    /// never written over: that throws, and nothing should be written.
    public static func localText(
        favourites: [Favourite]?, servers: [SharedServer]?, home: URL, keeping existing: String?
    ) throws(ConfigWriteRefused) -> String {
        var document = TomlDocument()
        if let existing {
            let saving = favourites == nil ? "the shared folders" : servers == nil ? "the favourites"
                : "the favourites and shared folders"
            do {
                // Read as the config reads it: what it would refuse is not
                // understood well enough to be rewritten.
                _ = try Layer(existing, home: home)
                document = try TomlDocument.parse(existing)
            } catch let error as ConfigError {
                throw ConfigWriteRefused(line: error.line, saving: saving)
            } catch {
                throw ConfigWriteRefused(line: (error as? TomlError)?.line ?? 0, saving: saving)
            }
        }
        // A file of comments alone parses as one table without a name.
        document.sections.removeAll { $0.path.isEmpty && $0.entries.isEmpty && $0.leadingComments.isEmpty }

        if let favourites {
            let homePath = home.path
            var tables = favourites.map { favourite in
                let path = favourite.url.path
                let text = path == homePath ? "~"
                    : path.hasPrefix(homePath + "/") ? "~" + path.dropFirst(homePath.count)
                    : path
                return TomlSection(path: [favouritesTable, favourite.id], entries: [
                    TomlEntry(key: "path", value: .string(text)),
                    TomlEntry(key: "title", value: .string(favourite.title)),
                ])
            }
            if tables.isEmpty { tables = [TomlSection(path: [favouritesTable])] }
            replace(favouritesTable, with: tables, in: &document)
        }
        if let servers {
            let tables = servers.enumerated().map { index, server in
                TomlSection(path: [serversTable, server.id], entries: [
                    TomlEntry(key: "url", value: .string(SharedAddress.withoutPassword(server.url).absoluteString)),
                    TomlEntry(key: "order", value: .int(index + 1)),
                ])
            }
            replace(serversTable, with: tables, in: &document)
        }
        return document.serialized()
    }

    /// `document` with its `[table…]` tables replaced by `tables`, where
    /// the first of them stood (at the end when it had none).
    private static func replace(_ table: String, with tables: [TomlSection], in document: inout TomlDocument) {
        func isOne(_ section: TomlSection) -> Bool { section.path.first == table }
        let place = document.sections.firstIndex(where: isOne)
            .map { index in document.sections[..<index].filter { !isOne($0) }.count }
        document.sections.removeAll(where: isOne)
        document.sections.insert(contentsOf: tables, at: place ?? document.sections.count)
    }

    fileprivate static let favouritesTable = "favourites"
    fileprivate static let serversTable = "servers"
}

/// Why `explorer.local.toml` was not written: it can't be read as it is.
public struct ConfigWriteRefused: Error, Equatable, Sendable {
    /// For the window's banner.
    public let description: String

    public init(description: String) {
        self.description = description
    }

    init(line: Int, saving: String) {
        let place = line > 0 ? "explorer.local.toml line \(line)" : "explorer.local.toml"
        description = "\(place) can't be read, so it was left as it is and \(saving) were not saved"
    }
}

/// What is wrong with a config file. `line` is 0 when no line is at fault
/// (a table that lacks a key).
private struct ConfigError: Error {
    var line: Int
    var message: String

    func description(file: String) -> String {
        line > 0 ? "\(file) line \(line): \(message)" : "\(file): \(message)"
    }
}

/// What one file sets: nil for what it leaves alone.
private struct Layer {
    var start: URL?
    var showHidden: Bool?
    var twoPanes: Bool?
    var favourites: [Favourite]?
    /// With the `order` each was given (nil: none) and its place in the file.
    private var ordered: [(order: Int?, server: SharedServer)] = []

    /// By `order`, those without one after, each kind in file order.
    var servers: [SharedServer] {
        ordered.enumerated()
            .sorted { a, b in
                (a.element.order ?? .max, a.offset) < (b.element.order ?? .max, b.offset)
            }
            .map(\.element.server)
    }

    init() {}

    init(_ text: String, home: URL) throws(ConfigError) {
        let document: TomlDocument
        do { document = try TomlDocument.parse(text) } catch {
            throw ConfigError(line: error.line, message: error.message)
        }
        for section in document.sections {
            let name = "[" + section.path.joined(separator: ".") + "]"
            let first = section.entries.first
            switch section.path.first {
            case nil:
                if let first { throw ConfigError(line: first.line, message: "\"\(first.key)\" is outside a table") }
            case "general" where section.path.count == 1:
                try readGeneral(section.entries, home: home)
            case ExplorerConfig.favouritesTable where section.path.count == 1:
                // The table alone says "these are the favourites": none.
                if let first {
                    throw ConfigError(line: first.line, message: "a favourite is a table of its own: [favourites.name]")
                }
                favourites = favourites ?? []
            case ExplorerConfig.favouritesTable where section.path.count == 2:
                favourites = (favourites ?? []) + [try Self.favourite(section, name: name, home: home)]
            case ExplorerConfig.serversTable where section.path.count == 1:
                if let first {
                    throw ConfigError(line: first.line, message: "a shared folder is a table of its own: [servers.name]")
                }
            case ExplorerConfig.serversTable where section.path.count == 2:
                ordered.append(try Self.server(section, name: name))
            default:
                throw ConfigError(line: first?.line ?? 0, message: "unknown table \(name)")
            }
        }
    }

    private mutating func readGeneral(_ entries: [TomlEntry], home: URL) throws(ConfigError) {
        for entry in entries {
            switch (entry.key, entry.value) {
            case ("start", .string(let text)):
                start = try Self.folder(text, of: entry, home: home)
            case ("show_hidden", .bool(let on)):
                showHidden = on
            case ("two_panes", .bool(let on)):
                twoPanes = on
            case ("start", _):
                throw ConfigError(line: entry.line, message: "\"start\" must be a string")
            case ("show_hidden", _), ("two_panes", _):
                throw ConfigError(line: entry.line, message: "\"\(entry.key)\" must be true or false")
            default:
                throw ConfigError(line: entry.line, message: "unknown key \"\(entry.key)\"")
            }
        }
    }

    private static func favourite(_ section: TomlSection, name: String, home: URL) throws(ConfigError) -> Favourite {
        var url: URL?
        var title: String?
        for entry in section.entries {
            switch (entry.key, entry.value) {
            case ("path", .string(let text)):
                url = try folder(text, of: entry, home: home)
            case ("title", .string(let text)) where !text.isEmpty:
                title = text
            case ("path", _):
                throw ConfigError(line: entry.line, message: "\"path\" must be a string")
            case ("title", _):
                throw ConfigError(line: entry.line, message: "\"title\" must be a string with text in it")
            default:
                throw ConfigError(line: entry.line, message: "unknown key \"\(entry.key)\"")
            }
        }
        guard let url else {
            throw ConfigError(line: section.entries.first?.line ?? 0, message: "\(name) has no \"path\"")
        }
        return Favourite(id: section.path[1], url: url, title: title ?? url.lastPathComponent)
    }

    private static func server(_ section: TomlSection, name: String) throws(ConfigError) -> (order: Int?, server: SharedServer) {
        var url: URL?
        var order: Int?
        for entry in section.entries {
            switch (entry.key, entry.value) {
            case ("url", .string(let text)):
                switch SharedAddress.parse(text) {
                case .success(let address): url = address
                case .failure(let problem):
                    throw ConfigError(line: entry.line, message: "\"url\" must be a share's address: \(problem.sentence)")
                }
            case ("order", .int(let number)):
                order = number
            case ("url", _):
                throw ConfigError(line: entry.line, message: "\"url\" must be a string")
            case ("order", _):
                throw ConfigError(line: entry.line, message: "\"order\" must be a number")
            default:
                throw ConfigError(line: entry.line, message: "unknown key \"\(entry.key)\"")
            }
        }
        guard let url else {
            throw ConfigError(line: section.entries.first?.line ?? 0, message: "\(name) has no \"url\"")
        }
        return (order, SharedServer(id: section.path[1], url: url))
    }

    /// The folder a path names: `~` is `home`, never the real home folder.
    private static func folder(_ text: String, of entry: TomlEntry, home: URL) throws(ConfigError) -> URL {
        if text == "~" { return home }
        if text.hasPrefix("~/") {
            let path = (home.path as NSString).appendingPathComponent(String(text.dropFirst(2)))
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if text.hasPrefix("/") { return URL(fileURLWithPath: text, isDirectory: true) }
        throw ConfigError(line: entry.line, message: "\"\(entry.key)\" must start with / or ~/")
    }
}
