import Foundation

/// Which columns a pane's list has and how wide each is, from the pane's own
/// width. The header row and the table both lay out from this, so they line up.
public struct ListColumns: Equatable, Sendable {
    /// Under this Kind goes and the date is written short.
    public static let kindThreshold: Double = 640
    /// Under this the date goes too.
    public static let dateThreshold: Double = 430
    /// The widest the Name column gets: beyond it the other columns follow
    /// the name and the rest of the row is empty.
    public static let nameCap: Double = 560
    /// The narrowest: a pane too small for its columns cuts them, not the name to nothing.
    public static let nameFloor: Double = 80

    /// From the pane's edge to the first column, and from the last to the other edge.
    public static let edge: Double = 16
    /// Between two columns.
    public static let gap: Double = 16
    public static let size: Double = 72
    public static let kind: Double = 112
    static let longDate: Double = 140
    static let shortDateWidth: Double = 104

    public let showsDate: Bool
    public let showsKind: Bool
    /// "Today 09:41", "9 Nov 2026" rather than "Today at 09:41".
    public let shortDate: Bool
    /// The Name column: the icon and the name.
    public let name: Double

    public init(paneWidth: Double) {
        showsKind = paneWidth >= Self.kindThreshold
        showsDate = paneWidth >= Self.dateThreshold
        shortDate = !showsKind
        var others = 2 * Self.edge + Self.size
        if showsDate { others += Self.gap + (shortDate ? Self.shortDateWidth : Self.longDate) }
        if showsKind { others += Self.gap + Self.kind }
        name = min(Self.nameCap, max(Self.nameFloor, paneWidth - others))
    }

    /// The Date Modified column, without the gap before it.
    public var date: Double { shortDate ? Self.shortDateWidth : Self.longDate }

    /// From the pane's left edge to the end of the last column's edge: the
    /// pane's width until the name reaches its cap.
    public var used: Double {
        2 * Self.edge + name + Self.size + (showsDate ? Self.gap + date : 0) + (showsKind ? Self.gap + Self.kind : 0)
    }
}
