import GroveThemesCore
import GroveUI
import SwiftUI

/// What only Grove Themes draws with; the shared roles, fonts and helpers
/// are GroveUI's.
extension ThemeColors {
    /// A line the dark schemes draw as fg at `dark` opacity (the dropdown's
    /// tiles and divider); on a pale background that is too faint, so `border`.
    func softLine(dark opacity: Double) -> Color {
        isDark ? Color(fg).opacity(opacity) : Color(border)
    }
}

/// A dot and "on" beside the current scheme or choice in the gallery: the dot in
/// green, the word with it in dark and in fg in light.
struct OnMark: View {
    @Environment(\.theme) private var theme

    var body: some View {
        (GroveIcon.text(.dot, size: GroveType.label).foregroundStyle(Color(theme.green)) + Text(" on").foregroundStyle(theme.ink(theme.green)))
            .font(GroveFont.mono(GroveType.label))
    }
}

/// The scheme name under "Grove Themes" in the dropdown and on each gallery card:
/// one style so the two can't drift apart. fg at 0.75 in dark; whole in light,
/// where 0.75 would leave it near 3:1.
struct SchemeNameStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .font(GroveFont.mono(GroveType.label))
            .foregroundStyle(Color(theme.fg).opacity(theme.quietOpacity(dark: 0.75)))
    }
}

extension ThemesModel {
    /// The current scheme's colours, or the fallback before the first `list`.
    var currentColors: ThemeColors {
        list.flatMap { colors(for: $0.current) } ?? .fallback
    }

    func colors(for scheme: String) -> ThemeColors? {
        list?.palettes[scheme].flatMap(ThemeColors.init(palette:))
    }

    /// Schemes in the CLI's order, the dark ones (or light ones) only.
    func schemes(dark: Bool) -> [String] {
        guard let list else { return [] }
        return list.schemes.filter { colors(for: $0)?.isDark == dark }
    }

    /// Tiles and cards take no clicks while a switch runs or the CLI is in trouble.
    var switchingDisabled: Bool { isBusy || error != nil }
}

/// "dark-medium" → "Medium".
func contrastName(_ scheme: String) -> String {
    StatusText.displayName(String(scheme.split(separator: "-").last ?? Substring(scheme)))
}
