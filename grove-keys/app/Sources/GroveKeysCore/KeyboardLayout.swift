/// The physical shape of the built-in keyboard.
public enum KeyboardShape: String, Sendable, CaseIterable {
    case ansi, iso

    /// Carbon's `kKeyboardISO`: the four-character code 'ISO ', what
    /// `KBGetLayoutType` returns for an ISO board. Its value is copied here
    /// so Core doesn't import Carbon.
    static let carbonISO: UInt32 = 0x4953_4F20

    /// From `KBGetLayoutType(LMGetKbdType())`: ISO for `kKeyboardISO`,
    /// ANSI for anything else (JIS and unknown included).
    public static func from(layoutType: UInt32) -> KeyboardShape {
        layoutType == carbonISO ? .iso : .ansi
    }
}

/// `[keyboard] shape` in keys.toml: absent means auto.
public enum KeyboardShapeSetting: String, Sendable, CaseIterable {
    case auto, iso, ansi

    public func resolved(detected: KeyboardShape) -> KeyboardShape {
        switch self {
        case .auto: return detected
        case .iso: return .iso
        case .ansi: return .ansi
        }
    }
}

/// The drawn MacBook keyboard (mockup §1), without the function row, in
/// either shape: ANSI (`rows`) or ISO.
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
        /// The macOS key code of a named cap; nil for modifiers, fn and caps.
        public var keyCode: UInt16?
        /// A part of the ISO Return, which spans rows 2 and 3: both parts
        /// are named `enter` and are one key.
        public var tall: Tall?

        public enum Tall: Sendable { case top, bottom }

        /// `keyCode` defaults to the name's (`KeyNames`).
        public init(name: String?, legend: String, width: Double = 1, modifier: Modifier? = nil,
                    stacked: Bool = false, keyCode: UInt16? = nil, tall: Tall? = nil) {
            self.name = name
            self.legend = legend
            self.width = width
            self.modifier = modifier
            self.stacked = stacked
            self.keyCode = keyCode ?? name.flatMap(KeyNames.code(for:))
            self.tall = tall
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

    private static let digits: [Cap] = "1234567890".map { key(String($0), String($0)) }

    private static let bottomRow: [Cap] = [
        mod(nil, "fn"), mod(.ctrl, "ctrl"), mod(.alt, "opt"), mod(.cmd, "cmd", 1.25),
        key("space", "", 5), mod(.cmd, "cmd", 1.25), mod(.alt, "opt"),
        key("left", "←"), Cap(name: "up", legend: "↑", stacked: true),
        Cap(name: "down", legend: "↓", stacked: true), key("right", "→"),
    ]

    /// The ANSI board.
    public static let rows: [[Cap]] = [
        [key("backtick", "`")] + digits
            + [key("minus", "-"), key("equal", "="), key("backspace", "delete", 1.5)],
        [key("tab", "tab", 1.5)] + letters("qwertyuiop")
            + [key("leftSquareBracket", "["), key("rightSquareBracket", "]"), key("backslash", "\\")],
        [mod(nil, "caps", 1.75)] + letters("asdfghjkl")
            + [key("semicolon", ";"), key("quote", "'"), key("enter", "return", 1.75)],
        [mod(.shift, "shift", 2.25)] + letters("zxcvbnm")
            + [key("comma", ","), key("period", "."), key("slash", "/"), mod(.shift, "shift", 2.25)],
        bottomRow,
    ]

    /// Apple's ISO MacBook board: `section` top left, a tall Return over
    /// rows 2–3 with `backslash` beside its bottom part, and `backtick`
    /// beside a short left Shift.
    public static let isoRows: [[Cap]] = [
        [key("section", "§")] + digits
            + [key("minus", "-"), key("equal", "="), key("backspace", "delete", 1.5)],
        [key("tab", "tab", 1.5)] + letters("qwertyuiop")
            + [key("leftSquareBracket", "["), key("rightSquareBracket", "]"),
               Cap(name: "enter", legend: "return", tall: .top)],
        [mod(nil, "caps", 1.75)] + letters("asdfghjkl")
            + [key("semicolon", ";"), key("quote", "'"), key("backslash", "\\"),
               Cap(name: "enter", legend: "", width: 0.75, tall: .bottom)],
        [mod(.shift, "shift", 1.25), key("backtick", "`")] + letters("zxcvbnm")
            + [key("comma", ","), key("period", "."), key("slash", "/"), mod(.shift, "shift", 2.25)],
        bottomRow,
    ]

    public static func rows(for shape: KeyboardShape) -> [[Cap]] {
        switch shape {
        case .ansi: return rows
        case .iso: return isoRows
        }
    }

    /// Every cap's key name. Bindings on other keys (Escape sits in the
    /// function row) are listed under the keyboard.
    public static let names: Set<String> = names(for: .ansi)

    public static func names(for shape: KeyboardShape) -> Set<String> {
        Set(rows(for: shape).flatMap { $0 }.compactMap(\.name))
    }

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

    private static func makeSlots(_ rows: [[Cap]]) -> [[Slot]] {
        rows.map { row in
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
    }

    private static let ansiSlots = makeSlots(rows)
    private static let isoSlots = makeSlots(isoRows)

    private static func slots(for shape: KeyboardShape) -> [[Slot]] {
        switch shape {
        case .ansi: return ansiSlots
        case .iso: return isoSlots
        }
    }

    /// The named cap next to `name` on the ANSI board; nil at an edge.
    public static func neighbor(of name: String, _ direction: Direction) -> String? {
        neighbor(of: name, direction, shape: .ansi)
    }

    /// The named cap next to `name` (arrows, Ctrl+H/J/K/L); nil at an edge.
    /// A key in more than one row (the ISO Return) is one stop: ←/→ move
    /// from its top part, ↑/↓ leave from over or under all of its parts.
    public static func neighbor(of name: String, _ direction: Direction, shape: KeyboardShape) -> String? {
        let slots = slots(for: shape)
        let rowsWithName = slots.indices.filter { r in slots[r].contains { $0.names.contains(name) } }
        guard let r = rowsWithName.first, let last = rowsWithName.last,
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
            let target = direction == .up ? r - 1 : last + 1
            guard slots.indices.contains(target) else { return nil }
            let parts = rowsWithName.compactMap { row in slots[row].first { $0.names.contains(name) } }
            let start = parts.map(\.start).min()!
            let end = parts.map(\.end).max()!
            return nearest(in: slots[target], to: (start + end) / 2)
        }
    }

    /// The named cap of `row` over or under `x` (in key units): the one
    /// `x` is in, else the nearest edge, the nearer centre breaking a tie.
    private static func nearest(in row: [Slot], to x: Double) -> String? {
        var best: (edge: Double, center: Double, name: String)?
        for other in row {
            guard let n = other.names.first, let n else { continue }
            let edge = x < other.start ? other.start - x : (x > other.end ? x - other.end : 0)
            let center = abs(other.center - x)
            if best == nil || edge < best!.edge || (edge == best!.edge && center < best!.center) {
                best = (edge, center, n)
            }
        }
        return best?.name
    }

    // MARK: The bindings under the keyboard

    /// The bindings without a cap ("not on the keyboard") are listed under
    /// the keyboard in this many columns, filled row by row.
    public static let extraColumns = 4

    /// `neighbor(of:_:)` with the listed bindings (`extras`, their keys in
    /// the order shown) joined on after the bottom row: ↓ from the bottom
    /// row goes to the first listed row, into the column under the cap; ↑
    /// from that row goes back to the cap over the column's middle; inside
    /// the list the arrows move by one cell and stop at its edges.
    public static func neighbor(of name: String, _ direction: Direction, extras: [String]) -> String? {
        neighbor(of: name, direction, extras: extras, shape: .ansi)
    }

    /// `neighbor(of:_:extras:)` on the board of `shape`.
    public static func neighbor(of name: String, _ direction: Direction, extras: [String],
                                shape: KeyboardShape) -> String? {
        let slots = slots(for: shape)
        let last = slots.count - 1
        let width = slots[last].last?.end ?? 1
        if let at = extras.firstIndex(of: name), !names(for: shape).contains(name) {
            let column = at % extraColumns
            switch direction {
            case .left: return column > 0 ? extras[at - 1] : nil
            case .right: return column < extraColumns - 1 && at + 1 < extras.count ? extras[at + 1] : nil
            case .down: return at + extraColumns < extras.count ? extras[at + extraColumns] : nil
            case .up:
                if at >= extraColumns { return extras[at - extraColumns] }
                return nearest(in: slots[last], to: (Double(column) + 0.5) / Double(extraColumns) * width)
            }
        }
        if let next = neighbor(of: name, direction, shape: shape) { return next }
        guard direction == .down, !extras.isEmpty,
              let slot = slots[last].first(where: { $0.names.contains(name) }) else { return nil }
        let column = min(Int(slot.center / width * Double(extraColumns)), extraColumns - 1)
        return extras[min(column, extras.count - 1)]
    }
}
