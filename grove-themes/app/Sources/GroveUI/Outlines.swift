import GroveThemesCore
import SwiftUI

extension View {
    /// A panel one background step from what it sits on (bg1 on bg0, a bg0
    /// well on bg1, a bg3 selection) is 1.06 to 1.2:1 in the light schemes:
    /// there it gets an outline to read as a panel, `border` unless `accent`
    /// is given (a warning banner). Nothing in dark, and nothing unless `shown`.
    public func lightOutline(cornerRadius: CGFloat, accent: RGB? = nil, when shown: Bool = true) -> some View {
        modifier(LightOutline(cornerRadius: cornerRadius, accent: accent, shown: shown))
    }

    /// The keyboard focus box: a 2 pt rounded outline in the current scheme's
    /// green, `outset` points outside the view (tiles and cards: 5, clear
    /// of their own 1 pt line; menu rows: 0, on the row's edge). The one
    /// focus style in both apps, and the only 2 pt green outline: "current"
    /// is a 1 pt green line and a mark.
    public func focusBox(_ shown: Bool, cornerRadius: CGFloat, outset: CGFloat) -> some View {
        modifier(FocusBox(shown: shown, cornerRadius: cornerRadius, outset: outset))
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
