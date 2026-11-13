import AppKit
import GroveExplorerCore

// The list for VoiceOver. A table's own stand-ins for its rows offer one
// cell per column and take no words from the row's view: with cells that
// are drawings, each row was a sentence followed by things that say
// nothing, and the columns had no names. So the table hands out rows and
// columns of its own here: a row is one thing with its sentence
// (`Spoken.row`), whether it is selected, and its menu; it has no cells.
//
// Folders open in place (spec §16), so the list is an outline, as an
// `NSOutlineView` is to VoiceOver (looked at in a program of its own:
// the list "AXOutline", each row "AXOutlineRow" with its level from 0,
// "AXDisclosing" for an open folder, settable on a folder alone, which is
// how VoiceOver opens and closes it, the row it is inside and the rows
// it has open). A folder's loading line is no row: VoiceOver's rows are
// the table's others, numbered among themselves.
//
// An assistive app holds a row by the object it was given: the token it
// keeps stands for that object and for no other, however equal, and is
// dead once the object is. So the table keeps one element for each item
// it has been asked about, for as long as the item is listed: the same
// file is the same element from one answer to the next and after the
// list is loaded again, and a row held by VoiceOver follows its file when
// rows above it come or go. A row inside a folder that is closed (or
// being read) is kept too, while the folder is a row: opened again, it is
// the same row.

/// One row of the list, as VoiceOver meets it: the item it shows, in its
/// table. An `NSAccessibilityElement`, and it has to be: the token an
/// assistive app gets for one stands for that object, whereas for a plain
/// object answering the same questions it stands for a place among the
/// table's children (tried: after a sort such a token said another
/// file's words, and after its file went it was the "Name" column).
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
        setAccessibilitySubrole(.outlineRow)
        setAccessibilityParent(table)
    }

    /// Where the item is in the list now; nil when it is no longer listed.
    fileprivate var row: Int? {
        onMain { [me] in
            me.value.table.flatMap { table in
                table.onRowOf?(me.value.item).flatMap { $0 < table.numberOfRows ? $0 : nil }
            }
        }
    }

    /// Its place among VoiceOver's rows, which a loading line is not.
    override func accessibilityIndex() -> Int {
        row.flatMap { row in onMain { [me] in me.value.table?.position(ofRow: row) } } ?? NSNotFound
    }

    override func accessibilityChildren() -> [Any]? { [] }

    // MARK: Its place in the tree

    /// The tree's row it is now: its level and its fold.
    private var tree: TreeRow? {
        row.flatMap { row in onMain { [me] in me.value.table?.onRowTree?(row) } }
    }

    /// 0 for the tab folder's own items, 1 inside one of their folders, …
    override func accessibilityDisclosureLevel() -> Int { tree?.depth ?? 0 }

    /// A folder that is open, or opened and being read.
    override func isAccessibilityDisclosed() -> Bool {
        tree.map { $0.fold == .open || $0.fold == .loading } ?? false
    }

    /// VoiceOver opens or closes the folder: as a click on its chevron
    /// (the row's pane gets the keys; closing remembers what was open inside).
    override func setAccessibilityDisclosed(_ disclosed: Bool) {
        // Already so: nothing, not even the click.
        guard let row, folds, disclosed != isAccessibilityDisclosed() else { return }
        onMain { [me] in
            guard let table = me.value.table else { return }
            table.clickedByAccessibility()
            table.onRowFold?(row, disclosed)
        }
    }

    /// Only a row with a chevron opens or closes. The server asks the
    /// newer way, then, told no, the older, whose answer is otherwise yes
    /// (tried: either alone leaves every row settable).
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        selector == #selector(setAccessibilityDisclosed(_:)) ? folds : super.isAccessibilitySelectorAllowed(selector)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityIsAttributeSettable(_ attribute: NSAccessibility.Attribute) -> Bool {
        attribute == .disclosing ? folds : super.accessibilityIsAttributeSettable(attribute)
    }

    /// Whether it is a folder with a chevron.
    private var folds: Bool { tree.map { $0.fold != TreeRow.Fold.none } ?? false }

    /// The rows one level down inside its open folder.
    override func accessibilityDisclosedRows() -> Any? {
        row.map { row in onMain { [me] in me.value.table?.disclosedRows(of: row) ?? [] } }
    }

    /// The row of the folder it is inside; nil at the top.
    override func accessibilityDisclosedByRow() -> Any? {
        row.flatMap { row in onMain { [me] in me.value.table?.disclosingRow(of: row) } }
    }

    /// "notes.md, Markdown, 4 KB, Today at 09:41": asked for when
    /// VoiceOver comes to the row, not while the list is drawn.
    override func accessibilityLabel() -> String? {
        row.flatMap { row in onMain { [me] in me.value.table?.onRowLabel?(row) } }
    }

    override func isAccessibilitySelected() -> Bool {
        row.map { row in onMain { [me] in me.value.table?.isRowSelected(row) ?? false } } ?? false
    }

    /// Selecting by VoiceOver is a click as far as the panes go: the
    /// row's pane gets the keys, and its list the keyboard.
    override func setAccessibilitySelected(_ selected: Bool) {
        guard let row else { return }
        onMain { [me] in
            guard let table = me.value.table else { return }
            table.clickedByAccessibility()
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
    /// The element of the item on `row`: the one kept for it, made the
    /// first time it is asked for.
    private func element(_ row: Int) -> ListRowElement? {
        guard let item = onRowURL?(row) else { return nil }
        if let kept = spoken.rows[item] { return kept }
        let element = ListRowElement(item: item, in: self)
        spoken.rows[item] = element
        return element
    }

    private func elements<Rows: Sequence>(_ rows: Rows) -> [ListRowElement] where Rows.Element == Int {
        rows.compactMap { $0 >= 0 && $0 < numberOfRows ? element($0) : nil }
    }

    /// The rows changed: the elements of items no longer listed are let
    /// go of (a token held for one then says the element is gone, as for
    /// anything that went), unless the nearest folder above it that is a
    /// row is closed or being read: opened again, the item is the same row.
    /// One under an open folder went for good. What VoiceOver never asked
    /// about costs nothing.
    func rowsReloadedForAccessibility() {
        spoken.listed = nil
        guard !spoken.rows.isEmpty else { return }
        var folds: [String: TreeRow.Fold] = [:]
        for row in 0..<numberOfRows {
            if let shown = onRowTree?(row), shown.entry.kind == .folder { folds[shown.entry.url.pathKey] = shown.fold }
        }
        func isUnderAClosedFolder(_ item: URL) -> Bool {
            var path = item.pathKey
            while path.count > 1 {
                path = (path as NSString).deletingLastPathComponent
                if let fold = folds[path] { return fold == .closed || fold == .loading }
            }
            return false
        }
        spoken.rows = spoken.rows.filter { item, _ in onRowOf?(item) != nil || isUnderAClosedFolder(item) }
    }

    /// The table's rows that are VoiceOver's (all but loading lines), in
    /// order: found once after each reload, when first asked.
    private var listedRows: [Int] {
        if let known = spoken.listed { return known }
        let rows = (0..<numberOfRows).filter { onRowURL?($0) != nil }
        spoken.listed = rows
        return rows
    }

    /// Where VoiceOver's rows from table row `row` on begin, among them.
    private func firstListed(from row: Int) -> Int {
        let rows = listedRows
        var low = 0, high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if rows[middle] < row { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The place of table row `row` among VoiceOver's rows; nil for a loading line.
    fileprivate func position(ofRow row: Int) -> Int? {
        let place = firstListed(from: row)
        return place < listedRows.count && listedRows[place] == row ? place : nil
    }

    /// The rows one level down inside the folder on `row`, while it is open.
    fileprivate func disclosedRows(of row: Int) -> [ListRowElement] {
        guard let folder = onRowTree?(row), folder.fold == .open else { return [] }
        var found: [ListRowElement] = []
        for below in (row + 1)..<max(row + 1, numberOfRows) {
            // A loading line beneath a folder further in is passed over.
            guard let shown = onRowTree?(below) else { continue }
            if shown.depth <= folder.depth { break }
            if shown.depth == folder.depth + 1, let element = element(below) { found.append(element) }
        }
        return found
    }

    /// The row of the folder the row `row` is inside; nil at the top.
    fileprivate func disclosingRow(of row: Int) -> ListRowElement? {
        guard let shown = onRowTree?(row), shown.depth > 0 else { return nil }
        for above in stride(from: row - 1, through: 0, by: -1) {
            if let folder = onRowTree?(above), folder.depth == shown.depth - 1 { return element(above) }
        }
        return nil
    }

    /// The columns the pane has room for, each the one element kept for it.
    private var columnElements: [ListColumnElement] {
        tableColumns.filter { !$0.isHidden }.map { column in
            if let kept = spoken.columns[ObjectIdentifier(column)] { return kept }
            let element = ListColumnElement(column, in: self)
            spoken.columns[ObjectIdentifier(column)] = element
            return element
        }
    }

    /// VoiceOver's rows in view, as table rows.
    private var visibleListedRows: ArraySlice<Int> {
        let range = rows(in: visibleRect)
        return listedRows[firstListed(from: range.location)..<firstListed(from: range.location + range.length)]
    }

    /// What is beside the rows among the table's children.
    private var otherChildren: [Any] { columnElements + (renameField.map { [$0] } ?? []) }

    /// A click as far as the panes go, from VoiceOver: the pane gets the
    /// keys and this list the keyboard, as `mouseDown` does it.
    func clickedByAccessibility() {
        onClick?()
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    /// An outline, as an `NSOutlineView` is: its folders open in place.
    override func accessibilityRole() -> NSAccessibility.Role? { .outline }

    override func accessibilityChildren() -> [Any]? { elements(listedRows) + otherChildren }
    /// As AppKit's typed methods want rows (see `ListRowElement.isARow`).
    private func typed(_ rows: [ListRowElement]) -> [any NSAccessibilityRow] {
        rows.compactMap { ($0 as AnyObject) as? any NSAccessibilityRow }
    }

    override func accessibilityRows() -> [any NSAccessibilityRow]? { typed(elements(listedRows)) }
    override func accessibilityVisibleRows() -> [any NSAccessibilityRow]? { typed(elements(visibleListedRows)) }
    override func accessibilitySelectedRows() -> [any NSAccessibilityRow]? { typed(elements(selectedRowIndexes)) }

    override func setAccessibilitySelectedRows(_ rows: [any NSAccessibilityRow]?) {
        // As it came, unlooked at: what is in it is whatever the tokens
        // an assistive app sent stand for now.
        select(asked: rows.map { $0 as NSArray } ?? [])
    }

    /// Selects the rows among `asked` that are rows of this list now;
    /// anything else in it (a row whose file went, something that is no
    /// row) is passed over.
    private func select(asked: NSArray) {
        let rows = asked.compactMap { ($0 as? ListRowElement)?.row }
        clickedByAccessibility()
        selectRowIndexes(IndexSet(rows.filter { $0 >= 0 && $0 < numberOfRows }), byExtendingSelection: false)
    }

    override func accessibilityColumns() -> [Any]? { columnElements }
    override func accessibilityVisibleColumns() -> [Any]? { columnElements }

    // The same answers to the older way of asking, which the table has
    // answers of its own to (its stand-ins) and assistive apps are served
    // by: by attribute, and for a count or a part of a long list, which
    // make no more elements than they give.

    /// The rows an attribute is about, as table rows, and whether other
    /// children follow them; nil for an attribute that is not a list of rows.
    private func rowIndexes(_ attribute: NSAccessibility.Attribute) -> (rows: [Int], others: Bool)? {
        switch attribute {
        case .rows: (listedRows, false)
        case .children: (listedRows, true)
        case .visibleRows: (Array(visibleListedRows), false)
        case .visibleChildren: (Array(visibleListedRows), true)
        case .selectedRows: (Array(selectedRowIndexes), false)
        default: nil
        }
    }

    /// `count` values of the attribute from `start` (all of them when
    /// `count` is nil); nil for an attribute the table answers itself.
    private func older(_ attribute: NSAccessibility.Attribute, from start: Int = 0, count: Int? = nil) -> [Any]? {
        func part<Value>(of all: [Value], from start: Int) -> ArraySlice<Value> {
            guard start >= 0, start < all.count, count ?? 1 > 0 else { return [] }
            return all[start..<min(all.count, start + (count ?? all.count))]
        }
        if let (rows, others) = rowIndexes(attribute) {
            let wanted = elements(part(of: rows, from: start))
            guard others else { return wanted }
            let left = count.map { $0 - wanted.count }
            guard left ?? 1 > 0 else { return wanted }
            let rest = otherChildren
            let from = max(start - rows.count, 0)
            return wanted + (from < rest.count ? Array(rest[from..<min(rest.count, from + (left ?? rest.count))]) : [])
        }
        switch attribute {
        case .columns, .visibleColumns: return Array(part(of: columnElements, from: start))
        default: return nil
        }
    }

    private func olderCount(_ attribute: NSAccessibility.Attribute) -> Int? {
        if let (rows, others) = rowIndexes(attribute) { return rows.count + (others ? otherChildren.count : 0) }
        return older(attribute)?.count
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        onMain { self.older(attribute) } ?? super.accessibilityAttributeValue(attribute)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityArrayAttributeCount(_ attribute: NSAccessibility.Attribute) -> Int {
        onMain { self.olderCount(attribute) } ?? super.accessibilityArrayAttributeCount(attribute)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityArrayAttributeValues(
        _ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int
    ) -> [Any] {
        onMain { self.older(attribute, from: index, count: maxCount) }
            ?? super.accessibilityArrayAttributeValues(attribute, index: index, maxCount: maxCount)
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityIndex(ofChild child: Any) -> Int {
        let asked = Handed(value: child)
        let own: Int? = onMain {
            if let row = asked.value as? ListRowElement { return row.accessibilityIndex() }
            if let column = asked.value as? ListColumnElement {
                return self.listedRows.count + (self.columnElements.firstIndex { $0 === column } ?? 0)
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

/// What the table has handed VoiceOver (`FileTableView.spoken`): one
/// element per item and one per column, kept; and which of its rows are
/// VoiceOver's rows, found again after each reload.
struct SpokenElements {
    var rows: [URL: ListRowElement] = [:]
    var columns: [ObjectIdentifier: ListColumnElement] = [:]
    var listed: [Int]?
}

/// The older accessibility methods don't say they are called on the main
/// thread (they are): their answers are made there and handed back.
struct Handed<Value>: @unchecked Sendable {
    let value: Value
}

func onMain<Value>(_ body: @MainActor () -> Value) -> Value {
    MainActor.assumeIsolated { Handed(value: body()) }.value
}
