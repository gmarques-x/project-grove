import GroveThemesCore
import GroveUI
import SwiftUI

/// One scheme in the dropdown, drawn in its own colours.
struct SchemeTile: View {
    let scheme: String
    let colors: ThemeColors
    let isCurrent: Bool
    let isBusy: Bool
    /// The keyboard focus box is on this tile.
    var isFocused = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GroveRadius.card)
        Button(action: action) {
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                Text("Aa").font(GroveFont.mono(GroveType.title, .semibold))
                HStack(spacing: GroveSpace.s4) {
                    ForEach(Array([colors.red, colors.yellow, colors.green, colors.aqua, colors.blue].enumerated()),
                            id: \.offset) { _, dot in
                        Circle().fill(Color(dot)).frame(width: 7, height: 7)
                    }
                }
                Text(contrastName(scheme)).font(GroveFont.mono(GroveType.finePrint))
            }
            .foregroundStyle(Color(colors.fg))
            .padding(GroveSpace.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(colors.bg0), in: shape)
            .overlay(alignment: .topTrailing) {
                if isBusy {
                    ProgressView().controlSize(.small).padding(GroveSpace.s4)
                } else if isCurrent {
                    Text("✓")
                        .font(GroveFont.mono(GroveType.body, .bold))
                        .foregroundStyle(Color(colors.fg))
                        .padding(.top, GroveSpace.s8)
                        .padding(.trailing, GroveSpace.s8)
                }
            }
            .overlay {
                shape.strokeBorder(isCurrent ? Color(theme.green) : theme.softLine(dark: 0.22),
                                   lineWidth: isCurrent ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: GroveRadius.card, outset: 5)
        .help(StatusText.displayName(scheme))
    }
}
