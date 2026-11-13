import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// What the list draws of the tree (spec §16) beside a row's icon and
/// name: the chevron, and a folder's "···" loading line. Where each sits
/// is `TreeLayout`'s.
@MainActor
enum TreeCell {
    /// A folder whose contents are being read: one quiet line beneath it.
    static let loadingText = "···"

    /// The chevron of a row at `depth`: `GroveIcon`'s chevron.right (closed)
    /// or chevron.down (open), set as `GroveIcon` sets a symbol beside the
    /// name (the name's size, medium weight), in the quiet colour, in the
    /// text colour while `lit`. Centred in its 12 pt box by the box, not by
    /// the glyph's bounds (chevron.down is a point wider), and on the row.
    static func draw(_ chevron: TreeLayout.Chevron, depth: Int, lit: Bool, theme: ThemeColors, rowHeight: CGFloat) {
        let color = lit ? NSColor(theme.fg) : NSColor(theme.quiet)
        guard let image = image(chevron, color: color) else { return }
        let box = TreeLayout.chevronBox(depth: depth)
        let size = image.size
        let rect = NSRect(
            x: CGFloat(box.x) + (CGFloat(box.width) - size.width) / 2, y: (rowHeight - size.height) / 2,
            width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The symbol in `color`, made once per colour.
    private static func image(_ chevron: TreeLayout.Chevron, color: NSColor) -> NSImage? {
        let name: GroveIcon.Name = chevron == .open ? .menu : .forward
        let key = "\(name.symbol) \(color.description)"
        if let known = images[key] { return known }
        let configuration = NSImage.SymbolConfiguration(pointSize: GroveType.label, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        images[key] = image
        return image
    }

    private static var images: [String: NSImage] = [:]
}

/// The tree's part of a press and of the pointer in the list: a chevron's
/// gutter opens or closes its folder, and a loading line takes nothing.
extension FileList.Coordinator {
    func setUpTree(_ table: FileTableView) {
        table.onPress = { [weak self] in self?.pressed($0, row: $1, at: $2) ?? false }
        table.isOnChevron = { [weak self] in self?.isOnChevron(row: $0, at: $1) ?? false }
        table.onChevronRow = { [weak self] in self?.chevronRowChanged(from: $0, to: $1) }
    }

    /// `x` from the Name column's left edge (the pane's).
    private func columnX(_ point: NSPoint) -> Double {
        guard let table, table.numberOfColumns > 0 else { return point.x }
        return point.x - table.rect(ofColumn: 0).minX
    }

    /// Whether `point` of `row` is on a chevron's gutter.
    func isOnChevron(row: Int, at point: NSPoint) -> Bool {
        guard let shown = treeRow(onRow: row) else { return false }
        return TreeLayout.togglesFold(atX: columnX(point), depth: shown.depth, fold: shown.fold)
    }

    /// A press in the list. On a chevron's gutter it opens or closes the
    /// folder (⌥: everything inside too) and does not select, drag or go
    /// into it, a double-click's second press included. A loading line
    /// takes no press. Anything else is the table's.
    func pressed(_ event: NSEvent, row: Int, at point: NSPoint) -> Bool {
        guard items.indices.contains(row) else { return false }
        guard let shown = treeRow(onRow: row) else { return true }
        guard TreeLayout.togglesFold(atX: columnX(point), depth: shown.depth, fold: shown.fold) else { return false }
        // Rows of another moment (the model changed, this list not yet): no fold is taken from them.
        guard showsModelRows else { return true }
        let url = shown.entry.url
        if event.modifierFlags.contains(.option) {
            if shown.fold == .closed { model.openAll(url, in: side) } else { model.closeAll(url, in: side) }
        } else {
            model.toggleFold(url, in: side)
        }
        return true
    }

    /// The pointer went into a chevron's gutter, or out: that chevron is lit.
    private func chevronRowChanged(from old: Int, to new: Int) {
        guard let table else { return }
        for (row, lit) in [(old, false), (new, true)] where row >= 0 && row < table.numberOfRows {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NameCellView)?.chevronLit = lit
        }
    }
}
