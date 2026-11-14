import CoreGraphics
import Foundation

// A menu drawn by Grove (`GroveMenuList`: the pine's Grove menu, and every
// in-window menu): a list of rows in a panel, a submenu as a second panel
// beside it. What is pure about it is here: which row the keys move to,
// when a submenu opens under the pointer, where each row is and where a
// submenu's panel goes. The rows, the model and the views are GroveUI's
// (`GroveMenuList.swift`).

/// What a row is, as the list draws it (`GroveMenuListRow.Kind` without
/// its rows).
public enum MenuListRowKind: Equatable, Sendable {
    /// Choosing it does something.
    case action
    /// The same, for a row that opens something that is not one of these
    /// panels (the native Global Menu): → opens it too, but it has no arrow.
    case link
    /// It opens its rows in a panel beside this one.
    case submenu
    /// Text that can't be chosen (an error, a warning's line).
    case note

    /// Only a row that opens a panel beside this one is drawn with the
    /// submenu's arrow.
    public var showsChevron: Bool { self == .submenu }
}

/// Which row the highlight moves to. `selectable[i]` is false for a row that
/// can't be chosen (a note, a disabled row); separators are not rows.
public enum MenuListMove {
    /// The next row that can be chosen, `step` rows on (1 down, -1 up),
    /// wrapping at the ends. From no row: the first going down, the last
    /// going up. Nil when no row can be chosen.
    public static func step(from current: Int?, by step: Int, selectable: [Bool]) -> Int? {
        let count = selectable.count
        guard count > 0, step != 0, selectable.contains(true) else { return nil }
        let direction = step > 0 ? 1 : -1
        var index = current.map { min(max($0, 0), count - 1) } ?? (direction > 0 ? -1 : count)
        for _ in 0..<count {
            index = ((index + direction) % count + count) % count
            if selectable[index] { return index }
        }
        return nil
    }

    /// The first row that can be chosen.
    public static func first(selectable: [Bool]) -> Int? { selectable.firstIndex(of: true) }

    /// The last row that can be chosen.
    public static func last(selectable: [Bool]) -> Int? { selectable.lastIndex(of: true) }

    /// Type-to-jump: the next row after `current` whose title starts with
    /// `letter` (whatever the case and the accents), wrapping, so typing the
    /// letter again goes on to the next such row and comes back round. Nil
    /// when no row that can be chosen starts with it.
    public static func jump(to letter: String, from current: Int?, titles: [String], selectable: [Bool]) -> Int? {
        let count = min(titles.count, selectable.count)
        let wanted = fold(letter)
        guard count > 0, !wanted.isEmpty else { return nil }
        let start = current.map { min(max($0, 0), count - 1) } ?? -1
        for offset in 1...count {
            let index = (start + offset) % count
            if selectable[index], fold(titles[index]).hasPrefix(wanted) { return index }
        }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// When one level's submenu opens and closes under the pointer: after a
/// short rest on a row that has one, and not while the pointer is only
/// crossing other rows on its way into the open submenu ("menu aim"). A
/// click or a key opens and closes at once (`set`).
///
/// The model tells it where the pointer is, asks `due` when to come back,
/// and calls `fire` then.
public struct MenuHoverIntent: Equatable, Sendable {
    /// How long the pointer rests on a row before its submenu opens.
    public static let openDelay: TimeInterval = 0.15
    /// How long the open submenu stays while the pointer moves toward it
    /// over other rows.
    public static let grace: TimeInterval = 0.3

    public enum Change: Equatable, Sendable {
        /// Open this row's submenu (closing any other).
        case open(Int)
        /// Close the open submenu.
        case close
    }

    /// The row whose submenu is open.
    public private(set) var open: Int?
    /// What will happen at `due` unless the pointer moves on: that row's
    /// submenu opens, or (nil) the open one closes.
    private var pending: Pending?

    private struct Pending: Equatable, Sendable {
        var row: Int?
        var due: TimeInterval
    }

    public init() {}

    /// When `fire` has something to do; nil when nothing is waiting.
    public var due: TimeInterval? { pending?.due }

    /// The pointer moved over `row` of this level. `opens`: the row has a
    /// submenu. `towardSubmenu`: the move was in the direction of the open
    /// submenu's panel, so the rows crossed on the way get the grace period
    /// rather than the opening delay.
    public mutating func pointer(over row: Int, opens: Bool, towardSubmenu: Bool = false, now: TimeInterval) {
        if opens, row == open {
            pending = nil
            return
        }
        let target: Int? = opens ? row : nil
        // A plain row with nothing open: nothing to wait for.
        guard target != nil || open != nil else {
            pending = nil
            return
        }
        let aiming = towardSubmenu && open != nil
        let due = now + (aiming ? Self.grace : Self.openDelay)
        if let pending, pending.row == target, !aiming {
            // Still on its way to the same thing: the first deadline stands.
            self.pending = Pending(row: target, due: min(pending.due, due))
        } else {
            pending = Pending(row: target, due: due)
        }
    }

    /// The pointer is in the open submenu's panel: it stays.
    public mutating func pointerInSubmenu() { pending = nil }

    /// The pointer left this level's panel, or is between its rows: nothing
    /// new opens, and what is open stays (as a native menu).
    public mutating func pointerAway() { pending = nil }

    /// What is due at `now`: nil when nothing is, or not yet.
    public mutating func fire(now: TimeInterval) -> Change? {
        guard let pending, pending.due <= now else { return nil }
        self.pending = nil
        guard pending.row != open else { return nil }
        open = pending.row
        return pending.row.map(Change.open) ?? .close
    }

    /// A click, → or Return opened `row`'s submenu; ← or Escape closed it
    /// (nil). At once, and whatever was waiting is dropped.
    public mutating func set(open row: Int?) {
        open = row
        pending = nil
    }
}

/// Where a menu panel's rows are, in the panel's own coordinates (points,
/// the origin at its top-left corner, y down). Rows have fixed heights, so
/// the pointer's row and a submenu's place are known without asking the
/// drawn views.
public struct MenuListLayout: Equatable, Sendable {
    /// The measures, given by GroveUI from its spacing scale.
    public struct Metrics: Equatable, Sendable {
        /// From the panel's edge to the first row's fill, above and below.
        public var edge: Double
        /// From the panel's side to a row's fill.
        public var side: Double
        /// What a separator adds above its row: the line and its room.
        public var rule: Double

        public init(edge: Double, side: Double, rule: Double) {
            self.edge = edge
            self.side = side
            self.rule = rule
        }
    }

    public var width: Double
    public var metrics: Metrics
    /// Each row's rectangle (its hover fill).
    public private(set) var rows: [CGRect]
    /// The panel's height.
    public private(set) var height: Double

    /// - `heights`: each row's height.
    /// - `separators`: whether each row has a line above it; the first
    ///   row's is not drawn.
    public init(width: Double, heights: [Double], separators: [Bool], metrics: Metrics) {
        self.width = width
        self.metrics = metrics
        var y = metrics.edge
        var rows: [CGRect] = []
        for (index, height) in heights.enumerated() {
            if index > 0, index < separators.count, separators[index] { y += metrics.rule }
            rows.append(CGRect(x: metrics.side, y: y, width: max(0, width - 2 * metrics.side), height: height))
            y += height
        }
        self.rows = rows
        height = y + metrics.edge
    }

    public var size: CGSize { CGSize(width: width, height: height) }

    /// Whether the row at `index` has its line drawn above it.
    public static func showsRule(_ index: Int, separators: [Bool]) -> Bool {
        index > 0 && index < separators.count && separators[index]
    }

    /// The row under `point`; nil on a line, in the panel's padding or
    /// outside it. The whole width counts, not only the fill.
    public func row(at point: CGPoint) -> Int? {
        guard point.x >= 0, point.x <= width else { return nil }
        return rows.firstIndex { point.y >= $0.minY && point.y < $0.maxY }
    }
}

/// A menu opened by a press (a right-click, a pill's click) that is held:
/// releasing the button over a row chooses it, as in a native menu, but
/// the release of a plain click doesn't, so a quick click leaves the menu
/// open. Only the release of the press that opened the menu is asked about.
public enum MenuPress {
    /// How long the button must be held before its release chooses.
    public static let hold: TimeInterval = 0.3
    /// How far the pointer must have moved from the press (points, either
    /// way): a release where it was pressed is a click, however slow.
    public static let slop: Double = 4

    /// Whether the release at `up` (at `upTime`) of the press at `down`
    /// (at `downTime`) chooses the row under it. Times in seconds.
    public static func releaseChooses(pressedAt downTime: TimeInterval, at down: CGPoint,
                                      releasedAt upTime: TimeInterval, at up: CGPoint) -> Bool {
        upTime - downTime >= hold && max(abs(up.x - down.x), abs(up.y - down.y)) >= slop
    }
}

/// Where a menu's panels go.
public enum MenuPlacement {
    /// The frame of a menu popped up at `origin` (`GroveMenuList.popUp`), in
    /// the coordinates `screen` is in (y down), on whole points.
    ///
    /// Its top-left corner is at `origin`. Without room at the right it goes
    /// to the point's left (its right edge at the point); without room below,
    /// above the point (its bottom edge at the point), as a native menu.
    /// Where flipping doesn't fit either it is pushed back onto the screen:
    /// against its right or bottom edge, and never past its left or top. A
    /// point off the visible frame (in the menu bar, past an edge) is
    /// brought onto it the same way.
    ///
    /// - `size`: the menu panel's.
    /// - `screen`: what the menu may cover (the screen's visible frame).
    public static func menu(origin: CGPoint, size: CGSize, screen: CGRect) -> CGRect {
        let point = CGPoint(x: origin.x.rounded(.down), y: origin.y.rounded(.down))
        func place(_ start: Double, _ length: Double, _ low: Double, _ high: Double) -> Double {
            var value = start
            if start + length > high {
                let flipped = start - length
                value = flipped >= low ? flipped : high - length
            }
            // Inside [low, high - length]; the low edge wins when it doesn't fit.
            return max(low, min(value, high - length))
        }
        return CGRect(x: place(point.x, size.width, screen.minX, screen.maxX),
                      y: place(point.y, size.height, screen.minY, screen.maxY),
                      width: size.width, height: size.height)
    }

    /// The frame of a submenu's panel, in the coordinates `parent` is in
    /// (y down).
    ///
    /// Its left edge shares the parent's right outline (the two 1 pt lines
    /// are one: the frames overlap by `line`), and its first row is level
    /// with the row that opened it. Without room at the right it goes to
    /// the parent's left the same way; then it is kept inside `bounds`
    /// (moved up from the bottom, never above the top).
    ///
    /// - `parent`: the parent panel's frame (its outline's outer edge).
    /// - `row`: the opening row's rectangle, in the parent panel's own
    ///   coordinates (`MenuListLayout.rows`).
    /// - `size`: the submenu panel's.
    /// - `firstRow`: from the submenu panel's top to its first row
    ///   (`Metrics.edge`).
    /// - `bounds`: what the panels may cover: between the window borders'
    ///   lines, below the bar, above the screen's bottom gap.
    public static func submenu(parent: CGRect, row: CGRect, size: CGSize, firstRow: Double, bounds: CGRect,
                               line: Double = 1) -> CGRect {
        var x = parent.maxX - line
        if x + size.width > bounds.maxX {
            let left = parent.minX - size.width + line
            x = left >= bounds.minX ? left : max(bounds.minX, bounds.maxX - size.width)
        }
        var y = parent.minY + row.minY - firstRow
        y = max(bounds.minY, min(y, bounds.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// `frame` grown to whole points (a window sits on whole points), and
    /// where the panel is drawn inside it: as Grove Keys' `BarPanelPlacement.window`.
    public static func window(for frame: CGRect) -> (frame: CGRect, inset: CGPoint) {
        let whole = CGRect(x: frame.minX.rounded(.down), y: frame.minY.rounded(.down),
                           width: frame.maxX.rounded(.up) - frame.minX.rounded(.down),
                           height: frame.maxY.rounded(.up) - frame.minY.rounded(.down))
        return (whole, CGPoint(x: frame.minX - whole.minX, y: frame.minY - whole.minY))
    }
}
