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
        "purple": "#D699B6", "border": "#475258", "on_accent": "#2D353B", "dim": "#859289",
    ]))!

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

/// What the views draw with, so each names the job and not the scheme. The app
/// was tuned in the dark schemes and looks there as it always did: the roles
/// are the old colours in dark, and anything else changes in light only.
/// (Grove Themes' Theme.swift has the same helpers; keep the two alike.)
extension ThemeColors {
    /// A line between things (a field's or pill's outline): `border`.
    var line: Color { Color(border) }

    /// Quiet text (labels, notes): `dim`.
    var quiet: Color { Color(dim) }

    /// Quiet text the dark schemes dim further, to `dark` opacity; full
    /// strength in light (`quietOpacity`).
    func quiet(dark opacity: Double) -> Color {
        Color(dim).opacity(quietOpacity(dark: opacity))
    }

    /// Words set in an accent: the accent in dark, fg in light (`accentInk`).
    func ink(_ accent: RGB) -> Color { Color(accentInk(accent)) }

    /// A sentence in an accent colour (an error in red, a warning in orange).
    /// Dark: as it was. Light: the accents are 1.9 to 3.3:1 as text, so a dot
    /// carries the colour and the sentence is fg.
    func marked(_ text: String, _ accent: RGB) -> Text {
        guard isLight else { return Text(text).foregroundStyle(Color(accent)) }
        return (Text("● ").foregroundStyle(Color(accent)) + Text(verbatim: text)).foregroundStyle(Color(fg))
    }

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
}

extension View {
    /// A panel one background step from what it sits on (bg1 on bg0, a bg0
    /// well on bg1, a bg3 selection) is 1.06 to 1.2:1 in the light schemes:
    /// there it gets an outline to read as a panel, `border` unless `accent`
    /// is given (a warning banner). Nothing in dark, and nothing unless `shown`.
    func lightOutline(cornerRadius: CGFloat, accent: RGB? = nil, when shown: Bool = true) -> some View {
        modifier(LightOutline(cornerRadius: cornerRadius, accent: accent, shown: shown))
    }
}

private struct LightOutline: ViewModifier {
    let cornerRadius: CGFloat
    let accent: RGB?
    let shown: Bool
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.overlay {
            if theme.isLight, shown {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(accent.map(Color.init) ?? theme.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
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

    /// `mono` for AppKit (a text field).
    static func monoNS(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: "JetBrains Mono", traits: [], weight: 5, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
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
        case "grey1": return dim
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
