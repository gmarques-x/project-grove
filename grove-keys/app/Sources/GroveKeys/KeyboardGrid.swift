import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The drawn MacBook keyboard for one layer (mockup §1 and §3): rows of caps
/// on a well. Modifier caps are drawn here (lit for the layer's held
/// modifiers); named keys come from `named`, so the Keyboard tab can make
/// them clickable and the cheat sheet leaves them plain.
struct KeyboardGrid<Named: View>: View {
    let layer: Layer
    let width: CGFloat
    let capHeight: CGFloat
    @ViewBuilder let named: (_ cap: KeyboardLayout.Cap, _ name: String, _ legend: String, _ width: CGFloat, _ height: CGFloat) -> Named
    @Environment(\.theme) private var theme

    static var gap: CGFloat { 6 }

    var body: some View {
        let held = KeyboardLayout.held(layerID: layer.id)
        VStack(spacing: Self.gap) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                let rowSlots = Self.slots(row)
                let units = rowSlots.reduce(0) { $0 + $1[0].width }
                let unit = (width - 24 - Self.gap * CGFloat(rowSlots.count - 1)) / CGFloat(units)
                HStack(spacing: Self.gap) {
                    ForEach(Array(rowSlots.enumerated()), id: \.offset) { _, slot in
                        let slotWidth = unit * CGFloat(slot[0].width)
                        if slot.count == 1 {
                            cap(slot[0], held: held, width: slotWidth, height: capHeight)
                        } else {
                            VStack(spacing: 2) {
                                ForEach(Array(slot.enumerated()), id: \.offset) { _, c in
                                    cap(c, held: held, width: slotWidth,
                                        height: (capHeight - 2) / CGFloat(slot.count))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        // The palette has no bg_dim: the well is bg0 with a bg1 rim, so the
        // bg1 caps stand on it (in light the rim is `border`: bg1 can't be seen).
        .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.capLine(dark: theme.bg1), lineWidth: 1))
    }

    /// A row's slots: one cap each, except up and down, which share one.
    private static func slots(_ row: [KeyboardLayout.Cap]) -> [[KeyboardLayout.Cap]] {
        var result: [[KeyboardLayout.Cap]] = []
        for cap in row {
            if cap.stacked, let last = result.last?.last, last.stacked {
                result[result.count - 1].append(cap)
            } else {
                result.append([cap])
            }
        }
        return result
    }

    @ViewBuilder
    private func cap(_ cap: KeyboardLayout.Cap, held: Set<Modifier>, width: CGFloat, height: CGFloat) -> some View {
        let isCaps = cap.name == nil && cap.modifier == nil && cap.legend == "caps"
        // Hyper is Caps Lock held; other layers light their modifier caps.
        let isHeld = layer.id == "hyper" ? isCaps : cap.modifier.map(held.contains) ?? false
        let legend = isCaps ? (layer.id == "hyper" ? "⇪ hyper" : "⇪") : cap.legend
        if let name = cap.name {
            named(cap, name, legend, width, height)
        } else {
            KeyCapView(legend: legend, binding: nil, isModifier: true, held: isHeld, focused: false,
                       width: width, height: height)
        }
    }
}
