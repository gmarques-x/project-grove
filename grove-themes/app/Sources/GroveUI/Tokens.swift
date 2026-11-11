import CoreGraphics

/// Corner radii, named by what is being rounded. Views take a radius from
/// here, not a literal. (Colours come from the theme files, through
/// `ThemeColors`.)
public enum GroveRadius {
    /// 4: inline bits (a badge, a swatch, a chip inside a row).
    public static let inline: CGFloat = 4
    /// 6: controls, key caps, pills.
    public static let control: CGFloat = 6
    /// 10: cards and panels.
    public static let card: CGFloat = 10
    /// 16: windows and large sheets.
    public static let window: CGFloat = 16
}

/// Padding and gaps: a 4 pt grid and one half step, named by their size
/// (`s8` is 8 pt), since the same step does different jobs in different views.
public enum GroveSpace {
    /// 2: a hairline gap (rows of a list, a label and its caption).
    public static let s2: CGFloat = 2
    /// 4: parts of one thing (an icon and its word; a pill's vertical padding).
    public static let s4: CGFloat = 4
    /// 8: things in a row; a control's inner padding.
    public static let s8: CGFloat = 8
    /// 12: rows and groups; a card's inner padding.
    public static let s12: CGFloat = 12
    /// 16: sections; a panel's inner padding.
    public static let s16: CGFloat = 16
    /// 24: a window's margins.
    public static let s24: CGFloat = 24

    /// Every step, smallest first.
    public static let scale: [CGFloat] = [s2, s4, s8, s12, s16, s24]
}
