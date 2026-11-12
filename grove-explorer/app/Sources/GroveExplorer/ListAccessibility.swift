import AppKit
import GroveExplorerCore

// The list for VoiceOver. A table's own stand-ins for its rows offer one
// cell per column and take no words from the row's view: with cells that
// are drawings, each row was a sentence followed by things that say
// nothing, and the columns had no names. So the table hands out rows and
// columns of its own here: a row is one thing with its sentence
// (`Spoken.row`), whether it is selected, and its menu; it has no cells.

/// One row of the list, as VoiceOver meets it. An object of its own that
/// answers the accessibility protocol's questions for a row (AppKit asks
/// each by name), not a view: there is one for every row of the folder,
/// in view or not. (Accessibility asks on the main thread; the protocol
/// doesn't say so, hence `@preconcurrency`.)
@MainActor
final class ListRowElement: NSObject, @preconcurrency NSAccessibilityRow {
    private weak var table: FileTableView?
    private let row: Int

    init(row: Int, in table: FileTableView) {
        self.row = row
        self.table = table
    }

    func accessibilityParent() -> Any? { table }
    func accessibilityIndex() -> Int { row }
    @objc func isAccessibilityElement() -> Bool { true }
    @objc func accessibilityRole() -> NSAccessibility.Role? { .row }
    @objc func accessibilitySubrole() -> NSAccessibility.Subrole? { .tableRow }
    @objc func accessibilityChildren() -> [Any]? { [] }

    /// "notes.md, Markdown, 4 KB, Today at 09:41": asked for when
    /// VoiceOver comes to the row, not while the list is drawn.
    @objc func accessibilityLabel() -> String? { table?.onRowLabel?(row) }

    @objc func isAccessibilitySelected() -> Bool { table?.isRowSelected(row) ?? false }

    @objc func setAccessibilitySelected(_ selected: Bool) {
        guard let table, row < table.numberOfRows else { return }
        if selected { table.selectRowIndexes([row], byExtendingSelection: false) } else { table.deselectRow(row) }
    }

    /// On the screen, as the accessibility protocol has frames.
    func accessibilityFrame() -> NSRect {
        guard let table, let window = table.window, row < table.numberOfRows else { return .zero }
        return window.convertToScreen(table.convert(table.rect(ofRow: row), to: nil))
    }

    /// VoiceOver's "show menu": the right-click menu, for this row when it
    /// is not among the selected.
    @objc func accessibilityPerformShowMenu() -> Bool {
        guard let table, row < table.numberOfRows else { return false }
        if !table.isRowSelected(row) { table.selectRowIndexes([row], byExtendingSelection: false) }
        table.onMenuKey?()
        return true
    }
}

/// One column: its name, which the table itself never draws.
@MainActor
final class ListColumnElement: NSObject, @preconcurrency NSAccessibilityElementProtocol {
    private weak var table: FileTableView?
    let column: NSTableColumn

    init(_ column: NSTableColumn, in table: FileTableView) {
        self.column = column
        self.table = table
    }

    func accessibilityParent() -> Any? { table }
    @objc func isAccessibilityElement() -> Bool { true }
    @objc func accessibilityRole() -> NSAccessibility.Role? { .column }
    @objc func accessibilityLabel() -> String? { column.title }
    @objc func accessibilityChildren() -> [Any]? { [] }

    func accessibilityFrame() -> NSRect {
        guard let table, let window = table.window, let index = table.tableColumns.firstIndex(of: column)
        else { return .zero }
        return window.convertToScreen(table.convert(table.rect(ofColumn: index).intersection(table.visibleRect), to: nil))
    }
}

extension FileTableView {
    /// Every row, made once per set of rows (a large folder's are only
    /// made when VoiceOver asks).
    private var rowElements: [ListRowElement] {
        if let rows = spokenRows, rows.count == numberOfRows { return rows }
        let rows = (0..<numberOfRows).map { ListRowElement(row: $0, in: self) }
        spokenRows = rows
        return rows
    }

    /// The columns the pane has room for.
    private var columnElements: [ListColumnElement] {
        let shown = tableColumns.filter { !$0.isHidden }
        if let columns = spokenColumns, columns.map(\.column) == shown { return columns }
        let columns = shown.map { ListColumnElement($0, in: self) }
        spokenColumns = columns
        return columns
    }

    private func elements(_ rows: IndexSet) -> [ListRowElement] {
        let all = rowElements
        return rows.compactMap { all.indices.contains($0) ? all[$0] : nil }
    }

    override func accessibilityChildren() -> [Any]? {
        rowElements + columnElements + (renameField.map { [$0] } ?? [])
    }

    override func accessibilityRows() -> [any NSAccessibilityRow]? { rowElements }

    override func accessibilityVisibleRows() -> [any NSAccessibilityRow]? {
        let range = rows(in: visibleRect)
        return elements(IndexSet(integersIn: range.location..<(range.location + range.length)))
    }

    override func accessibilitySelectedRows() -> [any NSAccessibilityRow]? { elements(selectedRowIndexes) }

    override func setAccessibilitySelectedRows(_ rows: [any NSAccessibilityRow]?) {
        let chosen = IndexSet((rows ?? []).map { $0.accessibilityIndex() }.filter { $0 >= 0 && $0 < numberOfRows })
        selectRowIndexes(chosen, byExtendingSelection: false)
    }

    override func accessibilityColumns() -> [Any]? { columnElements }
    override func accessibilityVisibleColumns() -> [Any]? { columnElements }

    // The same answers to the older way of asking, which the table has
    // answers of its own to (its stand-ins) and assistive apps may still
    // be served by: by attribute, and for a part of a long list.

    private func older(_ attribute: NSAccessibility.Attribute) -> [Any]? {
        switch attribute {
        case .rows: rowElements
        case .visibleRows: accessibilityVisibleRows()
        case .selectedRows: accessibilitySelectedRows()
        case .children: accessibilityChildren()
        case .visibleChildren:
            (accessibilityVisibleRows() ?? []) + columnElements + (renameField.map { [$0] } ?? [])
        case .columns, .visibleColumns: columnElements
        default: nil
        }
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        onMain { self.older(attribute) } ?? super.accessibilityAttributeValue(attribute)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityArrayAttributeCount(_ attribute: NSAccessibility.Attribute) -> Int {
        onMain { self.older(attribute) }?.count ?? super.accessibilityArrayAttributeCount(attribute)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityArrayAttributeValues(
        _ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int
    ) -> [Any] {
        guard let all = onMain({ self.older(attribute) }) else {
            return super.accessibilityArrayAttributeValues(attribute, index: index, maxCount: maxCount)
        }
        guard index >= 0, index < all.count, maxCount > 0 else { return [] }
        return Array(all[index..<min(all.count, index + maxCount)])
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityIndex(ofChild child: Any) -> Int {
        let asked = Handed(value: child)
        let own: Int? = onMain {
            if let row = asked.value as? ListRowElement { return row.accessibilityIndex() }
            if let column = asked.value as? ListColumnElement {
                return self.numberOfRows + (self.columnElements.firstIndex { $0 === column } ?? 0)
            }
            return nil
        }
        return own ?? super.accessibilityIndex(ofChild: child)
    }

    /// Where the keyboard is, for VoiceOver: the row the selection last
    /// moved to, else the list itself.
    override var accessibilityFocusedUIElement: Any? {
        onMain { self.elements(self.selectedRow >= 0 ? [self.selectedRow] : []).first } ?? self
    }

    /// What is under a point of the screen: the row there, else the list.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        let found: ListRowElement? = onMain {
            guard let window = self.window else { return nil }
            let row = self.row(at: self.convert(window.convertPoint(fromScreen: point), from: nil))
            return self.elements(row >= 0 ? [row] : []).first
        }
        return found ?? self
    }
}

/// The older accessibility methods don't say they are called on the main
/// thread (they are): their answers are made there and handed back.
private struct Handed<Value>: @unchecked Sendable {
    let value: Value
}

private func onMain<Value>(_ body: @MainActor () -> Value) -> Value {
    MainActor.assumeIsolated { Handed(value: body()) }.value
}
