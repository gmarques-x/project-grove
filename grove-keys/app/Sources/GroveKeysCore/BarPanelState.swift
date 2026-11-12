import Foundation
import GroveThemesCore

/// Which bar panel is open, and what a toggle link means now.
///
/// A click on the open panel's own pill is first a click outside the panel
/// (it is put away), then the pill's toggle link arrives: that link is the
/// same "put away", not a new "show". So a toggle for the panel that a click
/// outside closed within `ownClick` seconds does nothing.
public struct BarPanelToggle: Sendable {
    /// How long after a click outside the same panel's link is taken for
    /// that click (as `KeyPanelHost`'s own-link guard).
    public static let ownClick: TimeInterval = 0.5

    public enum Step: Equatable, Sendable {
        /// Show this panel, after putting `closing` away.
        case open(String, closing: String?)
        /// Put the open panel away.
        case close(String)
        /// The link was the click that already closed the panel.
        case nothing
    }

    /// The open panel's name.
    public private(set) var open: String?
    private var dismissed: (name: String, at: Date)?

    public init() {}

    /// A `panel/<name>` link arrived.
    public mutating func toggle(_ name: String, now: Date) -> Step {
        if open == name {
            open = nil
            dismissed = nil
            return .close(name)
        }
        if let dismissed, dismissed.name == name, now.timeIntervalSince(dismissed.at) < Self.ownClick,
           now >= dismissed.at {
            self.dismissed = nil
            return .nothing
        }
        let closing = open
        open = name
        dismissed = nil
        return .open(name, closing: closing)
    }

    /// The open panel was put away by a click outside it (or the keyboard
    /// going elsewhere).
    public mutating func dismissedFromOutside(now: Date) {
        guard let open else { return }
        dismissed = (open, now)
        self.open = nil
    }

    /// The open panel was put away any other way (Escape, a row chosen,
    /// `panel/close`, a workspace change).
    public mutating func closed() {
        open = nil
        dismissed = nil
    }
}

/// What Grove Keys tells the bar about the open panel.
public enum BarPanelFile {
    /// `$GROVE_STATE/bar-panel` (default `~/.local/state/grove/bar-panel`):
    /// one line, the open panel's pill ("pill.clock"); no file when none is
    /// open. The bar's hover helper reads it so the open pill stays filled,
    /// and its workspaces plugin so a workspace change only sends
    /// `panel/close` when there is something to close.
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("bar-panel")
    }

    /// A bar item's name as the file and `sketchybar` may be given it:
    /// lower-case letters, digits, dots and underscores.
    public static func isItemName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 40 && name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "_"
        }
    }

    /// A colour as SketchyBar reads it: `0xffRRGGBB`, opaque.
    public static func argb(_ color: RGB) -> String {
        func byte(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "0xff%02x%02x%02x", byte(color.red), byte(color.green), byte(color.blue))
    }

    /// No fill, as the bar's `sb_transparent`: bg0 without its alpha.
    public static func transparent(_ bg0: RGB) -> String {
        "0x00" + argb(bg0).dropFirst(4)
    }
}
