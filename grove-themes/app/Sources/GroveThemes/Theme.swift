import CoreText
import GroveThemesCore
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension ThemeColors {
    /// Everforest Dark Medium, worn only until the CLI's first `list` answers
    /// (or when it never does: the error state still needs colours).
    static let fallback = ThemeColors(palette: Palette(name: "Dark Medium", appearance: "dark", colors: [
        "bg0": "#2D353B", "bg1": "#343F44", "bg2": "#3D484D", "bg3": "#475258",
        "fg": "#D3C6AA", "grey1": "#859289", "red": "#E67E80", "orange": "#E69875",
        "yellow": "#DBBC7F", "green": "#A7C080", "aqua": "#83C092", "blue": "#7FBBB3",
        "purple": "#D699B6",
    ]))!

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// The Grove lockup's ink: the branding's own colours, not the palette's.
    var lockupInk: Color {
        isDark ? Color(.sRGB, red: 0xDA / 255, green: 0xC7 / 255, blue: 0xA2 / 255)
               : Color(.sRGB, red: 0x27 / 255, green: 0x33 / 255, blue: 0x2A / 255)
    }
}

/// The current scheme's colours, set at the top of the dropdown and the gallery.
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

/// The scheme name under "Grove Themes" in the dropdown and on each gallery card:
/// one style so the two can't drift apart.
struct SchemeNameStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .font(GroveFont.mono(12))
            .foregroundStyle(Color(theme.fg).opacity(0.75))
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
