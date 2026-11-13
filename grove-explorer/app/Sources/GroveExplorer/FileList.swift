import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// A pane's list: an AppKit table under the Grove skin (spec §6). The table
/// gives scrolling, the selection's maths (click, ⇧-click, ⌘-click, arrows,
/// ⌘A, typing a name's start) and the reuse of rows; the header row is drawn
/// by `PaneView` above it, and the rows and cells here draw with the tokens.
struct FileList: NSViewRepresentable {
    @ObservedObject var model: AppModel
    /// The file operations: the rename field of a row follows them.
    @ObservedObject var work: FileWork
    let side: Side
    let columns: ListColumns

    func makeCoordinator() -> Coordinator { Coordinator(model: model, side: side) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = FileTableView()
        table.headerView = nil
        table.rowHeight = ListMetrics.row
        table.intercellSpacing = .zero
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        // The selection shows where the keys are; no ring round the list.
        table.focusRingType = .none
        for id in Column.allCases {
            let column = NSTableColumn(identifier: id.identifier)
            // Not drawn (the header row is `PaneView`'s): what VoiceOver calls the column.
            column.title = id.title
            column.resizingMask = []
            table.addTableColumn(column)
        }
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.opened(_:))
        // Typing a name is the model's (a second's pause, accents ignored), not the table's.
        table.allowsTypeSelect = false
        table.onKey = { [weak coordinator] in coordinator?.key($0) ?? false }
        table.onEdit = { [weak coordinator] in coordinator?.edit($0) }
        table.canEdit = { [weak coordinator] in coordinator?.canEdit($0) ?? false }
        table.onActivate = { [weak coordinator] in coordinator?.activate() }
        table.onClick = { [weak coordinator] in coordinator?.clicked() }
        table.onPointerRow = { [weak coordinator] in coordinator?.pointerMoved(to: $0) }
        table.onMenu = { [weak coordinator] in coordinator?.menu(forRow: $0) }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: ListMetrics.listPadding, left: 0, bottom: ListMetrics.listPadding, right: 0)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.scrolled(_:)), name: NSView.boundsDidChangeNotification,
            object: scroll.contentView)
        coordinator.table = table
        coordinator.quickLook.table = table
        table.quickLook = coordinator.quickLook
        coordinator.setUpDragging(table)
        coordinator.setUpTree(table)
        coordinator.offerMenuByKey()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(columns: columns)
    }

    /// The pane closed: a Quick Look panel showing its selection goes with it.
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.quickLook.detach()
    }

    enum Column: String, CaseIterable {
        case name, size, date, kind

        var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Size"
            case .date: "Date Modified"
            case .kind: "Kind"
            }
        }
    }

    /// The table's data source and delegate: it holds the rows the table
    /// shows and brings them in line with the model on every update.
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let model: AppModel
        let side: Side
        weak var table: FileTableView?

        /// The rows the table shows now: the tree's items, an open folder's
        /// loading line among them (no entry, never selected, dragged,
        /// dropped on or spoken).
        private(set) var items: [TreeItem] = []
        private var revision = -1
        private var columns: ListColumns?
        private var theme: ThemeColors?
        private var sizesVersion = -1
        private var paneIsActive = true
        /// The folder the rows are of, by its standardized path.
        private var folder: String?
        /// The model's selection as last put on the table, and the tab it was of.
        private var selectionVersion = -1
        private var tab: UUID?
        /// Each row's date as written, kept until the rows change or the
        /// dates turn short or long.
        private var dates: [URL: String] = [:]
        /// True while the table's selection changes by this coordinator's hand, not the user's.
        var settingSelection = false
        /// The model's last call for the keyboard that this list answered.
        private var listFocus = 0
        private let rename: RenameEditor
        let quickLook: QuickLookController
        let menu: ListMenu

        init(model: AppModel, side: Side) {
            self.model = model
            self.side = side
            rename = RenameEditor(model: model)
            quickLook = QuickLookController(model: model, side: side)
            menu = ListMenu(model: model, side: side)
        }

        // MARK: Following the model

        func update(columns: ListColumns) {
            guard let table else { return }
            var redrawRows = false
            var reloadVisible = false

            if columns != self.columns {
                if columns.shortDate != self.columns?.shortDate { dates = [:] }
                self.columns = columns
                layOut(columns, in: table)
                reloadVisible = true
            }
            if model.colors != theme {
                theme = model.colors
                redrawRows = true
                reloadVisible = true
            }
            let active = model.browser.active == side
            if active != paneIsActive {
                paneIsActive = active
                redrawRows = true
            }
            if model.sizesVersion != sizesVersion {
                sizesVersion = model.sizesVersion
                reloadVisible = true
            }

            let listing = model.listing(for: side)
            var newRows = false
            if let listing, listing.revision != revision {
                revision = listing.revision
                items = listing.items
                dates = [:]
                newRows = true
                // The table's own selection is by row: it means nothing in
                // the new order, and `putSelection` below sets the right one.
                settingSelection = true
                table.reloadData()
                settingSelection = false
                reloadVisible = false
                // A refresh keeps its place; another folder starts at its top.
                let path = listing.folder.standardizedFileURL.path
                if path != folder {
                    if folder != nil { scrollToTop(table) }
                    folder = path
                }
                // The table is called by its folder's name.
                table.setAccessibilityLabel(model.browser.tab(side)?.title ?? FolderName.title(of: listing.folder, home: model.home))
                reportVisible()
            } else if listing == nil, !items.isEmpty {
                // The pane has nothing of its tab's folder: no row of
                // another folder stays in the table to be opened or dragged.
                revision = -1
                items = []
                dates = [:]
                newRows = true
                settingSelection = true
                table.reloadData()
                settingSelection = false
                reloadVisible = false
            }
            // Other rows are under the pointer now (a folder opened above it): its row and lit chevron are found again.
            if newRows { table.pointerMovedToCurrentPlace() }
            if reloadVisible {
                // Every row the table has made, not only those in view: it
                // keeps some ready beyond the edges, and they scroll in as
                // they were last drawn.
                var rows = IndexSet()
                table.enumerateAvailableRowViews { _, row in rows.insert(row) }
                table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
            }
            if redrawRows {
                table.enumerateAvailableRowViews { view, _ in
                    guard let view = view as? FileRowView else { return }
                    view.theme = self.model.colors
                    view.paneIsActive = active
                }
            }
            // Another tab of the pane has a selection of its own.
            let tab = model.browser.tab(side)?.id
            if newRows || model.selectionVersion != selectionVersion || tab != self.tab {
                selectionVersion = model.selectionVersion
                self.tab = tab
                putSelection(on: table, rows: listing?.rows ?? [:])
                quickLook.selectionChanged()
            }
            if let stand = model.pointerStandIn[side] {
                table.pointerRow = listing?.rows[stand] ?? -1
            }
            if let url = model.takeReveal(for: side), let row = listing?.rows[url], row < table.numberOfRows {
                table.scrollRowToVisible(row)
            }
            putDropMark()
            let renaming = model.work.rename.flatMap { $0.side == side ? $0 : nil }
            let renamingRow = renaming.flatMap { listing?.rows[$0.url] }
            rename.update(
                renaming, row: renamingRow, depth: renamingRow.flatMap { treeRow(onRow: $0)?.depth } ?? 0, in: table,
                theme: model.colors)
            takeKeyboardIfAsked(table, active: active)
        }

        /// The model asked for the keys to be in the active pane's list (a
        /// pane switch, the path field closed, the launch): this list takes
        /// them when it is that pane's. After the turn, since this runs
        /// while SwiftUI is updating its views; asked again on the next
        /// update while the table has no window yet.
        private func takeKeyboardIfAsked(_ table: FileTableView, active: Bool) {
            guard active, model.listFocus != listFocus, table.window != nil else { return }
            listFocus = model.listFocus
            DispatchQueue.main.async { [weak table, model] in
                // A rename field that opened meanwhile keeps the keyboard:
                // taking it away would commit the name as it stands.
                guard let table, let window = table.window, window.firstResponder !== table, model.work.rename == nil
                else { return }
                window.makeFirstResponder(table)
            }
        }

        private func scrollToTop(_ table: NSTableView) {
            guard let scroll = table.enclosingScrollView else { return }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        private func layOut(_ columns: ListColumns, in table: NSTableView) {
            func set(_ id: Column, width: Double?) {
                guard let column = table.tableColumn(withIdentifier: id.identifier) else { return }
                column.isHidden = width == nil
                if let width {
                    column.minWidth = width
                    column.maxWidth = width
                    column.width = width
                }
            }
            set(.name, width: ListColumns.edge + columns.name)
            set(.size, width: ListColumns.size)
            set(.date, width: columns.showsDate ? ListColumns.gap + columns.date : nil)
            set(.kind, width: columns.showsKind ? ListColumns.gap + ListColumns.kind : nil)
        }

        /// The model's selection, as rows: found through the listing's row
        /// index, so a selection costs its own size and not the folder's.
        /// What is selected and not shown (a hidden item) has no row.
        private func putSelection(on table: NSTableView, rows: [URL: Int]) {
            var chosen = IndexSet()
            for url in model.selection(for: side) {
                if let row = rows[url] { chosen.insert(row) }
            }
            guard chosen != table.selectedRowIndexes else { return }
            settingSelection = true
            table.selectRowIndexes(chosen, byExtendingSelection: false)
            settingSelection = false
        }

        // MARK: The table asks

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        /// A folder's loading line is no row to select: a click on it
        /// selects nothing, and the arrows pass over it.
        /// (A row the table selects some other way, ⇧-click over one say,
        /// is no URL: `tableViewSelectionDidChange` leaves it out, and the
        /// model's selection is put back on the table.)
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { entry(onRow: row) != nil }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("row")
            let view = tableView.makeView(withIdentifier: id, owner: nil) as? FileRowView ?? FileRowView()
            view.identifier = id
            view.theme = model.colors
            view.paneIsActive = paneIsActive
            view.isUnderPointer = row == table?.pointerRow
            view.isInert = treeRow(onRow: row) == nil
            view.isDropTarget = row == table?.dropRow
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
                items.indices.contains(row)
            else { return nil }
            let theme = model.colors
            guard case .row(let shown) = items[row] else {
                // A loading line: "···" in the Name column at its level, the other columns empty.
                guard column == .name, case .loading(_, let depth) = items[row] else { return nil }
                let cell = reused(NameCellView.self, tableColumn.identifier, in: tableView)
                cell.font = ListMetrics.nameFont
                cell.theme = theme
                cell.depth = depth
                cell.isLoadingLine = true
                cell.chevron = nil
                cell.color = NSColor(theme.quiet)
                return cell
            }
            let entry = shown.entry
            switch column {
            case .name:
                let cell = reused(NameCellView.self, tableColumn.identifier, in: tableView)
                cell.font = ListMetrics.nameFont
                cell.theme = theme
                cell.depth = shown.depth
                cell.isLoadingLine = false
                cell.chevron = TreeLayout.chevron(for: shown.fold)
                cell.chevronLit = row == table?.chevronRow
                cell.dimmed = entry.isHidden
                // Kept by the filter for a match inside: the name is quiet, the icon and chevron as ever.
                if entry.isHidden {
                    cell.color = NSColor(theme.hiddenText)
                } else if shown.isContext {
                    cell.color = NSColor(theme.quiet)
                } else {
                    cell.color = NSColor(theme.fg)
                }
                cell.icon = IconCache.shared.icon(for: entry, light: theme.isLight)
                cell.text = entry.name
                return cell
            case .size:
                let cell = detail(tableColumn.identifier, in: tableView, theme)
                cell.alignment = .right
                cell.text = model.sizeText(entry)
                return cell
            case .date:
                let cell = detail(tableColumn.identifier, in: tableView, theme)
                cell.leading = ListColumns.gap
                cell.text = date(of: entry)
                return cell
            case .kind:
                let cell = detail(tableColumn.identifier, in: tableView, theme)
                cell.leading = ListColumns.gap
                cell.text = entry.typeDescription
                return cell
            }
        }

        private func reused<Cell: TextCellView>(
            _ type: Cell.Type, _ id: NSUserInterfaceItemIdentifier, in table: NSTableView
        ) -> Cell {
            if let cell = table.makeView(withIdentifier: id, owner: nil) as? Cell { return cell }
            let cell = Cell(frame: .zero)
            cell.identifier = id
            return cell
        }

        /// A cell of the quiet columns: 11 pt, in the quiet colour.
        private func detail(_ id: NSUserInterfaceItemIdentifier, in table: NSTableView, _ theme: ThemeColors) -> TextCellView {
            let cell = reused(TextCellView.self, id, in: table)
            cell.color = NSColor(theme.quiet)
            return cell
        }

        /// The entry on a row; nil for a loading line or no row.
        func entry(onRow row: Int) -> Entry? {
            guard items.indices.contains(row), case .row(let shown) = items[row] else { return nil }
            return shown.entry
        }

        /// The tree's row on a row of the table; nil for a loading line or no row.
        func treeRow(onRow row: Int) -> TreeRow? {
            guard items.indices.contains(row), case .row(let shown) = items[row] else { return nil }
            return shown
        }

        /// The item on a row, and the row an item is on: through the
        /// listing's index while the table shows that listing's rows.
        func item(onRow row: Int) -> URL? { entry(onRow: row)?.url }

        /// Whether the table's rows are the ones the model has for the
        /// pane now. Not for the moment between a change to the model and
        /// this list's next update: a row is then not opened or dragged.
        var showsModelRows: Bool { model.listing(for: side)?.revision == revision }

        func row(of item: URL) -> Int? {
            if let listing = model.listing(for: side), listing.revision == revision { return listing.rows[item] }
            return items.firstIndex { if case .row(let row) = $0 { row.entry.url == item } else { false } }
        }

        /// The row as VoiceOver says it; nil for a row that is not there.
        func spoken(_ row: Int) -> String? {
            guard let shown = treeRow(onRow: row) else { return nil }
            let entry = shown.entry
            return Spoken.row(
                entry, total: model.sizes[entry.url], date: entry.modified == nil ? nil : date(of: entry),
                awaitsTotal: model.awaitsTotal(entry.url), level: shown.depth + 1, fold: shown.fold)
        }

        private func date(of entry: Entry) -> String {
            if let known = dates[entry.url] { return known }
            let text = model.dateText(entry, short: columns?.shortDate ?? false)
            dates[entry.url] = text
            return text
        }
    }
}
