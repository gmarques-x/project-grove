import AppKit
import GroveExplorerCore

/// The right-click menu of a pane's list (spec §7): the system's menu, its
/// rows from `GroveExplorerCore.ContextMenu` and, for the rows that are
/// commands, the titles, the enabled state and the actions of
/// `CommandTable`, as the menu bar and the keys have them.
@MainActor
final class ListMenu: NSObject, NSMenuDelegate {
    private typealias Rows = GroveExplorerCore.ContextMenu

    private let model: AppModel
    private let side: Side
    /// The items the menu was opened for, in the list's order: what Open
    /// With and Show in Finder work on.
    private var items: [URL] = []

    init(model: AppModel, side: Side) {
        self.model = model
        self.side = side
    }

    /// The menu for `items` selected (the row clicked among them); for
    /// none, the menu of the list's empty space.
    func menu(for items: [URL]) -> NSMenu {
        self.items = items
        let menu = NSMenu()
        // Each row says itself whether it is offered: nothing is asked of
        // the responder chain.
        menu.autoenablesItems = false
        for item in Rows.items(selected: items.count, showsHidden: model.browser.showHidden) {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case let .row(row):
                menu.addItem(self.item(row))
            }
        }
        return menu
    }

    private func item(_ row: Rows.Row) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        item.target = self
        item.state = row.checked ? .on : .off
        switch row.action {
        case let .command(id):
            item.action = #selector(run(_:))
            item.representedObject = id
            item.isEnabled = row.enabled && (CommandTable.command(id)?.isEnabled(model) ?? false)
        case .openWith:
            // Filled when it opens: the apps are asked for only then.
            let apps = NSMenu()
            apps.autoenablesItems = false
            apps.delegate = self
            item.submenu = apps
            item.isEnabled = row.enabled && !items.isEmpty
        case .showInFinder:
            item.action = #selector(showInFinder(_:))
            item.isEnabled = row.enabled && !items.isEmpty
        }
        return item
    }

    /// The menu may be let go of some time after it was made: the command
    /// is asked again whether it is still offered.
    @objc private func run(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let command = CommandTable.command(id),
            model.sides.contains(side)
        else { return }
        model.activate(side)
        guard command.isEnabled(model) else { return }
        command.run(model)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items)
    }

    // MARK: Open With

    /// The submenu is about to show: the apps that open the first selected
    /// item, the default one first and marked.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let first = items.first else { return }
        let standard = NSWorkspace.shared.urlForApplication(toOpen: first)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        apps.sort { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
        if let standard {
            apps.removeAll { $0.standardizedFileURL.path == standard.standardizedFileURL.path }
            apps.insert(standard, at: 0)
        }
        guard !apps.isEmpty else {
            let none = NSMenuItem(title: "No Application Opens This", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        for app in apps {
            let isStandard = app == standard
            let item = NSMenuItem(
                title: Self.name(of: app) + (isStandard ? " (default)" : ""), action: #selector(openWith(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: IconMetrics.cell, height: IconMetrics.cell)
            item.image = icon
            menu.addItem(item)
            if isStandard, apps.count > 1 { menu.addItem(.separator()) }
        }
    }

    private static func name(of app: URL) -> String {
        app.deletingPathExtension().lastPathComponent
    }

    /// Every selected item opens in the app chosen.
    @objc private func openWith(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL, !items.isEmpty else { return }
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
    func menu(forRow row: Int) -> NSMenu? {
        guard let table, model.canTakeDrop else { return nil }
        model.clicked(side)
        model.listTakesKeyboard()
        if let window = table.window, window.firstResponder !== table { window.makeFirstResponder(table) }
        // The table's own selection: its delegate tells the model at once.
        if entries.indices.contains(row) {
            if !table.isRowSelected(row) { table.selectRowIndexes([row], byExtendingSelection: false) }
        } else if table.numberOfSelectedRows > 0 {
            table.deselectAll(nil)
        }
        return menu.menu(for: model.chosenItems.map(\.url))
    }
}

extension AppModel {
    /// The list is about to be handed the keyboard by a click that isn't
    /// the table's own to see (a right-click): a path field over it closes
    /// now, not a turn later, so the menu's commands are offered as they
    /// will be when it shows.
    func listTakesKeyboard() {
        if pathField != nil { pathField = nil }
    }
}
