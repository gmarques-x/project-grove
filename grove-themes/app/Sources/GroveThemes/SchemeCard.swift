import GroveThemesCore
import GroveUI
import SwiftUI

/// One scheme in the gallery: a small desktop (its bg0 with the Grove lockup
/// and a terminal snippet), then its name.
struct SchemeCard: View {
    let scheme: String
    let colors: ThemeColors
    let isCurrent: Bool
    let isBusy: Bool
    /// The keyboard focus box is on this card.
    var isFocused = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GroveRadius.card)
        Button(action: action) {
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                desktop
                HStack(alignment: .firstTextBaseline) {
                    Text(StatusText.displayName(scheme)).modifier(SchemeNameStyle())
                    Spacer(minLength: 4)
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if isCurrent {
                        OnMark()
                    }
                }
            }
            .padding(10)
            .overlay {
                shape.strokeBorder(isCurrent ? Color(theme.green) : theme.line,
                                   lineWidth: isCurrent ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: GroveRadius.card, outset: 5)
    }

    private var desktop: some View {
        let ink = colors.lockupInk
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color(colors.bg0))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    PineShape().fill(ink).frame(width: 13, height: 13)
                    Text("Project Grove").font(GroveFont.lockup(11)).foregroundStyle(ink)
                }
                .padding(.horizontal, 8)
                .padding(.top, 7)
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { box in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Text("gm").foregroundStyle(Color(colors.aqua))) \(Text("~/grove").foregroundStyle(Color(colors.green))) \(Text("main").foregroundStyle(Color(colors.yellow)))")
                        Text("❯ ls")
                    }
                    .font(GroveFont.mono(9.5))
                    .foregroundStyle(Color(colors.fg))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(width: box.size.width * 0.58, alignment: .leading)
                    .background(Color(colors.bg1), in: RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .padding(.leading, 8)
                .padding(.bottom, 7)
            }
    }
}
