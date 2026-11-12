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
                    GroveIcon(.current, size: GroveType.body, weight: .bold)
                        .foregroundStyle(Color(colors.fg))
                        .padding(.top, GroveSpace.s8)
                        .padding(.trailing, GroveSpace.s8)
                }
            }
            .overlay {
                // Current: a 1 pt green line and the tick. The 2 pt green box is the focus only.
                shape.strokeBorder(isCurrent ? Color(theme.green) : theme.softLine(dark: 0.22), lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: GroveRadius.card, outset: 5)
        .help(StatusText.displayName(scheme))
        // "Dark Medium", not the tile's "Aa" and "Medium".
        .accessibilityLabel(StatusText.displayName(scheme))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
