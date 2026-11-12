import CoreGraphics
import Foundation

// Where a bar panel goes: "border over border" (spec
// 2026-11-12-bar-panels-design §5). Everything here is in the window list's
// coordinates: points, global, y down from the top of the main display.

/// The outer edges of the window borders (JankyBorders) around the tiled
/// windows under the bar: the lines a panel's own outline lies on.
public struct BorderLines: Equatable, Sendable {
    /// The top border's outer edge (y).
    public var top: Double
    /// The leftmost border's outer edge (x).
    public var left: Double
    /// The rightmost border's outer edge (x).
    public var right: Double

    public init(top: Double, left: Double, right: Double) {
        self.top = top
        self.left = left
        self.right = right
    }
}

/// The window borders as measured on 2026-11-12 (captures at 2x of both top
/// corners, and the window list), and how their lines are found again.
public enum WindowBorders {
    /// `width=` in bordersrc as Grove ships it.
    public static let defaultWidth = 5.0
    /// JankyBorders makes each border's own window this much larger than the
    /// border on every side.
    public static let windowPadding = 8.0
    /// A tiled window's corner radius on macOS 27 (measured: the border's
    /// outer arc is 18.5 with a width of 5).
    public static let windowCornerRadius = 16.0
    /// The Grove bar's strip.
    public static let stripHeight = 48.0

    // The fallback's numbers: AeroSpace's gaps in aerospace.base.toml (a
    // test holds them to the file).
    /// `gaps.outer.left` and `.right`.
    public static let sideGap = 8.0
    /// `gaps.outer.top` where the menu bar reserves nothing: from the
    /// screen's top.
    public static let topGap = 51.0
    /// `gaps.outer.top` on the built-in display: below what the notch keeps.
    public static let topGapBuiltIn = 14.0
    /// `gaps.outer.bottom`.
    public static let bottomGap = 8.0

    /// A top-row window's border starts at most this far below the strip.
    static let topRowReach = 12.0
    /// An end window's border is at most this far from the screen's side.
    static let sideReach = 16.0

    /// How far the visible border reaches outside its window: half its
    /// width (the inner half is under the window).
    public static func reach(width: Double) -> Double { width / 2 }

    /// The border's outer corner radius: the window's plus the reach.
    public static func cornerRadius(width: Double) -> Double { windowCornerRadius + reach(width: width) }

    /// JankyBorders' config as grove-themes renders it:
    /// `$XDG_CONFIG_HOME/borders/bordersrc`, default `~/.config/borders/bordersrc`.
    public static func configFile(home: URL, environment: [String: String]) -> URL {
        KeysPaths.configDirectory(home: home, environment: environment).appendingPathComponent("borders/bordersrc")
    }

    /// `width=` from bordersrc's text; `defaultWidth` when it isn't there or
    /// isn't a sensible number.
    public static func width(bordersrc: String?) -> Double {
        guard let bordersrc else { return defaultWidth }
        for line in bordersrc.split(separator: "\n") where !line.drop(while: { $0 == " " }).hasPrefix("#") {
            for word in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) where word.hasPrefix("width=") {
                if let value = Double(word.dropFirst("width=".count)), value > 0, value <= 40 { return value }
            }
        }
        return defaultWidth
    }

    /// A border's outer rectangle from the frame of the `borders` window
    /// that draws it: that window is the bordered one grown by the width
    /// and the padding; the visible border ends half a width outside it.
    public static func outerRect(ofBorderWindow frame: CGRect, width: Double) -> CGRect {
        let inset = windowPadding + width - reach(width: width)
        return frame.insetBy(dx: inset, dy: inset)
    }

    /// The lines without a tiled window to read them from: the configured
    /// gaps less the border's reach. `notchInset`: what the built-in display
    /// keeps at the top (its safe area), 0 on any other.
    public static func fallback(screen: CGRect, notchInset: Double, width: Double) -> BorderLines {
        let reach = reach(width: width)
        let windowTop = notchInset > 0 ? (notchInset + topGapBuiltIn).rounded(.up) : topGap
        return BorderLines(top: max(screen.minY + stripHeight, screen.minY + windowTop - reach),
                           left: screen.minX + sideGap - reach,
                           right: screen.maxX - sideGap + reach)
    }

    /// The lines on `screen` from the frames of the `borders` windows on
    /// screen. The top row is the borders that start within `topRowReach`
    /// below the strip: the top line is the highest of them, the side lines
    /// their extremes when those are at the screen's sides. Whatever can't
    /// be read (no tiled window, a floating one alone, a window that stops
    /// short of a side) comes from `fallback`.
    public static func lines(borderWindows: [CGRect], width: Double, screen: CGRect,
                             fallback: BorderLines) -> BorderLines {
        let strip = screen.minY + stripHeight
        let row = borderWindows
            .map { outerRect(ofBorderWindow: $0, width: width) }
            .filter { $0.minY >= strip && $0.minY <= strip + topRowReach
                && $0.maxX > screen.minX && $0.minX < screen.maxX && $0.width > 0 }
        guard let top = row.map(\.minY).min() else { return fallback }
        var lines = BorderLines(top: top, left: fallback.left, right: fallback.right)
        if let left = row.map(\.minX).min(), left >= screen.minX, left <= screen.minX + sideReach { lines.left = left }
        if let right = row.map(\.maxX).max(), right <= screen.maxX, right >= screen.maxX - sideReach {
            lines.right = right
        }
        return lines
    }
}

/// Which side of its pill a panel hangs from.
public enum BarPanelAnchor: Sendable {
    /// Its left edge on the pill's left outline: the Grove menu.
    case leading
    /// Its right edge on the pill's right outline: every other panel.
    case trailing
}

/// Where a panel goes and which of its top corners follow the window
/// border's corner.
public struct BarPanelPlacement: Equatable, Sendable {
    /// The panel's outer rectangle (its outline's outer edge); half points
    /// are meant.
    public var frame: CGRect
    /// The left edge is the left border line: that corner takes the
    /// border's radius.
    public var followsLeft: Bool
    public var followsRight: Bool

    /// A pill's end outline this close to a border line is the bar's last
    /// pill: the panel takes the line, not the pill (the bar places pills on
    /// whole points, the lines are on half points).
    public static let snap = 2.0

    /// - `size`: the panel's.
    /// - `pill`: the pill's rectangle (its outline is the rectangle's edge);
    ///   nil when the bar didn't answer: the panel hangs from the line on
    ///   its side.
    /// - `bottom`: the lowest the panel may reach (the screen's bottom less
    ///   the gap); a taller panel is cut there.
    ///
    /// The top edge is the top line. The anchored edge is the pill's
    /// outline, or the border line when the pill ends within `snap` of it.
    /// A panel wider than the room on its side is moved in between the lines.
    public static func place(size: CGSize, anchor: BarPanelAnchor, pill: CGRect?, lines: BorderLines,
                             bottom: Double) -> BarPanelPlacement {
        var x: Double
        switch anchor {
        case .trailing:
            var edge = pill.map { Double($0.maxX) } ?? lines.right
            if abs(edge - lines.right) <= snap { edge = lines.right }
            x = edge - size.width
        case .leading:
            var edge = pill.map { Double($0.minX) } ?? lines.left
            if abs(edge - lines.left) <= snap { edge = lines.left }
            x = edge
        }
        x = max(lines.left, min(x, lines.right - size.width))
        let height = max(0, min(size.height, bottom - lines.top))
        let frame = CGRect(x: x, y: lines.top, width: size.width, height: height)
        return BarPanelPlacement(frame: frame, followsLeft: frame.minX == lines.left,
                                 followsRight: frame.maxX == lines.right)
    }

    /// The window that holds the panel: `frame` grown to whole points
    /// (windows sit on whole points), and where the panel is drawn inside it.
    public var window: (frame: CGRect, inset: CGPoint) {
        let whole = CGRect(x: frame.minX.rounded(.down), y: frame.minY.rounded(.down),
                           width: frame.maxX.rounded(.up) - frame.minX.rounded(.down),
                           height: frame.maxY.rounded(.up) - frame.minY.rounded(.down))
        return (whole, CGPoint(x: frame.minX - whole.minX, y: frame.minY - whole.minY))
    }
}

/// What `sketchybar --query <item>` says about where an item is.
public enum BarQuery {
    /// The item's rectangle on each display it is drawn on, by SketchyBar's
    /// display number (1 is the first): `bounding_rects` →
    /// `display-N` → `origin` [x, y], `size` [w, h]. Empty when the answer
    /// can't be read or the item isn't drawn.
    public static func rects(json: String) -> [Int: CGRect] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let rects = object["bounding_rects"] as? [String: Any] else { return [:] }
        var found: [Int: CGRect] = [:]
        for (key, value) in rects {
            guard key.hasPrefix("display-"), let display = Int(key.dropFirst("display-".count)),
                  let entry = value as? [String: Any],
                  let origin = entry["origin"] as? [Double], origin.count == 2,
                  let size = entry["size"] as? [Double], size.count == 2, size[0] > 0, size[1] > 0 else { continue }
            found[display] = CGRect(x: origin[0], y: origin[1], width: size[0], height: size[1])
        }
        return found
    }
}
