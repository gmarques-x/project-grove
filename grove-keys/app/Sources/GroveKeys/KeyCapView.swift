import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// One drawn key (mockup §1): its legend on top (the Shift character over the
/// base one where they differ, as printed on Apple's keys), what it does
/// below, tinted by the binding's kind. Free keys are dim, modifier caps
/// darker, held caps lit.
/// In the light schemes the label is fg (the kinds' colours are 1.6 to 2.6:1
/// as text on a tinted cap) and the cap's outline carries the colour, whole.
struct KeyCapView: View {
    let legend: Legend
    let binding: KeyBinding?
    let isModifier: Bool
    let held: Bool
    let focused: Bool
    let width: CGFloat
    let height: CGFloat
    /// The ISO Return's part in the row under this cap (`KeyCapShape`).
    var lower: KeyCapShape.Lower? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let accent = binding.map { theme.named($0.missingApp ? "grey1" : $0.kind.tint) }
        let tint = accent.map { Color($0) }
        let layout = compact
            ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            legendText
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
        // The ISO Return's top part is one unit wide: 4 pt keeps "return" whole in the cheat sheet.
        .padding(.horizontal, compact || lower != nil ? 4 : 6)
        .padding(.top, compact ? 0 : (short ? 3 : 5)).padding(.bottom, compact ? 0 : (short ? 2 : 5))
        .frame(width: width, height: height, alignment: .leading)
        .background {
            let shape = outline
            ZStack {
                shape.fill(baseColor)
                if let accent, !held, !isModifier { shape.fill(theme.tintFill(accent, .cap)) }
            }
        }
        .overlay {
            outline.strokeBorder(border(tint), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if binding?.conflict == true {
                Circle().fill(Color(theme.orange)).frame(width: 6, height: 6).padding(5)
            }
        }
        .focusBox(focused, shape: outline, outset: 3)
        .help(help)
        // One thing to VoiceOver, not a legend and a label apart. Where a cap
        // can be clicked (the Keyboard tab) the caller adds the button trait.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CapWords.spoken(legend: legend.base, binding: binding, isModifier: isModifier))
    }

    var outline: KeyCapShape { KeyCapShape(lower: lower) }

    /// One line, or the Shift character over the base one.
    @ViewBuilder private var legendText: some View {
        if let shift = legend.shift, !compact {
            VStack(alignment: .leading, spacing: 0) {
                Text(shift).font(GroveFont.mono(GroveType.finePrint))
                Text(legend.base).font(GroveFont.mono(GroveType.finePrint))
            }
        } else {
            Text(legend.base).font(GroveFont.mono(GroveType.finePrint))
        }
    }

    /// The cheat sheet's 46 pt caps (key geometry, measured, not the spacing
    /// scale): 3 pt over the text and 2 under, not 5, so two legend lines
    /// and a label fit; the same on every cap, so the rows line up.
    private var short: Bool { height < 50 }

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

/// A key cap's outline: a `GroveRadius.control` rounded rectangle, or for the
/// ISO Return one cap as an inverted L. The view's frame is then the part in
/// the upper row, and `lower` reaches down from its trailing edge into the
/// row under it (drawn and hit-tested outside the frame, so the lower row
/// leaves that place empty).
struct KeyCapShape: InsettableShape {
    struct Lower: Equatable {
        /// Its width, at the cap's trailing edge.
        var width: CGFloat
        /// How far it reaches below the frame: the row gap and a cap's height.
        var drop: CGFloat
    }

    var lower: Lower?
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> KeyCapShape {
        var shape = self
        shape.inset += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let radius = GroveRadius.control
        guard let lower else { return RoundedRectangle(cornerRadius: radius).inset(by: inset).path(in: rect) }
        // Inset (or, negative, outset) evenly, the corners staying concentric:
        // the outer ones smaller, the inner one larger.
        let i = inset
        let left = rect.minX + i, right = rect.maxX - i, top = rect.minY + i
        let step = rect.maxY - i, bottom = rect.maxY + lower.drop - i, inner = rect.maxX - lower.width + i
        let outer = max(0, radius - i), concave = max(0, radius + i)
        var path = Path()
        path.move(to: CGPoint(x: (left + right) / 2, y: top))
        let corners: [(CGPoint, CGPoint, CGFloat)] = [
            (CGPoint(x: right, y: top), CGPoint(x: right, y: bottom), outer),
            (CGPoint(x: right, y: bottom), CGPoint(x: inner, y: bottom), outer),
            (CGPoint(x: inner, y: bottom), CGPoint(x: inner, y: step), outer),
            (CGPoint(x: inner, y: step), CGPoint(x: left, y: step), concave),
            (CGPoint(x: left, y: step), CGPoint(x: left, y: top), outer),
            (CGPoint(x: left, y: top), CGPoint(x: right, y: top), outer),
        ]
        for (corner, next, r) in corners {
            path.addArc(tangent1End: corner, tangent2End: next, radius: r)
        }
        path.closeSubpath()
        return path
    }
}
