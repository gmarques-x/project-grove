/// The drawn MacBook ANSI keyboard (mockup §1), without the function row.
public enum KeyboardLayout {
    public struct Cap: Sendable, Equatable {
        /// AeroSpace key name; nil for modifiers, fn and caps.
        public var name: String?
        public var legend: String
        /// In key units; rows 1–4 add up to 14.5.
        public var width: Double
        public var modifier: Modifier?
        /// Up and down share one slot, half height each, as on a MacBook.
        public var stacked: Bool

        public init(name: String?, legend: String, width: Double = 1, modifier: Modifier? = nil,
                    stacked: Bool = false) {
            self.name = name
            self.legend = legend
            self.width = width
            self.modifier = modifier
            self.stacked = stacked
        }
    }

    private static func key(_ name: String, _ legend: String, _ width: Double = 1) -> Cap {
        Cap(name: name, legend: legend, width: width)
    }

    private static func letters(_ s: String) -> [Cap] {
        s.map { key(String($0), String($0)) }
    }

    private static func mod(_ m: Modifier?, _ legend: String, _ width: Double = 1) -> Cap {
        Cap(name: nil, legend: legend, width: width, modifier: m)
    }

    public static let rows: [[Cap]] = [
        [key("backtick", "`")] + "1234567890".map { key(String($0), String($0)) }
            + [key("minus", "-"), key("equal", "="), key("backspace", "delete", 1.5)],
        [key("tab", "tab", 1.5)] + letters("qwertyuiop")
            + [key("leftSquareBracket", "["), key("rightSquareBracket", "]"), key("backslash", "\\")],
        [mod(nil, "caps", 1.75)] + letters("asdfghjkl")
            + [key("semicolon", ";"), key("quote", "'"), key("enter", "return", 1.75)],
        [mod(.shift, "shift", 2.25)] + letters("zxcvbnm")
            + [key("comma", ","), key("period", "."), key("slash", "/"), mod(.shift, "shift", 2.25)],
        [mod(nil, "fn"), mod(.ctrl, "ctrl"), mod(.alt, "opt"), mod(.cmd, "cmd", 1.25),
         key("space", "", 5), mod(.cmd, "cmd", 1.25), mod(.alt, "opt"),
         key("left", "←"), Cap(name: "up", legend: "↑", stacked: true),
         Cap(name: "down", legend: "↓", stacked: true), key("right", "→")],
    ]

    /// Key names AeroSpace knows that have no cap here (Escape sits in the
    /// function row); the Keyboard tab lists their bindings under the keyboard.
    public static let offKeyboard: Set<String> = ["esc"]

    /// The modifiers a layer holds, from its `Layers` id: "hyper", "alt",
    /// "alt-shift", "ctrl-alt"…, "none", "mode:<name>" (none held).
    public static func held(layerID: String) -> Set<Modifier> {
        if layerID == "hyper" { return Set(Modifier.allCases) }
        if layerID == "none" || layerID.hasPrefix("mode:") { return [] }
        return Set(layerID.split(separator: "-").compactMap { Modifier(rawValue: String($0)) })
    }

    /// The AeroSpace mode a layer's bindings live in.
    public static func mode(layerID: String) -> String {
        layerID.hasPrefix("mode:") ? String(layerID.dropFirst(5)) : "main"
    }

    /// The AeroSpace shortcut a bare key writes in a layer: "hyper-t", "alt-1", "r".
    public static func shortcut(layerID: String, key: String) -> String {
        Shortcut(modifiers: held(layerID: layerID), key: key).aerospace
    }

    // MARK: Keyboard navigation

    public enum Direction: Sendable { case left, right, up, down }

    /// Where the focus starts.
    public static let firstKey = "1"

    /// One slot of a row: a cap, or the up/down pair stacked in one slot.
    private struct Slot {
        var names: [String?]
        var start: Double
        var end: Double
        var center: Double { (start + end) / 2 }
    }

    private static let slots: [[Slot]] = rows.map { row in
        var result: [Slot] = []
        var x = 0.0
        var previousStacked = false
        for cap in row {
            if cap.stacked, previousStacked {
                result[result.count - 1].names.append(cap.name)
            } else {
                result.append(Slot(names: [cap.name], start: x, end: x + cap.width))
                x += cap.width
            }
            previousStacked = cap.stacked
        }
        return result
    }

    /// The named cap next to `name` (arrows, Ctrl+H/J/K/L); nil at an edge.
    public static func neighbor(of name: String, _ direction: Direction) -> String? {
        guard let r = slots.firstIndex(where: { $0.contains { $0.names.contains(name) } }),
              let s = slots[r].firstIndex(where: { $0.names.contains(name) }) else { return nil }
        let slot = slots[r][s]
        let level = slot.names.firstIndex(of: name)!
        switch direction {
        case .left, .right:
            let step = direction == .left ? -1 : 1
            let i = s + step
            if slots[r].indices.contains(i) {
                // A modifier cap stops the move.
                return slots[r][i].names.first ?? nil
            }
            return nil
        case .up, .down:
            let step = direction == .up ? -1 : 1
            if slot.names.indices.contains(level + step) { return slot.names[level + step] }
            guard slots.indices.contains(r + step) else { return nil }
            var best: (edge: Double, center: Double, name: String)?
            for other in slots[r + step] {
                guard let n = other.names.first, let n else { continue }
                let x = slot.center
                let edge = x < other.start ? other.start - x : (x > other.end ? x - other.end : 0)
                let center = abs(other.center - x)
                if best == nil || edge < best!.edge || (edge == best!.edge && center < best!.center) {
                    best = (edge, center, n)
                }
            }
            return best?.name
        }
    }
}
