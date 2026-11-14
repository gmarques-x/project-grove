import CoreGraphics
import Foundation

/// A real click on another app's status item, for an item that ignores
/// Accessibility presses. OneDrive's does (found 2026-11-14 on macOS 27):
/// `AXPress` on its button, on MenuBarAgent's group around it, and on the
/// app's own status bar item all answer success and open nothing, and so
/// does a click posted to OneDrive's or MenuBarAgent's pid. Only a click
/// through the window server opens its Activity Center. The Grove bar
/// covers the native menu bar, so Grove Keys hides the bar for a moment,
/// clicks, puts the pointer back and shows the bar again
/// (`StatusItemClicker`). These are the rules; the clicking is Grove Keys'.
public enum StatusItemClick {
    /// The native menu bar's window level (`kCGMainMenuWindowLevel`).
    public static let menuBarLayer = 24

    /// A window on screen as the window server lists it, frontmost first.
    public struct Window: Equatable, Sendable {
        public var layer: Int
        public var bounds: CGRect

        public init(layer: Int, bounds: CGRect) {
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// Where to click: the middle of the item's frame. Nil without a frame,
    /// or for an empty one (an item not drawn).
    public static func point(frame: CGRect?) -> CGPoint? {
        guard let frame, frame.width > 0, frame.height > 0, frame.minX.isFinite, frame.minY.isFinite else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The click would reach the item: the frontmost window under the point
    /// is the native menu bar's. Anything over it (the Grove bar, a panel,
    /// a menu) or no menu bar there (hidden, another display) means no click.
    public static func reachable(_ point: CGPoint, windows: [Window]) -> Bool {
        windows.first { $0.bounds.contains(point) }?.layer == menuBarLayer
    }

    /// SketchyBar's `--query bar` answer: is the bar hidden? Nil when the
    /// answer can't be read.
    public static func barHidden(json: String) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let hidden = object["hidden"] as? String else { return nil }
        switch hidden {
        case "on": return true
        case "off": return false
        default: return nil
        }
    }
}
