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

/// How the window's width is shared:the sidebar (full, a rail of icons, or
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
