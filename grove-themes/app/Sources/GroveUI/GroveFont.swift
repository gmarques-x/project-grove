import AppKit
import CoreText
import SwiftUI

/// The apps' two faces: JetBrains Mono for all text, the typewriter face for
/// the Grove wordmark only.
public enum GroveFont {
    private static let families = Set((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? [])
    private static let hasMono = families.contains("JetBrains Mono")
    private static let lockupFamily = families.contains("Courier Prime") ? "Courier Prime" : "Courier New"

    /// JetBrains Mono, else the system monospaced font. `size` from `GroveType`.
    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasMono ? .custom("JetBrains Mono", size: size).weight(weight)
                : .system(size: size, weight: weight, design: .monospaced)
    }

    /// `mono` for AppKit (a text field).
    public static func monoNS(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: "JetBrains Mono", traits: [], weight: 5, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The lockup's typewriter face: Courier Prime, else Courier New; bold.
    public static func lockup(_ size: CGFloat) -> Font {
        .custom(lockupFamily, size: size).weight(.bold)
    }
}
