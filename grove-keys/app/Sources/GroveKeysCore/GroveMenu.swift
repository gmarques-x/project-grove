import Foundation
import GroveThemesCore

/// The Grove menu (the pine's dropdown and the launcher), read from
/// `~/.config/grove/menu.toml` and the owner's `menu.local.toml` beside it.
/// A table is a row; its dotted name is its id and its place in the tree.

/// The rows Grove Keys draws itself.
public enum GroveMenuBuiltin: String, Equatable, Sendable {
    /// The Grove Keys submenu (`KeysMenuItem`).
    case keys
    /// The front app's menus, as a submenu.
    case globalMenu = "global-menu"
    case lock
}

/// What a row does when chosen.
public enum GroveMenuAction: Equatable, Sendable {
    /// A shell command, run quietly.
    case run(String)
    /// A shell command, run in the Grove window (`grove present`).
    case present(String)
    /// A link or a path to open.
    case open(String)
    case builtin(GroveMenuBuiltin)
    /// One item of the Grove Keys submenu. Never from the file: see `expandingKeys`.
    case keys(KeysMenuItem.Kind)
}

public struct GroveMenuRow: Equatable, Sendable {
    /// The table's dotted name; empty for a note.
    public var id: String
    public var title: String
    /// Nil for a submenu, and for a note.
    public var action: GroveMenuAction?
    /// A shell test: the row gets a ✓ when it exits 0.
    public var checked: String?
    /// A line above the row.
    public var separator: Bool
    public var children: [GroveMenuRow]
    /// The row's icon in the pine's panel: an SF Symbol's name as the file
    /// has it (`icon = "book"`). Drawn for top-level rows, and only when it
    /// is one of Grove's icons (the app's `GroveIcon.Name`); nil for none.
    public var icon: String?

    public init(id: String, title: String, action: GroveMenuAction? = nil, checked: String? = nil,
                separator: Bool = false, children: [GroveMenuRow] = [], icon: String? = nil) {
        self.id = id
        self.title = title
        self.action = action
        self.checked = checked
        self.separator = separator
        self.children = children
        self.icon = icon
    }

    /// A line of text that can't be chosen (an error, the Grove Keys red line).
    public var isNote: Bool { action == nil && children.isEmpty }
}

/// What is wrong with a menu file. `line` is 0 when the whole file is at
/// fault (it can't be read).
public struct MenuFileError: Error, Equatable, Sendable, CustomStringConvertible {
    public var file: String
    public var line: Int
    public var message: String

    public init(file: String, line: Int, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        line > 0 ? "\(file) line \(line): \(message)" : "\(file): \(message)"
    }
}

public struct GroveMenu: Equatable, Sendable {
    public var rows: [GroveMenuRow]

    public init(rows: [GroveMenuRow]) { self.rows = rows }

    /// What stands in for a tracked file that can't be used.
    public static let fallback = GroveMenu(rows: [
        GroveMenuRow(id: "themes", title: "Grove Themes", action: .open("grovethemes://gallery")),
        GroveMenuRow(id: "keys", title: "Grove Keys", action: .builtin(.keys)),
        GroveMenuRow(id: "global-menu", title: "Global Menu", action: .builtin(.globalMenu), separator: true),
    ])

    /// The tree of `main`, with `local` merged over it: a table with a known
    /// id changes that row key by key, a new id is appended to its parent,
    /// and `hidden = true` removes a row and its children. Any error in
    /// either file is thrown (`--check-menu`).
    public static func strict(main: String, mainName: String = "menu.toml",
                              local: String? = nil, localName: String = "menu.local.toml")
        throws(MenuFileError) -> GroveMenu {
        var draft = Draft()
        try draft.merge(main, file: mainName)
        if let local { try draft.merge(local, file: localName) }
        return GroveMenu(rows: draft.rows())
    }

    /// The menu to show, whatever the files hold: a tracked file with an
    /// error gives `fallback`, a local file with one is left out, and either
    /// way the error is the first row, as a note. `local` is nil when there
    /// is no such file.
    public static func load(main: Result<String, MenuFileError>, mainName: String = "menu.toml",
                            local: Result<String, MenuFileError>?, localName: String = "menu.local.toml")
        -> GroveMenu {
        let menu: GroveMenu
        do {
            menu = try strict(main: try main.get(), mainName: mainName)
        } catch {
            return fallback.noting(error)
        }
        guard let local else { return menu }
        do {
            // The tracked file parsed above, so an error here is the local file's.
            return try strict(main: try main.get(), mainName: mainName, local: try local.get(), localName: localName)
        } catch {
            return menu.noting(error)
        }
    }

    /// `load` from the files themselves. A local file that isn't there is
    /// not an error; one that can't be read is.
    public static func read(_ paths: MenuPaths) -> GroveMenu {
        func text(_ url: URL) -> Result<String, MenuFileError> {
            do { return .success(try String(contentsOf: url, encoding: .utf8)) } catch {
                return .failure(MenuFileError(file: url.lastPathComponent, line: 0, message: "can't be read"))
            }
        }
        let hasLocal = FileManager.default.fileExists(atPath: paths.local.path)
        return load(main: text(paths.main), mainName: paths.main.lastPathComponent,
                    local: hasLocal ? text(paths.local) : nil, localName: paths.local.lastPathComponent)
    }

    /// The error as a first row, set off from the menu by a line.
    private func noting(_ error: any Error) -> GroveMenu {
        var rows = self.rows
        if !rows.isEmpty { rows[0].separator = true }
        let text = (error as? MenuFileError)?.description ?? "\(error)"
        return GroveMenu(rows: [GroveMenuRow(id: "", title: text)] + rows)
    }

    /// Every row that can be chosen or opened, submenus included.
    public var count: Int {
        func count(_ rows: [GroveMenuRow]) -> Int {
            rows.reduce(0) { $0 + ($1.isNote ? 0 : 1) + count($1.children) }
        }
        return count(rows)
    }

    /// The row with this id, at any depth.
    public func row(id: String) -> GroveMenuRow? {
        func find(_ rows: [GroveMenuRow]) -> GroveMenuRow? {
            for row in rows where !row.isNote {
                if row.id == id { return row }
                if let found = find(row.children) { return found }
            }
            return nil
        }
        return id.isEmpty ? nil : find(rows)
    }

    /// Every `icon` the files name, with its row's id, in menu order
    /// (`--check-menu` holds them to the icons Grove has).
    public var icons: [(id: String, icon: String)] {
        func icons(_ rows: [GroveMenuRow]) -> [(id: String, icon: String)] {
            rows.flatMap { row in (row.icon.map { [(row.id, $0)] } ?? []) + icons(row.children) }
        }
        return icons(rows)
    }

    /// The ids from the top of the menu down to the row `id`, itself
    /// included (`["learn", "learn.more", "learn.more.yazi"]`); empty when
    /// no row has that id.
    public func path(to id: String) -> [String] {
        func find(_ rows: [GroveMenuRow]) -> [String]? {
            for row in rows where !row.isNote {
                if row.id == id { return [row.id] }
                if let below = find(row.children) { return [row.id] + below }
            }
            return nil
        }
        return id.isEmpty ? [] : find(rows) ?? []
    }

    /// The menu with each `keys` builtin row turned into an ordinary submenu
    /// of `items`, so the launcher and `menu/<id>` reach them (`keys.pause`).
    public func expandingKeys(_ items: [KeysMenuItem]) -> GroveMenu {
        func expand(_ rows: [GroveMenuRow]) -> [GroveMenuRow] {
            rows.map { row in
                var row = row
                if row.action == .builtin(.keys) {
                    row.action = nil
                    row.children = KeysMenuItem.rows(items, under: row.id)
                } else {
                    row.children = expand(row.children)
                }
                return row
            }
        }
        return GroveMenu(rows: expand(rows))
    }
}

/// The tables of the files read so far, as a tree in file order.
private struct Draft {
    struct Node {
        var name: String
        var title: String?
        var action: GroveMenuAction?
        var checked: String?
        var separator: Bool?
        var hidden: Bool?
        /// "" takes an icon away (the local file over the tracked one).
        var icon: String?
        var children: [Node] = []
    }

    var roots: [Node] = []

    private static let actionKeys = ["run", "present", "open", "builtin"]

    mutating func merge(_ text: String, file: String) throws(MenuFileError) {
        let document: TomlDocument
        do { document = try TomlDocument.parse(text) } catch {
            throw MenuFileError(file: file, line: error.line, message: error.message)
        }
        for section in document.sections {
            func fail(_ entry: TomlEntry, _ message: String) -> MenuFileError {
                MenuFileError(file: file, line: entry.line, message: message)
            }
            guard !section.path.isEmpty else {
                if let entry = section.entries.first { throw fail(entry, "\"\(entry.key)\" is outside a table") }
                continue
            }
            var fields = Node(name: "")
            var actionKey: String?
            for entry in section.entries {
                switch (entry.key, entry.value) {
                case ("title", .string(let text)) where !text.isEmpty:
                    fields.title = text
                case ("checked", .string(let text)):
                    fields.checked = text
                case ("separator", .bool(let on)):
                    fields.separator = on
                case ("hidden", .bool(let on)):
                    fields.hidden = on
                case ("icon", .string(let text)):
                    fields.icon = text
                case (let key, .string(let text)) where Self.actionKeys.contains(key):
                    if let actionKey { throw fail(entry, "a row has one action: \"\(actionKey)\" is already set") }
                    actionKey = key
                    switch key {
                    case "run": fields.action = .run(text)
                    case "present": fields.action = .present(text)
                    case "open": fields.action = .open(text)
                    default:
                        guard let builtin = GroveMenuBuiltin(rawValue: text) else {
                            throw fail(entry, "unknown builtin \"\(text)\" (keys, global-menu, lock)")
                        }
                        fields.action = .builtin(builtin)
                    }
                case ("title", _):
                    throw fail(entry, "\"title\" must be a string with text in it")
                case ("separator", _), ("hidden", _):
                    throw fail(entry, "\"\(entry.key)\" must be true or false")
                case ("checked", _), ("icon", _), ("run", _), ("present", _), ("open", _), ("builtin", _):
                    throw fail(entry, "\"\(entry.key)\" must be a string")
                default:
                    throw fail(entry, "unknown key \"\(entry.key)\"")
                }
            }
            Self.apply(fields, at: section.path[...], in: &roots)
        }
    }

    /// Sets the keys `fields` has on the node at `path`, which is appended to
    /// its parent when new; so are missing parents.
    private static func apply(_ fields: Node, at path: ArraySlice<String>, in nodes: inout [Node]) {
        guard let name = path.first else { return }
        let index: Int
        if let found = nodes.firstIndex(where: { $0.name == name }) {
            index = found
        } else {
            nodes.append(Node(name: name))
            index = nodes.count - 1
        }
        guard path.count == 1 else {
            apply(fields, at: path.dropFirst(), in: &nodes[index].children)
            return
        }
        if let title = fields.title { nodes[index].title = title }
        if let action = fields.action { nodes[index].action = action }
        if let checked = fields.checked { nodes[index].checked = checked }
        if let separator = fields.separator { nodes[index].separator = separator }
        if let hidden = fields.hidden { nodes[index].hidden = hidden }
        if let icon = fields.icon { nodes[index].icon = icon }
    }

    /// The rows to show: hidden ones gone, a row with rows under it a submenu
    /// (its own action ignored), a row with neither left out. A row without a
    /// title is called by the last part of its id.
    func rows() -> [GroveMenuRow] {
        func rows(_ nodes: [Node], under parent: String) -> [GroveMenuRow] {
            nodes.compactMap { node in
                guard node.hidden != true else { return nil }
                let id = parent.isEmpty ? node.name : "\(parent).\(node.name)"
                let children = rows(node.children, under: id)
                let title = node.title ?? node.name
                let separator = node.separator ?? false
                let icon = node.icon.flatMap { $0.isEmpty ? nil : $0 }
                if !children.isEmpty {
                    return GroveMenuRow(id: id, title: title, separator: separator, children: children, icon: icon)
                }
                guard let action = node.action else { return nil }
                return GroveMenuRow(id: id, title: title, action: action, checked: node.checked, separator: separator,
                                    icon: icon)
            }
        }
        return rows(roots, under: "")
    }
}

/// Grove Keys' own menu, as the pine's Grove Keys ▸ submenu and
/// `grovekeys://menu` show it: permission lines, the red line, Restart while
/// it may help, then its three items.
public struct KeysMenuItem: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case accessibility
        case inputMonitoring = "input-monitoring"
        case restart
        case open
        case cheatSheet = "cheatsheet"
        case pause
    }

    /// Nil for the red line, which is text only.
    public var kind: Kind?
    public var title: String
    public var separator: Bool

    public init(kind: Kind?, title: String, separator: Bool = false) {
        self.kind = kind
        self.title = title
        self.separator = separator
    }

    public static func items(accessibility: Bool, inputMonitoring: Bool, redLine: String?,
                             offersRestart: Bool, paused: Bool) -> [KeysMenuItem] {
        var items: [KeysMenuItem] = []
        if !accessibility {
            items.append(KeysMenuItem(kind: .accessibility, title: "Grove Keys needs Accessibility — Open Settings"))
        }
        if !inputMonitoring {
            items.append(KeysMenuItem(kind: .inputMonitoring, title: "Grove Keys needs Input Monitoring — Open Settings"))
        }
        if let redLine { items.append(KeysMenuItem(kind: nil, title: redLine)) }
        if offersRestart { items.append(KeysMenuItem(kind: .restart, title: "Restart Grove Keys")) }
        items.append(KeysMenuItem(kind: .open, title: "Open Grove Keys", separator: !items.isEmpty))
        items.append(KeysMenuItem(kind: .cheatSheet, title: "Show cheat sheet"))
        items.append(KeysMenuItem(kind: .pause, title: paused ? "Resume Hyper" : "Pause Hyper"))
        return items
    }

    /// The items as menu rows under the row `id` (`keys.pause`).
    public static func rows(_ items: [KeysMenuItem], under id: String) -> [GroveMenuRow] {
        items.map { item in
            GroveMenuRow(id: item.kind.map { "\(id).\($0.rawValue)" } ?? "", title: item.title,
                         action: item.kind.map(GroveMenuAction.keys), separator: item.separator)
        }
    }
}

// MARK: Running a row

extension GroveMenuAction {
    /// The shell command a `run` or `present` row runs; nil for the others.
    /// `present` goes through `grove present`, titled with the row's title.
    public func shellCommand(title: String) -> String? {
        switch self {
        case .run(let command): return command
        case .present(let command):
            let quoted = "'" + title.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return "grove present --title \(quoted) \(command)"
        case .open, .builtin, .keys: return nil
        }
    }

    /// The row brings a window forward itself or takes the keyboard (the
    /// cheat sheet, the launcher), so the app that was in front must not be
    /// given the keyboard back when the menu closes.
    public var takesFocus: Bool {
        switch self {
        case .run, .builtin: return false
        case .present, .open: return true
        case .keys(let kind):
            switch kind {
            case .accessibility, .inputMonitoring, .restart, .open, .cheatSheet: return true
            case .pause: return false
            }
        }
    }
}

/// What an `open` row's text names.
public enum OpenTarget: Equatable, Sendable {
    /// One of Grove Keys' own links, answered without leaving the app.
    case link(KeysURL)
    /// Any other link, or a file or folder (`~` is the home folder; a
    /// relative path starts there too).
    case url(URL)

    public init?(_ text: String, home: URL) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil {
            guard let url = URL(string: text) else { return nil }
            self = KeysURL(url).map(OpenTarget.link) ?? .url(url)
        } else if text.hasPrefix("/") {
            self = .url(URL(fileURLWithPath: text))
        } else {
            let path = text == "~" ? "" : text.hasPrefix("~/") ? String(text.dropFirst(2)) : text
            self = .url(path.isEmpty ? home : home.appendingPathComponent(path))
        }
    }
}

/// The environment a row's shell command gets: the app's own, with
/// `GROVE_STATE` set (default `~/.local/state/grove`) and a PATH that has
/// `~/.local/bin` and Homebrew even when the login profile adds neither.
public enum MenuShell {
    public static func environment(from environment: [String: String], home: URL) -> [String: String] {
        var result = environment
        if (result["GROVE_STATE"] ?? "").isEmpty {
            result["GROVE_STATE"] = home.appendingPathComponent(".local/state/grove").path
        }
        var path = (result["PATH"] ?? "").split(separator: ":").map(String.init)
        if path.isEmpty { path = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] }
        let wanted = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin"]
        result["PATH"] = (wanted.filter { !path.contains($0) } + path).joined(separator: ":")
        return result
    }
}

// MARK: The launcher

/// A Grove menu row as the launcher lists it: "Appearance › Dark Medium".
public struct LauncherEntry: Equatable, Sendable {
    public var id: String
    /// The titles from the top of the menu down to the row's own.
    public var path: [String]
    public var action: GroveMenuAction
    public var checked: String?

    public var title: String { path.last ?? "" }
    public var text: String { path.joined(separator: " › ") }
}

extension GroveMenu {
    /// Every row that does something, in menu order. The Global Menu isn't
    /// listed, and neither is a `keys` builtin that wasn't expanded.
    public var launcherEntries: [LauncherEntry] {
        func entries(_ rows: [GroveMenuRow], under path: [String]) -> [LauncherEntry] {
            rows.flatMap { row -> [LauncherEntry] in
                let path = path + [row.title]
                guard let action = row.action else { return entries(row.children, under: path) }
                if action == .builtin(.keys) || action == .builtin(.globalMenu) { return [] }
                return [LauncherEntry(id: row.id, path: path, action: action, checked: row.checked)]
            }
        }
        return entries(rows, under: [])
    }
}

/// What was typed into the launcher's or the cheat sheet's field, as both
/// match it: by words, whatever the case and the accents.
public struct TypedWords: Sendable {
    private let text: String
    private let words: [Substring]

    public init(_ query: String) {
        text = Self.fold(query).trimmingCharacters(in: .whitespaces)
        words = text.split(separator: " ")
    }

    public var isEmpty: Bool { text.isEmpty }

    /// Every typed word is somewhere in `text`.
    public func areAll(in text: String) -> Bool {
        let text = Self.fold(text)
        return words.allSatisfy { text.contains($0) }
    }

    /// `text` starts with what was typed, spaces and all.
    public func start(_ text: String) -> Bool {
        Self.fold(text).hasPrefix(self.text)
    }

    /// How well a thing called `name`, found by `text` (a menu row's whole
    /// path; an app's name), matches: nil when a typed word is missing from
    /// `text`; 0 when `name` starts with what was typed; 1 when every typed
    /// word starts a word of `name`; 2 otherwise.
    public func rank(name: String, text: String) -> Int? {
        guard areAll(in: text) else { return nil }
        if start(name) { return 0 }
        let nameWords = Self.fold(name).split { !$0.isLetter && !$0.isNumber }
        return words.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } } ? 1 : 2
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
