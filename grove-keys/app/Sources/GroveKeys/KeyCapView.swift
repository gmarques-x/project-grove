import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// One drawn key (mockup §1): its legend on top, what it does below, tinted by
/// the binding's kind. Free keys are dim, modifier caps darker, held caps lit.
/// In the light schemes the label is fg (the kinds' colours are 1.6 to 2.6:1
/// as text on a tinted cap) and the cap's outline carries the colour, whole.
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
        let accent = binding.map { theme.named($0.missingApp ? "grey1" : $0.kind.tint) }
        let tint = accent.map { Color($0) }
        let layout = compact
            ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            Text(legend)
                .font(GroveFont.mono(GroveType.finePrint))
                .foregroundStyle(legendColor)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let binding, let accent, let tint {
                Text(binding.label)
                    .font(GroveFont.mono(compact ? GroveType.finePrint : GroveType.body, .semibold))
                    // A missing app's label stays quiet in light too.
                    .foregroundStyle(binding.missingApp ? tint : theme.ink(accent))
                    .strikethrough(binding.missingApp)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, compact ? 4 : 6).padding(.vertical, compact ? 0 : 5)
        .frame(width: width, height: height, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: GroveRadius.control)
            ZStack {
                shape.fill(baseColor)
                if let accent, !held, !isModifier { shape.fill(theme.tintFill(accent, .cap)) }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(border(tint), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if binding?.conflict == true {
                Circle().fill(Color(theme.orange)).frame(width: 6, height: 6).padding(5)
            }
        }
        .focusBox(focused, cornerRadius: GroveRadius.control, outset: 3)
        .help(help)
        // One thing to VoiceOver, not a legend and a label apart. Where a cap
        // can be clicked (the Keyboard tab) the caller adds the button trait.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CapWords.spoken(legend: legend, binding: binding, isModifier: isModifier))
    }

    /// The half-height up and down caps: legend and label on one line.
    private var compact: Bool { height < 40 }

    private var legendColor: Color {
        if held { return Color(theme.fg) }
        return theme.quiet(dark: binding == nil ? 0.75 : 1)
    }

    private var baseColor: Color {
        if held { return Color(theme.bg3) }
        return Color(isModifier ? theme.bg0 : theme.bg1)
    }

    private func border(_ tint: Color?) -> Color {
        if held { return Color(theme.dim) }
        if let tint { return theme.accentLine(tint, dark: 0.45) }
        return theme.capLine(dark: theme.bg2)
    }

    private var help: String {
        guard let binding else { return "" }
        if binding.missingApp { return "\(binding.label) is not installed" }
        if binding.conflict { return "Also bound in AeroSpace; the launcher wins" }
        // In words: the cap has room for a few letters only.
        return binding.words
    }
}
