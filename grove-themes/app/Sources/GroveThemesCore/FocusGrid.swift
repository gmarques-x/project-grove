/// Where the keyboard focus box can go, and how arrows and Ctrl+h/j/k/l move
/// it. The tiles (dropdown) and cards (gallery) are 2 rows × 3: Dark on top,
/// Light below, Hard / Medium / Soft left to right. Both continue below with
/// the "Terminal logo" row (Project Grove under the left two columns, Avatar
/// under the right one) and the "Wallpaper" row (the same two columns, one
/// remembered column for both); the dropdown then has "Open Grove Themes…"
/// and "Quit", one column. Moves off an edge stay put (no wrap).
public struct FocusGrid: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        case scheme(String)
        case logo(String)
        case wallpaper(String)
        case openWindow
        case quit
    }

    public enum Direction: Equatable, Sendable { case left, right, up, down }

    public enum Layout: Equatable, Sendable {
        /// Tiles, then the two menu rows.
        case dropdown
        /// Cards only.
        case gallery
    }

    static let rows = ["dark", "light"]
    static let columns = ["hard", "medium", "soft"]
    static let logos = SchemeList.defaultLogos

    public let layout: Layout
    public private(set) var focused: Item
    /// The tile column last focused, for coming back up from the logo row.
    private var column = 1
    /// The logo last focused, for coming back up from the menu rows.
    private var logo = 0

    /// Starts on `current`'s tile, or the middle of the top row for a name
    /// that isn't one of the six.
    public init(layout: Layout, current: String) {
        self.layout = layout
        if let (_, column) = Self.position(of: current) {
            focused = .scheme(current)
            self.column = column
        } else {
            focused = .scheme(Self.scheme(row: 0, column: 1))
        }
    }

    public mutating func move(_ direction: Direction) {
        switch focused {
        case .scheme(let name):
            guard let (row, column) = Self.position(of: name) else { return }
            var (newRow, newColumn) = (row, column)
            switch direction {
            case .left: newColumn = max(column - 1, 0)
            case .right: newColumn = min(column + 1, Self.columns.count - 1)
            case .up: newRow = max(row - 1, 0)
            case .down:
                if row == Self.rows.count - 1 {
                    self.column = column
                    logo = column == Self.columns.count - 1 ? 1 : 0
                    focused = .logo(Self.logos[logo])
                    return
                }
                newRow = row + 1
            }
            self.column = newColumn
            focused = .scheme(Self.scheme(row: newRow, column: newColumn))
        case .logo:
            switch direction {
            case .left: logo = 0
            case .right: logo = Self.logos.count - 1
            case .up:
                focused = .scheme(Self.scheme(row: Self.rows.count - 1, column: column))
                return
            case .down:
                focused = .wallpaper(Self.logos[logo])
                return
            }
            focused = .logo(Self.logos[logo])
        case .wallpaper:
            switch direction {
            case .left: logo = 0
            case .right: logo = Self.logos.count - 1
            case .up:
                focused = .logo(Self.logos[logo])
                return
            case .down:
                if layout == .dropdown { focused = .openWindow }
                return
            }
            focused = .wallpaper(Self.logos[logo])
        case .openWindow:
            switch direction {
            case .up: focused = .wallpaper(Self.logos[logo])
            case .down: focused = .quit
            case .left, .right: break
            }
        case .quit:
            if direction == .up { focused = .openWindow }
        }
    }

    static func scheme(row: Int, column: Int) -> String { "\(rows[row])-\(columns[column])" }

    static func position(of scheme: String) -> (row: Int, column: Int)? {
        for row in rows.indices {
            for column in columns.indices where Self.scheme(row: row, column: column) == scheme {
                return (row, column)
            }
        }
        return nil
    }
}

/// A key the focus box listens to, as the views hand it over.
public enum FocusKey: Equatable, Sendable {
    case up, down, left, right, returnKey, space, escape
    case character(Character)

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public enum Command: Equatable, Sendable {
        case move(FocusGrid.Direction)
        case activate
        case escape
    }

    /// Arrows, Return, Space and Esc with no modifiers; h/j/k/l with Control
    /// only (also as the control characters ⌃H ⌃J ⌃K ⌃L type). Else nil: the
    /// key isn't ours.
    public func command(_ modifiers: Modifiers) -> Command? {
        if case .character(let character) = self {
            guard modifiers == .control else { return nil }
            switch character {
            case "h", "H", "\u{08}": return .move(.left)
            case "j", "J", "\n": return .move(.down)
            case "k", "K", "\u{0B}": return .move(.up)
            case "l", "L", "\u{0C}": return .move(.right)
            default: return nil
            }
        }
        guard modifiers.isEmpty else { return nil }
        switch self {
        case .up: return .move(.up)
        case .down: return .move(.down)
        case .left: return .move(.left)
        case .right: return .move(.right)
        case .returnKey, .space: return .activate
        case .escape: return .escape
        case .character: return nil
        }
    }
}

/// The focus box in one view: hidden (nil) until the first move, then on a
/// `FocusGrid` that starts on the current scheme.
public struct KeyboardFocus: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Taken care of (maybe by doing nothing).
        case handled
        /// Run this item, as a click on it would.
        case activate(FocusGrid.Item)
        /// Close the dropdown.
        case close
    }

    public let layout: FocusGrid.Layout
    public private(set) var grid: FocusGrid?

    public init(layout: FocusGrid.Layout) {
        self.layout = layout
    }

    /// Where the box is drawn; nil while it's hidden.
    public var focused: FocusGrid.Item? { grid?.focused }

    /// `schemesDisabled`: tiles, cards and logos take no clicks (a switch is
    /// running, or the CLI is in trouble), so they take no Return/Space either.
    public mutating func handle(_ command: FocusKey.Command, current: String,
                                schemesDisabled: Bool) -> Outcome {
        switch command {
        case .move(let direction):
            if grid == nil {
                grid = FocusGrid(layout: layout, current: current)
            } else {
                grid?.move(direction)
            }
            return .handled
        case .activate:
            guard let item = grid?.focused else { return .handled }
            switch item {
            case .scheme, .logo, .wallpaper: if schemesDisabled { return .handled }
            case .openWindow, .quit: break
            }
            return .activate(item)
        case .escape:
            if grid != nil {
                grid = nil
                return .handled
            }
            return layout == .dropdown ? .close : .handled
        }
    }

    /// Hides the box; the next move starts again on the current scheme.
    public mutating func hide() {
        grid = nil
    }
}
