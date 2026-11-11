import GroveThemesCore
import GroveUI
import SwiftUI

/// What only Grove Keys draws with; the shared roles, fonts and helpers are
/// GroveUI's.
extension ThemeColors {
    /// A key cap's or the keyboard well's own outline: one background step
    /// from its fill in dark (`dark`), which can't be seen in light: `border`.
    func capLine(dark: RGB) -> Color {
        isDark ? Color(dark) : Color(border)
    }

    /// A line in an accent (a bound cap's outline): faint in dark, where the
    /// label carries the colour; whole in light, where the label is fg and
    /// the line carries it.
    func accentLine(_ accent: Color, dark opacity: Double) -> Color {
        isDark ? accent.opacity(opacity) : accent
    }

    /// The cheat sheet's backdrop: the desktop dimmed with bg0 in dark; in
    /// light bg0 would whiten it, so the dark ink (`onAccent`), thinner.
    var scrim: Color {
        isDark ? Color(bg0).opacity(0.6) : Color(onAccent).opacity(0.4)
    }

    /// The cheat sheet's shadow: bg0 in dark; the dark ink in light, where a
    /// bg0 shadow can't be seen.
    var cardShadow: Color {
        isDark ? Color(bg0).opacity(0.5) : Color(onAccent).opacity(0.35)
    }

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
        case "grey1": return dim
        default: return fg
        }
    }
}
