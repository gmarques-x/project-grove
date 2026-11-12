import Foundation

/// The sidebar's places.
public enum Places {
    /// Which of `places` is lit for `folder`: the nearest one above it (the
    /// folder itself or the closest folder that holds it); the first of two
    /// on the same folder; nil when the folder is under none of them.
    public static func nearest(above folder: URL, among places: [URL]) -> Int? {
        let path = folder.standardizedFileURL.pathComponents
        var best: (index: Int, depth: Int)?
        for (index, place) in places.enumerated() {
            let parts = place.standardizedFileURL.pathComponents
            guard parts.count <= path.count, Array(path.prefix(parts.count)) == parts else { continue }
            if best == nil || parts.count > best!.depth { best = (index, parts.count) }
        }
        return best?.index
    }
}

/// How the window's width is shared: the sidebar (full, a rail of icons, or
/// hidden), a 1 pt line, then the pane or the two panes with a line between.
public enum SidebarLayout {
    public enum Mode: Equatable, Sendable {
        case full, rail, hidden

        /// In points.
        public var width: Double {
            switch self {
            case .full: 200
            case .rail: 48
            case .hidden: 0
            }
        }
    }

    /// Under this a pane loses its date column: the sidebar gives way first.
    public static let paneFloor = ListColumns.dateThreshold
    /// The narrowest a pane gets by dragging the divider.
    public static let dragFloor: Double = 240
    static let line: Double = 1

    /// The sidebar is a rail whenever the panes would otherwise be under
    /// 430 pt each.
    public static func mode(windowWidth: Double, panes: Int, hidden: Bool) -> Mode {
        if hidden { return .hidden }
        let count = Double(max(1, panes))
        // A line after the sidebar and one between two panes.
        let each = (windowWidth - Mode.full.width - count * line) / count
        return each >= paneFloor ? .full : .rail
    }

    /// What the panes share: the window less the sidebar and its line. With
    /// two panes the line between them is part of it.
    public static func panesWidth(windowWidth: Double, mode: Mode) -> Double {
        max(0, windowWidth - mode.width - (mode == .hidden ? 0 : line))
    }

    /// The left of two panes: its share of what the line between them leaves, in whole points.
    public static func leftPaneWidth(panesWidth: Double, split: Double) -> Double {
        (max(0, panesWidth - line) * clamped(split: split)).rounded(.down)
    }

    /// The share a divider dragged to `leftWidth` gives the left pane: each
    /// pane keeps `dragFloor`; where there is no room for that, even.
    public static func split(leftWidth: Double, panesWidth: Double) -> Double {
        let room = panesWidth - line
        guard room >= 2 * dragFloor else { return 0.5 }
        return min(max(leftWidth, dragFloor), room - dragFloor) / room
    }

    /// A share as a session file may give it, brought to what a window can show.
    public static func clamped(split: Double) -> Double {
        split.isFinite ? min(max(split, 0.1), 0.9) : 0.5
    }
}
