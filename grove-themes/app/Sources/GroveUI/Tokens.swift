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

/// Text sizes, named by what the text is. `GroveFont.mono` takes one of
/// these; a literal size is for a drawing (the gallery's miniature desktop)
/// or the wordmark (`GroveFont.lockup`).
public enum GroveType {
    /// 10: fine print (a caption, a count, a key cap's legend, small caps).
    public static let finePrint: CGFloat = 10
    /// 11: body text and rows (a note, a status line, a hint).
    public static let body: CGFloat = 11
    /// 12: labels, names and buttons; a window's own text.
    public static let label: CGFloat = 12
    /// 13: a heading; a panel's rows (the launcher, the cheat sheet).
    public static let heading: CGFloat = 13
    /// 15: a title; the launcher's field.
    public static let title: CGFloat = 15

    /// Every size, smallest first.
    public static let scale: [CGFloat] = [finePrint, body, label, heading, title]
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

/// How strongly something is drawn, for what can't take a colour role. Views
/// take an opacity from here, not a literal.
public enum GroveOpacity {
    /// 0.5: an image (an app's icon) on a disabled row, in every Grove menu.
    /// A disabled row's text and symbols are `theme.quiet` instead; an image
    /// keeps its own colours, so it is drawn at half strength.
    public static let disabledImage: Double = 0.5
}
