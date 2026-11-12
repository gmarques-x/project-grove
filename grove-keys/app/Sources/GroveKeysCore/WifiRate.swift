import Foundation

/// The Wi-Fi panel's rates: bytes a second from an interface's counters, the
/// last minute of them, and how they are written. Pure; the counters are
/// read by the panel's model.
public enum WifiRate {
    /// "348 KB/s", "2.1 MB/s", "1.2 GB/s": decimal units (as macOS counts
    /// network traffic), whole kilobytes, one decimal from a megabyte up to a
    /// hundred. The same text in every locale: the decimal mark is a point.
    public static func format(_ bytesPerSecond: Double) -> String {
        scaled(bytesPerSecond, units: ["KB/s", "MB/s", "GB/s"], wholeFirst: true)
    }

    /// `value` in thousands: the first unit is value / 1000. `wholeFirst`:
    /// the first unit never takes a decimal (kilobytes).
    static func scaled(_ value: Double, units: [String], wholeFirst: Bool) -> String {
        guard value.isFinite, value > 0 else { return "0 \(units[0])" }
        var amount = value / 1000
        var index = 0
        // 999.5 would be written "1000": it is the next unit's 1.0.
        while index < units.count - 1, amount >= 999.5 {
            amount /= 1000
            index += 1
        }
        if (index == 0 && wholeFirst) || amount >= 99.95 {
            return "\(Int(amount.rounded())) \(units[index])"
        }
        // Tenths, in whole numbers: no formatter, so no locale.
        let tenths = Int((amount * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(units[index])"
    }

    /// How far a byte counter moved between two readings. A counter that
    /// went backwards wrapped at 32 bits when both readings fit in 32 bits
    /// (`if_data`'s counters); anything else is a counter that started again
    /// (the interface was reset): nothing to count.
    public static func delta(from previous: UInt64, to current: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        let wrap = UInt64(UInt32.max) + 1
        guard previous < wrap else { return 0 }
        return current + wrap - previous
    }

    /// Bytes a second between two readings `seconds` apart; 0 when no time
    /// passed.
    public static func rate(from previous: UInt64, to current: UInt64, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(delta(from: previous, to: current)) / seconds
    }
}

/// The last minute of down and up rates, a reading a second, oldest first.
/// Where nothing was read yet there is no point: `nil`, drawn as absent.
public struct WifiHistory: Equatable, Sendable {
    public static let length = 60
    /// A chart's top is never under this (bytes a second), so an idle
    /// minute's few packets aren't stretched to the full height.
    public static let floor = 50_000.0

    public private(set) var down: [Double?]
    public private(set) var up: [Double?]

    public init() {
        down = Array(repeating: nil, count: Self.length)
        up = down
    }

    /// From readings, newest last (the sample render's).
    public init(down: [Double], up: [Double]) {
        self.init()
        for (d, u) in zip(down, up) { add(down: d, up: u) }
    }

    public mutating func add(down d: Double, up u: Double) {
        down.removeFirst()
        down.append(d)
        up.removeFirst()
        up.append(u)
    }

    /// Both lines on one scale, 0...1: against the largest reading of either
    /// (or `floor`), so down and up can be compared.
    public var normalized: (down: [Double?], up: [Double?]) {
        let top = max(Self.floor, (down + up).compactMap { $0 }.max() ?? 0)
        func scale(_ values: [Double?]) -> [Double?] { values.map { $0.map { min(1, max(0, $0 / top)) } } }
        return (scale(down), scale(up))
    }

    /// The runs of readings that follow each other, as index ranges: a line
    /// is drawn through each run and nothing between them.
    public static func runs(_ values: [Double?]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for (index, value) in values.enumerated() {
            if value != nil, start == nil { start = index }
            if value == nil, let s = start {
                runs.append(s..<index)
                start = nil
            }
        }
        if let start { runs.append(start..<values.count) }
        return runs
    }
}
