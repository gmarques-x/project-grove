import Foundation

/// Where a row's parts sit in the Name column when folders open in place
/// (spec §16), and which part a point is in: the indent (16 pt a level),
/// the chevron's gutter (a 12 pt box and 4 pt) that every row keeps, the
/// 16 pt icon, then the name. Measured from the column's left edge, which
/// is the pane's; the header's "Name" stays at `ListColumns.edge`.
public enum TreeLayout {
    /// One level further in: the gutter's width, so a child's chevron sits under its parent's icon.
    public static let indent: Double = 16
    /// The chevron's cell, on every row: its box and the gap to the icon.
    public static let gutter: Double = 16
    /// The chevron is centred in this box, at the gutter's start.
    public static let chevronBoxWidth: Double = 12
    /// A row's icon.
    public static let iconWidth: Double = 16

    /// Where a row's gutter starts, at `depth` (0 for the tab folder's own items). Never capped.
    public static func gutterStart(depth: Int) -> Double {
        ListColumns.edge + Double(max(depth, 0)) * indent
    }

    /// Where a row's icon starts; a loading line's "···" too, at its own depth.
    public static func iconStart(depth: Int) -> Double { gutterStart(depth: depth) + gutter }

    /// The chevron's box: its left edge and width.
    public static func chevronBox(depth: Int) -> (x: Double, width: Double) {
        (gutterStart(depth: depth), chevronBoxWidth)
    }

    public enum Part: Equatable, Sendable {
        /// The indent, or the column's edge before it.
        case before
        /// The chevron's whole cell (16 × the row's height).
        case gutter
        case icon
        /// The name and the rest of the row.
        case name
    }

    /// The part of a row at `depth` that `x` (from the column's left edge) is in.
    public static func part(atX x: Double, depth: Int) -> Part {
        let start = gutterStart(depth: depth)
        if x < start { return .before }
        if x < start + gutter { return .gutter }
        if x < start + gutter + iconWidth { return .icon }
        return .name
    }

    public enum Chevron: Equatable, Sendable {
        /// chevron.right.
        case closed
        /// chevron.down.
        case open
    }

    /// The chevron a row's fold shows: none for `.none`; a folder still
    /// being read shows it open (its "···" line is beneath it).
    public static func chevron(for fold: TreeRow.Fold) -> Chevron? {
        switch fold {
        case .none: nil
        case .closed: .closed
        case .open, .loading: .open
        }
    }

    /// Whether a click at `x` on a row at `depth` is on its chevron: in
    /// the gutter of a row that has one. Such a click opens or closes the
    /// folder, and does not select, drag or go into it.
    public static func togglesFold(atX x: Double, depth: Int, fold: TreeRow.Fold) -> Bool {
        chevron(for: fold) != nil && part(atX: x, depth: depth) == .gutter
    }
}

extension Formatting {
    /// What a row's Size column says: its size or its folder's total when
    /// known; "···" for a folder or package whose total is on its way;
    /// "--" for one with none on its way (`awaitsTotal` false: it can't be
    /// read) and for an item that has no size (a link, a volume).
    public static func sizeColumn(_ entry: Entry, total: Int64?, awaitsTotal: Bool) -> String {
        if let bytes = entry.size ?? total { return size(bytes) }
        switch entry.kind {
        case .folder, .package: return awaitsTotal ? "···" : "--"
        case .file, .symlink, .alias, .volume: return "--"
        }
    }
}
