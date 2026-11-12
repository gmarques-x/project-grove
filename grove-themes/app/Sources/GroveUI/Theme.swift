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
        "lockup_ink": "#DAC7A2", "hover": "#343F44",
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

    /// The backdrop of a panel over other apps (the cheat sheets, the
    /// launcher): the desktop dimmed with bg0 in dark; in light bg0 would
    /// whiten it, so the dark ink (`onAccent`), thinner.
    public var scrim: Color {
        isDark ? Color(bg0).opacity(0.6) : Color(onAccent).opacity(0.4)
    }

    /// The shadow of a card on the scrim: bg0 in dark; the dark ink in
    /// light, where a bg0 shadow can't be seen.
    public var cardShadow: Color {
        isDark ? Color(bg0).opacity(0.5) : Color(onAccent).opacity(0.35)
    }

    /// The fill of the selected row or segment: two background steps above
    /// what it sits on (bg2 on bg0, bg3 on a bg1 panel). In light a step is
    /// 1.06 to 1.2:1, so the caller adds `.lightOutline`. Never the system's
    /// accent: selection looks the same in every Grove list.
    public func selectedFill(on surface: Surface) -> Color {
        Color(surface == .base ? bg2 : bg3)
    }

    /// The fill under the pointer on a row: one step above what it sits on
    /// (the `hover` role on bg0; bg2 on a bg1 panel), so it reads as less
    /// than the selection in dark.
    public func hoverFill(on surface: Surface) -> Color {
        Color(surface == .base ? hover : bg2)
    }

    /// The card of a sheet on the scrim (the cheat sheets, the launcher): bg0,
    /// a little see-through.
    public var sheetFill: Color { Color(bg0).opacity(0.94) }

    /// An accent's soft fill, behind text: a banner in the accent's colour, a
    /// bound key cap in its kind's. How soft is named by what is filled
    /// (`TintStrength`), so no view writes an opacity.
    public func tintFill(_ accent: RGB, _ strength: TintStrength) -> Color {
        Color(accent).opacity(strength.rawValue)
    }

    /// Words set in an accent: the accent in dark, fg in light (`accentInk`).
    public func ink(_ accent: RGB) -> Color { Color(accentInk(accent)) }

    /// A sentence in an accent colour (an error in red, a warning in orange).
    /// Dark: as it was. Light: the accents are 1.9 to 3.3:1 as text, so a dot
    /// carries the colour and the sentence is fg. `size`: the size the
    /// sentence is set in, for the dot (`GroveIcon`'s rule).
    public func marked(_ text: String, _ accent: RGB, size: CGFloat = GroveType.body) -> Text {
        guard isLight else { return Text(text).foregroundStyle(Color(accent)) }
        return (GroveIcon.text(.dot, size: size).foregroundStyle(Color(accent)) + Text(verbatim: " " + text))
            .foregroundStyle(Color(fg))
    }
}

/// What a row or a segment sits on, for `selectedFill` and `hoverFill`.
public enum Surface: Sendable {
    /// The window's or a sheet's own background, or a well in a panel: bg0.
    case base
    /// A panel on the window (a group, a pill): bg1.
    case panel
}

/// How strong `ThemeColors.tintFill` is, by what it fills. The values the
/// dark schemes were tuned on.
public enum TintStrength: Double, Sendable {
    /// A banner across a window (an error in red, a warning in orange).
    case banner = 0.14
    /// A bound key cap, in its kind's colour.
    case cap = 0.16
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
