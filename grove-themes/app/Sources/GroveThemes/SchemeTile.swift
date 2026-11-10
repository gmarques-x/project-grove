import GroveThemesCore
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
        let shape = RoundedRectangle(cornerRadius: 8)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aa").font(GroveFont.mono(15, .semibold))
                HStack(spacing: 3) {
                    ForEach(Array([colors.red, colors.yellow, colors.green, colors.aqua, colors.blue].enumerated()),
                            id: \.offset) { _, dot in
                        Circle().fill(Color(dot)).frame(width: 7, height: 7)
                    }
                }
                Text(contrastName(scheme)).font(GroveFont.mono(10.5))
            }
            .foregroundStyle(Color(colors.fg))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(colors.bg0), in: shape)
            .overlay(alignment: .topTrailing) {
                if isBusy {
                    ProgressView().controlSize(.small).padding(5)
                } else if isCurrent {
                    Text("✓")
                        .font(GroveFont.mono(11, .bold))
                        .foregroundStyle(Color(colors.fg))
                        .padding(.top, 6)
                        .padding(.trailing, 7)
                }
            }
            .overlay {
                shape.strokeBorder(isCurrent ? Color(theme.green) : Color(theme.fg).opacity(0.22),
                                   lineWidth: isCurrent ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: 8, outset: 5)
        .help(StatusText.displayName(scheme))
    }
}
