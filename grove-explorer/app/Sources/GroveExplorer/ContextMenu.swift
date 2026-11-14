import AppKit
import GroveExplorerCore
import GroveUI

/// The right-click menu of a pane's list (spec §7): a Grove menu
/// (`GroveMenuList`), its rows from `GroveExplorerCore.ContextMenu` and, for
/// the rows that are commands, the titles, the enabled state and the
/// actions of `CommandTable`, as the menu bar and the keys have them.
@MainActor
final class ListMenu {
    private typealias Rows = GroveExplorerCore.ContextMenu

    private let model: AppModel
    private let side: Side
    /// The items the menu was opened for, in the list's order: what Open
    /// With and Show in Finder work on.
    private var items: [URL] = []
    /// The apps Open With offered when it last opened, by their rows' ids.
    private var apps: [String: URL] = [:]

    /// The ids of its rows (`choose`): a command's is "command." and its id.
    static let openWith = "openWith", showInFinder = "showInFinder", noApp = "openWith.none"
    private static let command = "command.", app = "openWith."

    init(model: AppModel, side: Side) {
        self.model = model
        self.side = side
    }

    /// The menu's rows for `items` selected (the row clicked among them);
    /// for none, the menu of the list's empty space. A separator is a line
    /// above the row after it.
    func rows(for items: [URL]) -> [GroveMenuListRow] {
        self.items = items
        apps = [:]
        var rows: [GroveMenuListRow] = [], lineAbove = false
        for item in Rows.items(selected: items.count, showsHidden: model.browser.showHidden) {
            switch item {
            case .separator:
                lineAbove = true
            case let .row(row):
                var shown = self.row(row)
                shown.separator = lineAbove
                lineAbove = false
                rows.append(shown)
            }
        }
        return rows
    }

    private func row(_ row: Rows.Row) -> GroveMenuListRow {
        switch row.action {
        case let .command(id):
            return GroveMenuListRow(
                id: Self.command + id, title: row.title,
                enabled: row.enabled && (CommandTable.command(id)?.isEnabled(model) ?? false), checked: row.checked)
        case .openWith:
            // Filled when it opens: the apps are asked for only then.
            return GroveMenuListRow(
                id: Self.openWith, title: row.title, kind: .submenu([]), enabled: row.enabled && !items.isEmpty,
                checked: row.checked, fill: { [weak self] in self?.openWithRows() ?? [] })
        case .showInFinder:
            return GroveMenuListRow(
                id: Self.showInFinder, title: row.title, enabled: row.enabled && !items.isEmpty, checked: row.checked)
        }
    }

    /// A row was chosen. The menu may be let go of some time after it was
    /// made: a command is asked again whether it is still offered.
    func choose(_ id: String) {
        if id.hasPrefix(Self.command) {
            let id = String(id.dropFirst(Self.command.count))
            guard let command = CommandTable.command(id), model.sides.contains(side) else { return }
            model.activate(side)
            guard command.isEnabled(model) else { return }
            command.run(model)
        } else if id == Self.showInFinder {
            guard !items.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(items)
        } else if let app = apps[id] {
            openWith(app)
        }
    }

    // MARK: Open With

    /// The submenu is opening: the apps that open the first selected item,
    /// the default one first and marked, each with its icon.
    func openWithRows() -> [GroveMenuListRow] {
        apps = [:]
        guard let first = items.first else { return [] }
        let found = model.openWithStandIn
            ?? (NSWorkspace.shared.urlForApplication(toOpen: first), NSWorkspace.shared.urlsForApplications(toOpen: first))
        let standard = found.standard
        var list = found.all
        list.sort { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
        if let standard {
            list.removeAll { $0.standardizedFileURL.path == standard.standardizedFileURL.path }
            list.insert(standard, at: 0)
        }
        guard !list.isEmpty else {
            return [GroveMenuListRow(id: Self.noApp, title: "No Application Opens This", kind: .note)]
        }
        var rows: [GroveMenuListRow] = []
        for (index, app) in list.enumerated() {
            let isStandard = app == standard
            let id = Self.app + String(index)
            apps[id] = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: IconMetrics.cell, height: IconMetrics.cell)
            // A line under the default one, when others follow.
            rows.append(GroveMenuListRow(
                id: id, title: Self.name(of: app) + (isStandard ? " (default)" : ""), icon: .image(icon),
                separator: index == 1 && list.first == standard))
        }
        return rows
    }

    private static func name(of app: URL) -> String {
        app.deletingPathExtension().lastPathComponent
    }

    /// Every selected item opens in the app chosen.
    private func openWith(_ app: URL) {
        guard !items.isEmpty else { return }
        let side = side, name = Self.name(of: app)
        NSWorkspace.shared.open(items, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) {
            [weak model] _, error in
            guard let error else { return }
            let why = error.localizedDescription
            Task { @MainActor in model?.say("\(name) couldn't open it: \(why)", in: side) }
        }
    }
}

extension FileList.Coordinator {
    /// A right-click in the list, on `row` (none: its empty space). As in
    /// Finder: a row that isn't selected becomes the selection; a selected
    /// one keeps the selection whole; the empty space clears it. No menu
    /// while the conflict prompt is up or a name is being typed.
    func menu(forRow row: Int) -> [GroveMenuListRow]? {
        guard let table, model.offersListMenu else { return nil }
        // A folder's loading line has no menu: it is no item, and not the list's empty space.
        if items.indices.contains(row), treeRow(onRow: row) == nil { return nil }
        model.clicked(side)
        model.listTakesKeyboard()
        if let window = table.window, window.firstResponder !== table { window.makeFirstResponder(table) }
        // The table's own selection: its delegate tells the model at once.
        if entry(onRow: row) != nil {
            if !table.isRowSelected(row) { table.selectRowIndexes([row], byExtendingSelection: false) }
        } else if table.numberOfSelectedRows > 0 {
            table.deselectAll(nil)
        }
        return menu.rows(for: model.chosenItems.map(\.url))
    }

    /// A right-click (or ⌃-click) on `row` at `point` of the table: its
    /// menu there, as the menu a key opens is (`showMenu(atRow:)`). A
    /// second right-click while one is up opens this one in its place.
    /// False when there is none to show.
    func popUpMenu(forRow row: Int, at point: NSPoint, opening: NSEvent) -> Bool {
        guard let table, let rows = menu(forRow: row) else { return false }
        GroveMenuList.popUp(rows: rows, at: point, in: table, theme: model.colors, opening: opening,
                            onChoose: { [weak self] in self?.menu.choose($0) }, onClose: {})
        return true
    }
}

extension AppModel {
    /// A list's menu is offered: not while the conflict prompt is up, a
    /// name is being typed or the app is quitting (`canTakeDrop` less its
    /// `live`, which is always so in the app: a render draws the menu too).
    var offersListMenu: Bool { work.prompt == nil && work.rename == nil && !work.quitting }

    /// The list is about to be handed the keyboard by a click that isn't
    /// the table's own to see (a right-click): a path field over it closes
    /// now, not a turn later, so the menu's commands are offered as they
    /// will be when it shows.
    func listTakesKeyboard() {
        if pathField != nil { pathField = nil }
        listHasKeyboard()
    }
}
