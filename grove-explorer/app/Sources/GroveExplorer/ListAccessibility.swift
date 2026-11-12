import AppKit
import GroveExplorerCore

// The list for VoiceOver. A table's own stand-ins for its rows offer one
// cell per column and take no words from the row's view: with cells that
// are drawings, each row was a sentence followed by things that say
// nothing, and the columns had no names. So the table hands out rows and
// columns of its own here: a row is one thing with its sentence
// (`Spoken.row`), whether it is selected, and its menu; it has no cells.
// They are `NSAccessibilityElement`s, so what a row doesn't answer itself
// (its window, its top-level element) is answered as for any element.

/// One row of the list, as VoiceOver meets it: the item it shows, in its
/// table. Made afresh for each answer, and equal to any other made for
/// the same item of the same table: so VoiceOver's place on a row holds
/// when the list is read again (the folder changed, another sort), and
/// follows the item when rows above it come or go.
final class ListRowElement: NSAccessibilityElement {
    // Only ever touched on the main thread, where accessibility asks.
    fileprivate weak var table: FileTableView?
    let item: URL
    /// Itself, to take into the main actor's code (see `onMain`).
    private var me: Handed<ListRowElement> { Handed(value: self) }

    /// AppKit takes a table's rows as `NSAccessibilityRow`. An
    /// `NSAccessibilityElement` can't be declared one in Swift (the two
    /// disagree on `accessibilityIdentifier`), so the class is told so
    /// where the question is put: to the Objective-C runtime, once.
    static let isARow: Bool = class_addProtocol(ListRowElement.self, NSAccessibilityRow.self)

    init(item: URL, in table: FileTableView) {
        self.item = item
        self.table = table
        super.init()
        _ = Self.isARow
        setAccessibilityRole(.row)
        setAccessibilitySubrole(.tableRow)
        setAccessibilityParent(table)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ListRowElement else { return false }
        return other.item == item && other.table === table
    }

    override var hash: Int { item.hashValue }

    /// Where the item is in the list now; nil when it is no longer listed.
    private var row: Int? {
        onMain { [me] in me.value.table.flatMap { table in table.onRowOf?(me.value.item).flatMap { $0 < table.numberOfRows ? $0 : nil } } }
    }

    override func accessibilityIndex() -> Int { row ?? NSNotFound }
    override func accessibilityChildren() -> [Any]? { [] }

    /// "notes.md, Markdown, 4 KB, Today at 09:41": asked for when
    /// VoiceOver comes to the row, not while the list is drawn.
    override func accessibilityLabel() -> String? {
        row.flatMap { row in onMain { [me] in me.value.table?.onRowLabel?(row) } }
    }

    override func isAccessibilitySelected() -> Bool {
        row.map { row in onMain { [me] in me.value.table?.isRowSelected(row) ?? false } } ?? false
    }

    /// Selecting by VoiceOver is a click as far as the panes go: the
    /// row's pane gets the keys.
    override func setAccessibilitySelected(_ selected: Bool) {
        guard let row else { return }
        onMain { [me] in
            guard let table = me.value.table else { return }
            table.onClick?()
            if selected { table.selectRowIndexes([row], byExtendingSelection: false) } else { table.deselectRow(row) }
        }
    }

    /// On the screen, as the accessibility protocol has frames.
    override func accessibilityFrame() -> NSRect {
        guard let row else { return .zero }
        return onMain { [me] in
            guard let table = me.value.table, let window = table.window else { return .zero }
            return window.convertToScreen(table.convert(table.rect(ofRow: row), to: nil))
        }
    }

    /// VoiceOver's "show menu": this list's right-click menu for this
    /// row, as a right-click on it gives (its pane gets the keys, the row
    /// becomes the selection unless it is among the selected). False when
    /// no menu could be shown.
    override func accessibilityPerformShowMenu() -> Bool {
        guard let row else { return false }
        return onMain { [me] in me.value.table?.onRowMenu?(row) ?? false }
    }
}

/// One column: its name, which the table itself never draws.
final class ListColumnElement: NSAccessibilityElement {
    fileprivate weak var table: FileTableView?
    let column: NSTableColumn
    private var me: Handed<ListColumnElement> { Handed(value: self) }

    init(_ column: NSTableColumn, in table: FileTableView) {
        self.column = column
        self.table = table
        super.init()
        setAccessibilityRole(.column)
        setAccessibilityLabel(onMain { column.title })
        setAccessibilityParent(table)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ListColumnElement else { return false }
        return other.column === column && other.table === table
    }

    override var hash: Int { ObjectIdentifier(column).hashValue }

    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityFrame() -> NSRect {
        onMain { [me] in
            guard let table = me.value.table, let window = table.window,
                let index = table.tableColumns.firstIndex(of: me.value.column)
            else { return .zero }
            return window.convertToScreen(table.convert(table.rect(ofColumn: index).intersection(table.visibleRect), to: nil))
        }
    }
}

extension FileTableView {
    private func element(_ row: Int) -> ListRowElement? {
        onRowURL?(row).map { ListRowElement(item: $0, in: self) }
    }

    private func elements<Rows: Sequence>(_ rows: Rows) -> [ListRowElement] where Rows.Element == Int {
        rows.compactMap { $0 >= 0 && $0 < numberOfRows ? element($0) : nil }
    }

    private var rowElements: [ListRowElement] { elements(0..<numberOfRows) }

    /// The columns the pane has room for.
    private var columnElements: [ListColumnElement] {
        tableColumns.filter { !$0.isHidden }.map { ListColumnElement($0, in: self) }
    }

    private var visibleRowRange: Range<Int> {
        let range = rows(in: visibleRect)
        return range.location..<(range.location + range.length)
    }

    /// As AppKit's typed methods want rows (see `ListRowElement.isARow`).
    private func typed(_ rows: [ListRowElement]) -> [any NSAccessibilityRow] {
        rows.compactMap { ($0 as AnyObject) as? any NSAccessibilityRow }
    }

    override func accessibilityChildren() -> [Any]? {
        rowElements + columnElements + (renameField.map { [$0] } ?? [])
    }

    override func accessibilityRows() -> [any NSAccessibilityRow]? { typed(rowElements) }
    override func accessibilityVisibleRows() -> [any NSAccessibilityRow]? { typed(elements(visibleRowRange)) }
    override func accessibilitySelectedRows() -> [any NSAccessibilityRow]? { typed(elements(selectedRowIndexes)) }

    /// Selecting by VoiceOver is a click as far as the panes go: the
    /// list's pane gets the keys.
    override func setAccessibilitySelectedRows(_ rows: [any NSAccessibilityRow]?) {
        let chosen = IndexSet((rows ?? []).map { $0.accessibilityIndex() }.filter { $0 >= 0 && $0 < numberOfRows })
        onClick?()
        selectRowIndexes(chosen, byExtendingSelection: false)
    }

    override func accessibilityColumns() -> [Any]? { columnElements }
    override func accessibilityVisibleColumns() -> [Any]? { columnElements }

    // The same answers to the older way of asking, which the table has
    // answers of its own to (its stand-ins) and assistive apps may still
    // be served by: by attribute, and for a part of a long list.

    /// The rows an attribute is about, by index; nil for one that is not
    /// about rows. A part of a long list is then made without the whole.
    private func rowIndexes(_ attribute: NSAccessibility.Attribute) -> [Int]? {
        switch attribute {
        case .rows: Array(0..<numberOfRows)
        case .visibleRows: Array(visibleRowRange)
        case .selectedRows: Array(selectedRowIndexes)
        default: nil
        }
    }

    private func older(_ attribute: NSAccessibility.Attribute) -> [Any]? {
        if let rows = rowIndexes(attribute) { return elements(rows) }
        switch attribute {
        case .children: return accessibilityChildren()
        case .visibleChildren:
            return elements(visibleRowRange) + columnElements + (renameField.map { [$0] } ?? [])
        case .columns, .visibleColumns: return columnElements
        default: return nil
        }
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        onMain { self.older(attribute) } ?? super.accessibilityAttributeValue(attribute)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityArrayAttributeCount(_ attribute: NSAccessibility.Attribute) -> Int {
        let count: Int? = onMain { self.rowIndexes(attribute)?.count ?? self.older(attribute)?.count }
        return count ?? super.accessibilityArrayAttributeCount(attribute)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityArrayAttributeValues(
        _ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int
    ) -> [Any] {
        let part: [Any]? = onMain {
            if let rows = self.rowIndexes(attribute) {
                guard index >= 0, index < rows.count, maxCount > 0 else { return [] }
                return self.elements(rows[index..<min(rows.count, index + maxCount)])
            }
            guard let all = self.older(attribute) else { return nil }
            guard index >= 0, index < all.count, maxCount > 0 else { return [] }
            return Array(all[index..<min(all.count, index + maxCount)])
        }
        return part ?? super.accessibilityArrayAttributeValues(attribute, index: index, maxCount: maxCount)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityIndex(ofChild child: Any) -> Int {
        let asked = Handed(value: child)
        let own: Int? = onMain {
            if let row = asked.value as? ListRowElement { return row.accessibilityIndex() }
            if let column = asked.value as? ListColumnElement {
                return self.numberOfRows + (self.columnElements.firstIndex { $0.isEqual(column) } ?? 0)
            }
            return nil
        }
        return own ?? super.accessibilityIndex(ofChild: child)
    }

    /// Where the keyboard is, for VoiceOver: the row the selection last
    /// moved to, else the list itself.
    override var accessibilityFocusedUIElement: Any? {
        onMain { self.selectedRow >= 0 ? self.element(self.selectedRow) : nil } ?? self
    }

    /// What is under a point of the screen: the row there, else the list.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        let found: ListRowElement? = onMain {
            guard let window = self.window else { return nil }
            let row = self.row(at: self.convert(window.convertPoint(fromScreen: point), from: nil))
            return row >= 0 ? self.element(row) : nil
        }
        return found ?? self
    }
}

/// The older accessibility methods don't say they are called on the main
/// thread (they are): their answers are made there and handed back.
struct Handed<Value>: @unchecked Sendable {
    let value: Value
}

func onMain<Value>(_ body: @MainActor () -> Value) -> Value {
    MainActor.assumeIsolated { Handed(value: body()) }.value
}
