import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The list's measures that aren't columns (those are `ListColumns`).
@MainActor
enum ListMetrics {
    /// A row, the header row and the status bar: 24 pt.
    static let row = GroveSpace.s24
    /// The selection's and the hover's shape stops this far from the pane's edges.
    static let fillInset = GroveSpace.s8
    /// Between the icon and the name.
    static let iconGap = GroveSpace.s8
    /// Clear of the next column at the name's end.
    static let nameTrailing = GroveSpace.s8
    /// Above the first row and below the last.
    static let listPadding = GroveSpace.s4

    static let nameFont = GroveFont.monoNS(GroveType.label)
    static let detailFont = GroveFont.monoNS(GroveType.body)
    /// One character of the name's face (it is monospaced).
    static let nameAdvance = ("0" as NSString).size(withAttributes: [.font: nameFont]).width
}

/// A row's ground: the selection and the pointer's fill, drawn with the
/// list's roles. Selected rows that touch are one shape: a row's corners
/// are round only where its neighbour isn't selected.
final class FileRowView: NSTableRowView {
    var theme = ThemeColors.fallback { didSet { needsDisplay = true } }
    /// Whether this pane has the keys: the other pane's selection is quieter.
    var paneIsActive = true { didSet { if paneIsActive != oldValue { needsDisplay = true } } }
    var isUnderPointer = false { didSet { if isUnderPointer != oldValue { needsDisplay = true } } }
    /// A drag of files is over this folder's row: the hover fill and a 1 pt green line.
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }

    override var isSelected: Bool { didSet { needsDisplay = true } }
    override var isPreviousRowSelected: Bool { didSet { needsDisplay = true } }
    override var isNextRowSelected: Bool { didSet { needsDisplay = true } }
    /// The cells draw their own text: nothing turns white on a selected row.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isUnderPointer || isDropTarget, !isSelected else { return }
        shape(roundTop: true, roundBottom: true) { path in
            NSColor(theme.listHoverFill).setFill()
            path.fill()
            if isDropTarget { outline(path, NSColor(theme.green)) }
        }
    }

    /// A 1 pt line just inside the shape.
    private func outline(_ path: NSBezierPath, _ color: NSColor) {
        color.setStroke()
        path.lineWidth = 2  // Half of it is outside the shape and clipped away.
        path.addClip()
        path.stroke()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        shape(roundTop: !isPreviousRowSelected, roundBottom: !isNextRowSelected) { path in
            NSColor(theme.listSelectionFill(active: paneIsActive)).setFill()
            path.fill()
            // In the light schemes the fills are a step apart at most: the
            // selection of the pane that has the keys takes a 1 pt line (as
            // `lightOutline` gives a panel), which sets it apart from the
            // pointer's row and from the other pane's selection.
            guard theme.isLight, paneIsActive else { return }
            outline(path, NSColor(theme.line))
        }
        // A selected folder a drag is over: the green line round this row alone.
        if isDropTarget {
            shape(roundTop: true, roundBottom: true) { outline($0, NSColor(theme.green)) }
        }
    }

    /// The row's part of a rounded shape: where a neighbour continues it
    /// (`roundTop` or `roundBottom` false) the shape runs on past this row's
    /// edge and is cut there, so its fill and its outline join the neighbour's.
    private func shape(roundTop: Bool, roundBottom: Bool, draw: (NSBezierPath) -> Void) {
        let radius = GroveRadius.control
        var rect = bounds.insetBy(dx: ListMetrics.fillInset, dy: 0)
        // The view is flipped: minY is the top.
        if !roundTop {
            rect.origin.y -= 2 * radius
            rect.size.height += 2 * radius
        }
        if !roundBottom { rect.size.height += 2 * radius }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        draw(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A cell that draws one line of text itself: the list reuses thousands of
/// these, and nothing in them is a control.
class TextCellView: NSView {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            setAccessibilityValue(text)
            needsDisplay = true
        }
    }
    var color = NSColor.labelColor { didSet { needsDisplay = true } }
    var font = ListMetrics.detailFont
    var alignment = NSTextAlignment.left
    /// The gap before the column, inside the cell.
    var leading: CGFloat = 0

    required override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        draw(text, in: NSRect(x: leading, y: 0, width: bounds.width - leading, height: bounds.height))
    }

    /// One line, centred on the row, cut in the middle if it still doesn't fit.
    func draw(_ string: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingMiddle
        let line = NSAttributedString(
            string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        let height = ceil(line.size().height)
        line.draw(in: NSRect(x: rect.minX, y: rect.minY + ((rect.height - height) / 2).rounded(), width: rect.width, height: height))
    }
}

/// The Name column's cell: the icon, then the name, cut in the middle with
/// its extension kept when it is too long.
final class NameCellView: TextCellView {
    var icon: EntryIcon? { didSet { needsDisplay = true } }
    var theme = ThemeColors.fallback
    /// A hidden item: its icon is dimmed.
    var dimmed = false

    override func draw(_ dirtyRect: NSRect) {
        let cell = IconMetrics.cell
        let iconRect = NSRect(x: leading, y: ((bounds.height - cell) / 2).rounded(), width: cell, height: cell)
        icon?.draw(in: iconRect, theme: theme, dimmed: dimmed)

        let start = iconRect.maxX + ListMetrics.iconGap
        let room = bounds.width - start - ListMetrics.nameTrailing
        guard room > 0 else { return }
        let fits = Int(room / ListMetrics.nameAdvance)
        draw(Formatting.middleTruncated(text, to: fits), in: NSRect(x: start, y: 0, width: room, height: bounds.height))
    }
}

/// The table itself: it tells which row the pointer is over and when the
/// pane is clicked (so it becomes the active one).
final class FileTableView: NSTableView {
    /// The list was handed the keyboard.
    var onActivate: (() -> Void)?
    /// The list was clicked.
    var onClick: (() -> Void)?
    /// A key was pressed: true when it was dealt with.
    var onKey: ((NSEvent) -> Bool)?
    var onPointerRow: ((Int) -> Void)?
    /// An item of the system's Edit menu was chosen, or its key pressed:
    /// "copy", "paste", "undo" or "redo", as `CommandList` names them.
    var onEdit: ((String) -> Void)?
    /// Whether that item is offered now.
    var canEdit: ((String) -> Bool)?
    /// The row under the pointer; -1 for none.
    var pointerRow = -1 {
        didSet { if pointerRow != oldValue { onPointerRow?(pointerRow) } }
    }
    /// The folder's row a drag of files is over; -1 for none.
    var dropRow = -1 {
        didSet {
            guard dropRow != oldValue else { return }
            enumerateAvailableRowViews { view, row in (view as? FileRowView)?.isDropTarget = row == dropRow }
        }
    }
    /// A right-click on a row (-1: on the list's empty space): the menu to show.
    var onMenu: ((Int) -> NSMenu?)?
    /// The system's key for a context menu (⌃Return unless the user chose
    /// another), or VoiceOver's "show menu", came to the list.
    var onMenuKey: (() -> Void)?
    /// Fills the Quick Look panel while this list has the keyboard (`QuickLook.swift`).
    weak var quickLook: QuickLookController?
    /// A drag left the list or ended over it.
    var onDragLeft: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDragLeft?()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragLeft?()
    }

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

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenu?(row(at: convert(event.locationInWindow, from: nil)))
    }

    /// From macOS 15 the system has a key for "the menu of what is
    /// selected" and sends this; before, ⌃Return comes as a key (`onKey`).
    @available(macOS 15.0, *)
    override func showContextMenuForSelection(_ sender: Any?) {
        onMenuKey?()
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    /// The keys came here (Tab, a click elsewhere in the pane): after the
    /// turn, since this can come while SwiftUI is updating its views.
    override func becomeFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in self?.onActivate?() }
        return super.becomeFirstResponder()
    }

    // MARK: The system's Edit menu

    // Undo, Redo, Copy and Paste stay the system's menu items (they act on
    // a text field when one has the keyboard); with the list as the first
    // responder they are sent here. Select All is the table's own.

    @objc func copy(_ sender: Any?) { onEdit?("copy") }
    @objc func paste(_ sender: Any?) { onEdit?("paste") }
    @objc func undo(_ sender: Any?) { onEdit?("undo") }
    @objc func redo(_ sender: Any?) { onEdit?("redo") }

    private static let edits: [Selector: String] = [
        #selector(copy(_:)): "copy", #selector(paste(_:)): "paste",
        #selector(undo(_:)): "undo", #selector(redo(_:)): "redo",
    ]

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, let id = Self.edits[action] { return canEdit?(id) ?? false }
        return super.validateUserInterfaceItem(item)
    }
}
