import Foundation

/// One colour, components in 0…1 (the `Hex.rgb` tuple as a value type).
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        guard let rgb = Hex.rgb(hex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// A scheme's palette as colours; nil unless all thirteen are there and readable
/// (the roles have stand-ins).
public struct ThemeColors: Equatable, Sendable {
    public let bg0, bg1, bg2, bg3, fg, grey1, red, orange, yellow, green, aqua, blue, purple: RGB
    /// The roles: what a colour is for, each scheme's own pick (grove-dotfiles'
    /// theme files). `border`: lines between things. `onAccent`: text on an
    /// accent-coloured fill. `dim`: quiet text (labels, notes). In the dark
    /// schemes they are bg3, bg0 and grey1, and a CLI older than the roles
    /// sends none of them: those three stand in, so nothing changes until the
    /// CLI catches up.
    public let border, onAccent, dim: RGB
    /// The Grove wordmark's ink (`lockup_ink`): the branding's own colour, not
    /// an Everforest one; one for the dark schemes, one for the light. A CLI
    /// older than the role sends none: `ThemeColors.lockupInk(dark:)`.
    public let lockupInk: RGB
    /// The fill under the pointer on something clickable (`hover`): bg1 on a
    /// dark scheme, bg3 on a light one (bg1 on bg0 is 1.06:1 there). A CLI
    /// older than the role sends none: those two stand in, as the theme
    /// files have them.
    public let hover: RGB
    /// The palette's `appearance` is "dark".
    public let isDark: Bool
    /// Not dark. The apps were tuned in the dark schemes: what only a pale
    /// background needs is asked for here.
    public var isLight: Bool { !isDark }

    public init?(palette: Palette) {
        func color(_ key: String) -> RGB? { palette.colors[key].flatMap(RGB.init(hex:)) }
        guard let bg0 = color("bg0"), let bg1 = color("bg1"), let bg2 = color("bg2"),
              let bg3 = color("bg3"), let fg = color("fg"), let grey1 = color("grey1"),
              let red = color("red"), let orange = color("orange"), let yellow = color("yellow"),
              let green = color("green"), let aqua = color("aqua"), let blue = color("blue"),
              let purple = color("purple")
        else { return nil }
        self.bg0 = bg0; self.bg1 = bg1; self.bg2 = bg2; self.bg3 = bg3
        self.fg = fg; self.grey1 = grey1
        self.red = red; self.orange = orange; self.yellow = yellow; self.green = green
        self.aqua = aqua; self.blue = blue; self.purple = purple
        border = color("border") ?? bg3
        onAccent = color("on_accent") ?? bg0
        dim = color("dim") ?? grey1
        isDark = palette.appearance == "dark"
        lockupInk = color("lockup_ink") ?? Self.lockupInk(dark: isDark)
        hover = color("hover") ?? (isDark ? bg1 : bg3)
    }

    /// What the theme files have as `lockup_ink` (ThemeColorsTests and
    /// GroveUITests hold it to them), for a CLI that doesn't send the role
    /// yet: DA C7 A2 on a dark scheme, 27 33 2A on a light one.
    public static func lockupInk(dark: Bool) -> RGB {
        dark ? RGB(red: 0xDA / 255, green: 0xC7 / 255, blue: 0xA2 / 255)
             : RGB(red: 0x27 / 255, green: 0x33 / 255, blue: 0x2A / 255)
    }

    /// Quiet text's opacity. Some of it is dimmed further in the dark schemes
    /// (`dark`); the light ones' `dim` is 2.8 to 3.2:1 on bg0 at full strength
    /// and has nothing to spare, so there it is always 1.
    public func quietOpacity(dark: Double) -> Double {
        isDark ? dark : 1
    }

    /// The colour for words set in an accent ("on", an error, a key's label).
    /// The dark schemes' accents read as text (4.5:1 and more on bg0); the light
    /// ones' are 1.9 to 3.3:1, so there the words are fg and the colour stays on
    /// the mark beside them (a dot, a border, a tinted cap).
    public func accentInk(_ accent: RGB) -> RGB {
        isDark ? accent : fg
    }
}
