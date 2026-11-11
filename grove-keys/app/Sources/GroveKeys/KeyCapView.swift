import GroveKeysCore
import GroveThemesCore
import SwiftUI

/// One drawn key (mockup §1): its legend on top, what it does below, tinted by
/// the binding's kind. Free keys are dim, modifier caps darker, held caps lit.
struct KeyCapView: View {
    let legend: String
    let binding: KeyBinding?
    let isModifier: Bool
    let held: Bool
    let focused: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let tint = binding.map { Color(theme.named($0.missingApp ? "grey1" : $0.kind.tint)) }
        VStack(alignment: .leading, spacing: 0) {
            Text(legend)
                .font(GroveFont.mono(10.5))
                .foregroundStyle(legendColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let binding, let tint {
                Text(binding.label)
                    .font(GroveFont.mono(11.5, .semibold))
                    .foregroundStyle(tint)
                    .strikethrough(binding.missingApp)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, height > 40 ? 5 : 3)
        .frame(width: width, height: height, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 7)
            ZStack {
                shape.fill(baseColor)
                if let tint, !held, !isModifier { shape.fill(tint.opacity(0.16)) }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(border(tint), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if binding?.conflict == true {
                Circle().fill(Color(theme.orange)).frame(width: 6, height: 6).padding(5)
            }
        }
        .focusBox(focused, cornerRadius: 7, outset: 3)
        .help(help)
    }

    private var legendColor: Color {
        if held { return Color(theme.fg) }
        return Color(theme.grey1).opacity(binding == nil ? 0.75 : 1)
    }

    private var baseColor: Color {
        if held { return Color(theme.bg3) }
        return Color(isModifier ? theme.bg0 : theme.bg1)
    }

    private func border(_ tint: Color?) -> Color {
        if held { return Color(theme.grey1) }
        if let tint { return tint.opacity(0.45) }
        return Color(theme.bg2)
    }

    private var help: String {
        guard let binding else { return "" }
        if binding.missingApp { return "\(binding.label) is not installed" }
        if binding.conflict { return "Also bound in AeroSpace; the launcher wins" }
        return ""
    }
}
