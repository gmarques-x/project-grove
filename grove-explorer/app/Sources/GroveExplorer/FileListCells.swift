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

    override var isSelected: Bool { didSet { needsDisplay = true } }
    override var isPreviousRowSelected: Bool { didSet { needsDisplay = true } }
    override var isNextRowSelected: Bool { didSet { needsDisplay = true } }
    /// The cells draw their own text: nothing turns white on a selected row.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isUnderPointer, !isSelected else { return }
        shape(roundTop: true, roundBottom: true) { path in
            NSColor(theme.listHoverFill).setFill()
            path.fill()
        }
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
            NSColor(theme.line).setStroke()
            path.lineWidth = 2  // Half of it is outside the shape and clipped away.
            path.addClip()
            path.stroke()
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
