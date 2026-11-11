import AppKit
import GroveThemesCore
import SwiftUI

extension Color {
    /// A palette colour for SwiftUI (sRGB).
    public init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension NSColor {
    /// A palette colour for AppKit (a text field's text): sRGB, opaque.
    public convenience init(_ rgb: RGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

extension ThemeColors {
    /// Everforest Dark Medium, worn only until the CLI's first `list` answers
    /// (or when it never does: the error state still needs colours). The one
    /// copy of a palette outside grove-dotfiles' theme files; GroveUITests
    /// holds it to them.
    public static let fallback = ThemeColors(palette: Palette(name: "Dark Medium", appearance: "dark", colors: [
        "bg0": "#2D353B", "bg1": "#343F44", "bg2": "#3D484D", "bg3": "#475258",
        "fg": "#D3C6AA", "grey1": "#859289", "red": "#E67E80", "orange": "#E69875",
        "yellow": "#DBBC7F", "green": "#A7C080", "aqua": "#83C092", "blue": "#7FBBB3",
        "purple": "#D699B6", "border": "#475258", "on_accent": "#2D353B", "dim": "#859289",
    ]))!

    /// For `.preferredColorScheme`, so the system's own controls match.
    public var colorScheme: ColorScheme { isDark ? .dark : .light }
}

/// What the views draw with, so each names the job and not the scheme. The
/// apps were tuned in the dark schemes and look there as they always did: the
/// roles are the old colours in dark, and anything else changes in light only.
extension ThemeColors {
    /// A line between things (an unselected card's, a field's or a pill's
    /// outline): `border`.
    public var line: Color { Color(border) }

    /// Quiet text (labels, notes): `dim`.
    public var quiet: Color { Color(dim) }

    /// Quiet text the dark schemes dim further, to `dark` opacity; full
    /// strength in light (`quietOpacity`).
    public func quiet(dark opacity: Double) -> Color {
        Color(dim).opacity(quietOpacity(dark: opacity))
    }

    /// Words set in an accent: the accent in dark, fg in light (`accentInk`).
    public func ink(_ accent: RGB) -> Color { Color(accentInk(accent)) }

    /// A sentence in an accent colour (an error in red, a warning in orange).
    /// Dark: as it was. Light: the accents are 1.9 to 3.3:1 as text, so a dot
    /// carries the colour and the sentence is fg.
    public func marked(_ text: String, _ accent: RGB) -> Text {
        guard isLight else { return Text(text).foregroundStyle(Color(accent)) }
        return (Text("● ").foregroundStyle(Color(accent)) + Text(verbatim: text)).foregroundStyle(Color(fg))
    }
}

/// The current scheme's colours, set at the top of each window, dropdown and
/// panel.
private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeColors.fallback
}

extension EnvironmentValues {
    /// The colours the views under here draw with (`.environment(\.theme, …)`).
    public var theme: ThemeColors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
