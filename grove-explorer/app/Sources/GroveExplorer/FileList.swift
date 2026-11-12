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
        table.setAccessibilityLabel("Files")
        for id in Column.allCases {
            let column = NSTableColumn(identifier: id.identifier)
            column.resizingMask = []
            table.addTableColumn(column)
        }
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.opened(_:))
        table.onActivate = { [weak coordinator] in coordinator?.activate() }
        table.onPointerRow = { [weak coordinator] in coordinator?.pointerMoved(to: $0) }

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
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(columns: columns)
    }

    enum Column: String, CaseIterable {
        case name, size, date, kind

        var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }
    }

    /// The table's data source and delegate: it holds the rows the table
    /// shows and brings them in line with the model on every update.
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private let model: AppModel
        private let side: Side
        weak var table: FileTableView?

        private var entries: [Entry] = []
        private var revision = -1
        private var columns: ListColumns?
        private var theme: ThemeColors?
        private var sizes: [URL: Int64] = [:]
        private var paneIsActive = true
        /// Each row's date as written, kept until the rows or the columns change.
        private var dates: [URL: String] = [:]
        /// True while the table's selection changes by this coordinator's hand, not the user's.
        private var settingSelection = false

        init(model: AppModel, side: Side) {
            self.model = model
            self.side = side
        }

        // MARK: Following the model

        func update(columns: ListColumns) {
            guard let table else { return }
            var redrawRows = false
            var reloadVisible = false

            if columns != self.columns {
                self.columns = columns
                layOut(columns, in: table)
                dates = [:]
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
            if model.sizes != sizes {
                sizes = model.sizes
                reloadVisible = true
            }

            let listing = model.listing(for: side)
            if let listing, listing.revision != revision {
                revision = listing.revision
                entries = listing.shown
                dates = [:]
                // The table's own selection is by row: it means nothing in
                // the new order, and `putSelection` below sets the right one.
                settingSelection = true
                table.reloadData()
                settingSelection = false
                reloadVisible = false
                reportVisible()
            }
            if reloadVisible {
                let rows = table.rows(in: table.visibleRect)
                table.reloadData(
                    forRowIndexes: IndexSet(integersIn: rows.location..<(rows.location + rows.length)),
                    columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
            }
            if redrawRows {
                table.enumerateAvailableRowViews { view, _ in
                    guard let view = view as? FileRowView else { return }
                    view.theme = self.model.colors
                    view.paneIsActive = active
                }
            }
            putSelection(on: table)
            if let stand = model.pointerStandIn[side] {
                table.pointerRow = entries.firstIndex { $0.url == stand } ?? -1
            }
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

        /// The model's selection, as rows; rows that went are no longer in it.
        private func putSelection(on table: NSTableView) {
            let chosen = model.selection(for: side)
            var rows = IndexSet()
            if !chosen.isEmpty {
                for (row, entry) in entries.enumerated() where chosen.contains(entry.url) { rows.insert(row) }
            }
            guard rows != table.selectedRowIndexes else { return }
            settingSelection = true
            table.selectRowIndexes(rows, byExtendingSelection: false)
            settingSelection = false
        }

        // MARK: The table asks

        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("row")
            let view = tableView.makeView(withIdentifier: id, owner: nil) as? FileRowView ?? FileRowView()
            view.identifier = id
            view.theme = model.colors
            view.paneIsActive = paneIsActive
            view.isUnderPointer = row == table?.pointerRow
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
                entries.indices.contains(row)
            else { return nil }
            let entry = entries[row]
            let theme = model.colors
            switch column {
            case .name:
                let cell = reused(NameCellView.self, tableColumn.identifier, in: tableView)
                cell.font = ListMetrics.nameFont
                cell.leading = ListColumns.edge
                cell.theme = theme
                cell.dimmed = entry.isHidden
                cell.color = NSColor(entry.isHidden ? theme.hiddenInk : theme.fg)
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
            cell.color = NSColor(theme.dim)
            return cell
        }

        private func date(of entry: Entry) -> String {
            if let known = dates[entry.url] { return known }
            let text = model.dateText(entry, short: columns?.shortDate ?? false)
            dates[entry.url] = text
            return text
        }

        /// Typing letters selects the first name that starts with them.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            entries.indices.contains(row) ? entries[row].name : nil
        }

        // MARK: The user does

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table, !settingSelection else { return }
            model.select(Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].url : nil }), in: side)
        }

        @objc func opened(_ sender: Any?) {
            guard let table, entries.indices.contains(table.clickedRow) else { return }
            model.activate(side)
            model.open(entries[table.clickedRow])
        }

        func activate() { model.activate(side) }

        func pointerMoved(to row: Int) {
            guard let table else { return }
            table.enumerateAvailableRowViews { view, at in (view as? FileRowView)?.isUnderPointer = at == row }
        }

        @objc func scrolled(_ notification: Notification) {
            table?.pointerMovedToCurrentPlace()
            reportVisible()
        }

        /// The folders and packages in view get their sizes first.
        private func reportVisible() {
            guard let table else { return }
            let rows = table.rows(in: table.visibleRect)
            let first = min(max(0, rows.location), entries.count)
            let visible = entries[first..<min(entries.count, first + rows.length)]
            model.wantSizesFirst(for: visible.filter(\.isMeasured).map(\.url))
        }
    }
}

/// The table itself: it tells which row the pointer is over and when the
/// pane is clicked (so it becomes the active one).
final class FileTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onPointerRow: ((Int) -> Void)?
    /// The row under the pointer; -1 for none.
    var pointerRow = -1 {
        didSet { if pointerRow != oldValue { onPointerRow?(pointerRow) } }
    }
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { pointerRow = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { pointerRow = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { pointerRow = -1 }

    /// After a scroll the pointer is over another row without having moved.
    func pointerMovedToCurrentPlace() {
        guard let window, window.isKeyWindow else { return }
        let place = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        pointerRow = visibleRect.contains(place) ? row(at: place) : -1
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    /// The keys came here (Tab, a click elsewhere in the pane): after the
    /// turn, since this can come while SwiftUI is updating its views.
    override func becomeFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in self?.onActivate?() }
        return super.becomeFirstResponder()
    }
}
