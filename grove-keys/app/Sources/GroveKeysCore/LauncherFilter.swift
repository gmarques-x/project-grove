/// A row of the Grove Launcher: an installed app, or a row of the Grove menu.
public enum LauncherItem: Equatable, Sendable, Identifiable {
    case app(InstalledApps.App)
    case row(LauncherEntry)

    public var id: String {
        switch self {
        case .app(let app): return "app:" + app.bundleID
        case .row(let entry): return "row:" + entry.id
        }
    }

    /// What it is ranked by: the app's name, the row's own title.
    public var name: String {
        switch self {
        case .app(let app): return app.name
        case .row(let entry): return entry.title
        }
    }
}

public enum LauncherFilter {
    /// Nothing typed: the Grove menu's rows in menu order, and no apps (a
    /// hundred of them would bury the rows; typing a letter brings them).
    ///
    /// Typed: the apps whose name, and the rows whose path, have every typed
    /// word (case and accents don't matter). Best first: a name that starts
    /// with what was typed; then one where every typed word starts a word of
    /// the name; then the rest. Within each, apps before rows, shorter names
    /// first, then the order given (apps by name, rows as in the menu).
    public static func filter(rows: [LauncherEntry], apps: [InstalledApps.App], _ query: String) -> [LauncherItem] {
        let typed = TypedWords(query)
        guard !typed.isEmpty else { return rows.map(LauncherItem.row) }
        var found: [(rank: Int, kind: Int, length: Int, order: Int, item: LauncherItem)] = []
        for app in apps {
            guard let rank = typed.rank(name: app.name, text: app.name) else { continue }
            found.append((rank, 0, app.name.count, found.count, .app(app)))
        }
        for row in rows {
            guard let rank = typed.rank(name: row.title, text: row.text) else { continue }
            found.append((rank, 1, row.title.count, found.count, .row(row)))
        }
        found.sort { ($0.rank, $0.kind, $0.length, $0.order) < ($1.rank, $1.kind, $1.length, $1.order) }
        return found.map(\.item)
    }
}
