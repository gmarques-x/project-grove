import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// A cap's place in a `KeyboardGrid`: its frame, and for the ISO Return the
/// part in the row under it.
struct CapSize {
    var width: CGFloat
    var height: CGFloat
    var lower: KeyCapShape.Lower?
    /// For hit-testing the whole cap.
    var outline: KeyCapShape { KeyCapShape(lower: lower) }
}

/// The drawn MacBook keyboard for one layer (mockup §1 and §3) in the
/// keyboard's shape (ANSI or ISO): rows of caps on a well, each showing what
/// it types on the current input source (`legends`). Modifier caps are drawn
/// here (lit for the layer's held modifiers); named keys come from `named`,
/// so the Keyboard tab can make them clickable and the cheat sheet leaves
/// them plain. The ISO Return is one cap, given to `named` from its top part
/// with the part under it in `size.lower`.
struct KeyboardGrid<Named: View>: View {
    let layer: Layer
    let shape: KeyboardShape
    let legends: Legends
    let width: CGFloat
    let capHeight: CGFloat
    @ViewBuilder let named: (_ cap: KeyboardLayout.Cap, _ name: String, _ legend: Legend, _ size: CapSize) -> Named
    @Environment(\.theme) private var theme

    static var gap: CGFloat { 6 }

    var body: some View {
        let held = KeyboardLayout.held(layerID: layer.id)
        let rows = KeyboardLayout.rows(for: shape)
        VStack(spacing: Self.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                let rowSlots = Self.slots(row)
                let unit = self.unit(rowSlots)
                HStack(spacing: Self.gap) {
                    ForEach(Array(rowSlots.enumerated()), id: \.offset) { _, slot in
                        let slotWidth = unit * CGFloat(slot[0].width)
                        if slot[0].tall == .bottom {
                            // Drawn by the cap's top part, from the row above.
                            Color.clear.frame(width: slotWidth, height: capHeight)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        } else if slot.count == 1 {
                            cap(slot[0], held: held,
                                size: CapSize(width: slotWidth, height: capHeight,
                                              lower: slot[0].tall == .top ? lower(below: r, in: rows) : nil))
                        } else {
                            VStack(spacing: 2) {
                                ForEach(Array(slot.enumerated()), id: \.offset) { _, c in
                                    cap(c, held: held, size: CapSize(width: slotWidth,
                                                                     height: (capHeight - 2) / CGFloat(slot.count)))
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
        .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.card))
        .overlay(RoundedRectangle(cornerRadius: GroveRadius.card).strokeBorder(theme.capLine(dark: theme.bg1), lineWidth: 1))
    }

    /// Points per key unit in a row: every row is 14.5 units across the
    /// same width, less its gaps.
    private func unit(_ rowSlots: [[KeyboardLayout.Cap]]) -> CGFloat {
        let units = rowSlots.reduce(0) { $0 + $1[0].width }
        return (width - 24 - Self.gap * CGFloat(rowSlots.count - 1)) / CGFloat(units)
    }

    /// The ISO Return's part in the row under row `r`.
    private func lower(below r: Int, in rows: [[KeyboardLayout.Cap]]) -> KeyCapShape.Lower? {
        guard rows.indices.contains(r + 1), let part = rows[r + 1].first(where: { $0.tall == .bottom }) else { return nil }
        return KeyCapShape.Lower(width: unit(Self.slots(rows[r + 1])) * CGFloat(part.width), drop: Self.gap + capHeight)
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
    private func cap(_ cap: KeyboardLayout.Cap, held: Set<Modifier>, size: CapSize) -> some View {
        let isCaps = cap.name == nil && cap.modifier == nil && cap.legend == "caps"
        // Hyper is Caps Lock held; other layers light their modifier caps.
        let isHeld = layer.id == "hyper" ? isCaps : cap.modifier.map(held.contains) ?? false
        if let name = cap.name {
            // What the key types here; its name when it types nothing (tab,
            // return, the arrows, space).
            let legend = cap.keyCode.flatMap(legends.legend(keyCode:)) ?? Legend(base: cap.legend, shift: nil)
            named(cap, name, legend, size)
        } else {
            let legend = isCaps ? (layer.id == "hyper" ? "⇪ hyper" : "⇪") : cap.legend
            KeyCapView(legend: Legend(base: legend, shift: nil), binding: nil, isModifier: true, held: isHeld,
                       focused: false, width: size.width, height: size.height)
        }
    }
}
