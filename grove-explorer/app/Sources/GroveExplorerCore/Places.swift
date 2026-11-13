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

    /// Where the keyboard's row is after the sidebar's rows changed (a
    /// favourite or a share removed or kept, a disk come or gone): on the
    /// row it was on, found by its id (or by the id it became, `renamed`:
    /// Keep in Sidebar makes a volume's row its share's); when that row
    /// went, on the one now at its place, or the last. Nil with no rows.
    public static func keptCursor(on id: String?, at index: Int, among ids: [String], renamed: [String: String] = [:]) -> Int? {
        guard !ids.isEmpty else { return nil }
        if let id, let found = ids.firstIndex(of: renamed[id] ?? id) { return found }
        return min(max(index, 0), ids.count - 1)
    }
}

/// The sidebar's sections, in its order: Favourites, iCloud, one for each
/// cloud provider in `~/Library/CloudStorage` (by its name), Locations
/// (the disks and the shares, saved or not), and the Trash. There is no
/// section of its own for the saved shares (2026-11-13: they are in
/// Locations, the + on its header).
public enum SidebarSection: Hashable, Sendable {
    case favourites, cloud
    case provider(String)
    case locations
    /// The Trash, at the bottom, without a caption.
    case trash

    /// Its caption, before it is set in capitals.
    public var caption: String {
        switch self {
        case .favourites: "Favourites"
        case .cloud: "iCloud"
        case .provider(let name): name
        case .locations: "Locations"
        case .trash: ""
        }
    }

    /// Its header carries the + of Connect to Server… (⌘K).
    public var connects: Bool { self == .locations }
}

/// What LOCATIONS lists, top to bottom.
public enum Locations {
    public enum Row<Volume, Share> {
        case volume(Volume)
        case share(Share)
    }

    /// The startup disk, the other disks as macOS lists them, the saved
    /// shares in the order they were added, then the network volumes that
    /// aren't saved, as listed. A saved share's mount is its share's row,
    /// not a row of its own.
    public static func rows<Volume, Share>(
        volumes: [Volume], shares: [Share], isStartup: (Volume) -> Bool, isNetwork: (Volume) -> Bool,
        isSavedShare: (Volume) -> Bool
    ) -> [Row<Volume, Share>] {
        let listed = volumes.filter { !isSavedShare($0) }
        let disks = listed.filter { !isNetwork($0) }
        let startup = disks.filter(isStartup), others = disks.filter { !isStartup($0) }
        return (startup + others).map { .volume($0) } + shares.map { .share($0) }
            + listed.filter(isNetwork).map { .volume($0) }
    }
}

extension Locations.Row: Equatable where Volume: Equatable, Share: Equatable {}

/// How the window's width is shared: the sidebar (full, a rail of icons, or
/// hidden), a 1 pt line, then the pane or the two panes with a line between.
/// The full sidebar is as wide as the user chose (dragging the line after
/// it, 160–360 pt; 2026-11-13 sidebar spec, B).
public enum SidebarLayout {
    public enum Mode: Equatable, Sendable {
        case full, rail, hidden

        /// In points; the full sidebar's at the default width (`width(of:chosen:)` has the chosen one).
        public var width: Double {
            switch self {
            case .full: SidebarLayout.defaultWidth
            case .rail: 48
            case .hidden: 0
            }
        }
    }

    /// The full sidebar's width until one is chosen.
    public static let defaultWidth: Double = 200
    /// What a double-click on the line after the sidebar makes it.
    public static let reset = defaultWidth
    /// How narrow and how wide the full sidebar may be made.
    public static let narrowest: Double = 160
    public static let widest: Double = 360

    /// Under this a pane loses its date column: the sidebar gives way first.
    public static let paneFloor = ListColumns.dateThreshold
    /// The narrowest a pane gets by dragging the divider.
    public static let dragFloor: Double = 240
    static let line: Double = 1

    /// A chosen width as a session file may give it, brought into 160–360.
    public static func clamped(width: Double) -> Double {
        width.isFinite ? min(max(width, narrowest), widest) : defaultWidth
    }

    /// How wide the sidebar is in `mode`: the full one as chosen, the rail 48, hidden 0.
    public static func width(of mode: Mode, chosen: Double) -> Double {
        mode == .full ? clamped(width: chosen) : mode.width
    }

    /// The sidebar is a rail whenever the panes beside the full sidebar,
    /// at its chosen width, would be under 430 pt each. The chosen width
    /// is kept meanwhile: it is back when the window widens again.
    public static func mode(windowWidth: Double, panes: Int, hidden: Bool, chosen: Double = defaultWidth) -> Mode {
        if hidden { return .hidden }
        let count = Double(max(1, panes))
        // A line after the sidebar and one between two panes.
        let each = (windowWidth - width(of: .full, chosen: chosen) - count * line) / count
        return each >= paneFloor ? .full : .rail
    }

    /// What the panes share: the window less the sidebar and its line. With
    /// two panes the line between them is part of it.
    public static func panesWidth(windowWidth: Double, mode: Mode, chosen: Double = defaultWidth) -> Double {
        max(0, windowWidth - width(of: mode, chosen: chosen) - (mode == .hidden ? 0 : line))
    }

    /// The width the line after the sidebar, dragged to `x` (from the
    /// window's left edge), gives the sidebar: whole points in 160–360, and
    /// no wider than leaves each pane 430 (it would turn into the rail
    /// under the pointer).
    public static func dragged(to x: Double, windowWidth: Double, panes: Int) -> Double {
        min(max(x.rounded(), narrowest), widestFitting(windowWidth: windowWidth, panes: panes))
    }

    /// A drag that began with the sidebar `start` wide and has moved the
    /// pointer `translation` since: the width moves by as much (where in the
    /// line's catch area it was caught makes no jump), within `dragged(to:)`'s limits.
    public static func dragged(from start: Double, by translation: Double, windowWidth: Double, panes: Int) -> Double {
        dragged(to: start + translation, windowWidth: windowWidth, panes: panes)
    }

    /// The widest the sidebar can be dragged in this window: 360, or less
    /// where that leaves each pane 430; never under 160 (the window shows
    /// the rail then, and nothing is dragged).
    public static func widestFitting(windowWidth: Double, panes: Int) -> Double {
        let count = Double(max(1, panes))
        let room = (windowWidth - count * line - count * paneFloor).rounded(.down)
        return max(narrowest, min(widest, room))
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
