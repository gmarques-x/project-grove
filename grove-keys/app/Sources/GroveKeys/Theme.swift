import AppKit
import CoreText
import GroveThemesCore
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension NSColor {
    convenience init(_ rgb: RGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

extension ThemeColors {
    /// Everforest Dark Medium, worn until grove-themes' first `list` answers
    /// (or when it never does), as in Grove Themes.
    static let fallback = ThemeColors(palette: Palette(name: "Dark Medium", appearance: "dark", colors: [
        "bg0": "#2D353B", "bg1": "#343F44", "bg2": "#3D484D", "bg3": "#475258",
        "fg": "#D3C6AA", "grey1": "#859289", "red": "#E67E80", "orange": "#E69875",
        "yellow": "#DBBC7F", "green": "#A7C080", "aqua": "#83C092", "blue": "#7FBBB3",
        "purple": "#D699B6",
    ]))!

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

/// The current scheme's colours, for the window and the cheat sheet.
private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeColors.fallback
}

extension EnvironmentValues {
    var theme: ThemeColors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum GroveFont {
    private static let families = Set((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? [])
    private static let hasMono = families.contains("JetBrains Mono")
    private static let lockupFamily = families.contains("Courier Prime") ? "Courier Prime" : "Courier New"

    /// JetBrains Mono, else the system monospaced font.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasMono ? .custom("JetBrains Mono", size: size).weight(weight)
                : .system(size: size, weight: weight, design: .monospaced)
    }

    /// The lockup's typewriter face: Courier Prime, else Courier New; bold.
    static func lockup(_ size: CGFloat) -> Font {
        .custom(lockupFamily, size: size).weight(.bold)
    }
}

extension ThemeColors {
    /// A key's colour by palette name (BindingKind.tint).
    func named(_ name: String) -> RGB {
        switch name {
        case "green": return green
        case "aqua": return aqua
        case "blue": return blue
        case "yellow": return yellow
        case "orange": return orange
        case "red": return red
        case "purple": return purple
        case "grey1": return grey1
        default: return fg
        }
    }
}

extension View {
    /// The keyboard focus box, as Grove Themes: a 2 pt outline in the scheme's
    /// green, `outset` points outside the view.
    func focusBox(_ shown: Bool, cornerRadius: CGFloat, outset: CGFloat) -> some View {
        modifier(FocusBox(shown: shown, cornerRadius: cornerRadius, outset: outset))
    }
}

private struct FocusBox: ViewModifier {
    let shown: Bool
    let cornerRadius: CGFloat
    let outset: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.overlay {
            if shown {
                RoundedRectangle(cornerRadius: cornerRadius + outset)
                    .strokeBorder(Color(theme.green), lineWidth: 2)
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
        }
    }
}
