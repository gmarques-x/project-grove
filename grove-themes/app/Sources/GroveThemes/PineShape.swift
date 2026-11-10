import AppKit
import SwiftUI

/// The Grove logo's pine, from the 40 × 40 path
/// `M20 2 27 12h-4l7 9h-5l8 10H22v7h-4v-7H7l8-10h-5l7-9h-4z`, scaled to fit.
struct PineShape: Shape {
    private static let points: [(CGFloat, CGFloat)] = [
        (20, 2), (27, 12), (23, 12), (30, 21), (25, 21), (33, 31), (22, 31), (22, 38),
        (18, 38), (18, 31), (7, 31), (15, 21), (10, 21), (17, 12), (13, 12),
    ]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 40
        let originX = rect.midX - 20 * scale, originY = rect.midY - 20 * scale
        var path = Path()
        path.addLines(Self.points.map { CGPoint(x: originX + $0.0 * scale, y: originY + $0.1 * scale) })
        path.closeSubpath()
        return path
    }

    /// The pine as a template image for the menu bar (macOS tints it).
    static func menuBarImage(size: CGFloat = 16) -> NSImage {
        let pine = PineShape().path(in: CGRect(x: 0, y: 0, width: size, height: size)).cgPath
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(pine)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
