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

/// A scheme's palette as colours; nil unless all thirteen are there and readable.
public struct ThemeColors: Equatable, Sendable {
    public let bg0, bg1, bg2, bg3, fg, grey1, red, orange, yellow, green, aqua, blue, purple: RGB
    /// The palette's `appearance` is "dark".
    public let isDark: Bool

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
        isDark = palette.appearance == "dark"
    }
}
