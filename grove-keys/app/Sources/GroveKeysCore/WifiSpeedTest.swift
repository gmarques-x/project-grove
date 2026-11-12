import Foundation

/// A speed test's result, from `/usr/bin/networkQuality -c` (JSON on
/// standard output when the test ends).
public struct WifiSpeedResult: Equatable, Sendable {
    /// The network's delay: the idle round trip when the tool gives it,
    /// else its responsiveness score.
    public enum Delay: Equatable, Sendable {
        case milliseconds(Double)
        /// Round trips a minute under load ("RPM"), labelled as such.
        case rpm(Double)
    }

    /// Bits a second.
    public var down: Double
    public var up: Double
    public var delay: Delay?

    public init(down: Double, up: Double, delay: Delay?) {
        self.down = down
        self.up = up
        self.delay = delay
    }

    /// Nil when the output isn't the tool's JSON or has no throughput (a
    /// test that was stopped, an error message).
    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? {
            guard let value = (object[key] as? NSNumber)?.doubleValue, value.isFinite, value >= 0 else { return nil }
            return value
        }
        guard let down = number("dl_throughput"), let up = number("ul_throughput") else { return nil }
        self.down = down
        self.up = up
        if let rtt = number("base_rtt"), rtt > 0 {
            delay = .milliseconds(rtt)
        } else if let rpm = number("responsiveness") ?? number("dl_responsiveness"), rpm > 0 {
            delay = .rpm(rpm)
        } else {
            delay = nil
        }
    }

    /// "412 Mbps", "38 Mbps", "0.4 Mbps", "1.2 Gbps": megabits from the
    /// start (a kilobit link is "0.1 Mbps"), locale-free.
    public static func format(bitsPerSecond: Double) -> String {
        guard bitsPerSecond.isFinite, bitsPerSecond > 0 else { return "0 Mbps" }
        if bitsPerSecond < 9_950_000 {
            let tenths = Int((bitsPerSecond / 100_000).rounded())
            return "\(tenths / 10).\(tenths % 10) Mbps"
        }
        // From kilobits, so megabits are the scale's first step up.
        return WifiRate.scaled(bitsPerSecond / 1000, units: ["Mbps", "Gbps"], wholeFirst: true)
    }

    public var downText: String { Self.format(bitsPerSecond: down) }
    public var upText: String { Self.format(bitsPerSecond: up) }

    /// "12 ms" or "916 RPM"; nil without either.
    public var delayText: String? {
        switch delay {
        case .milliseconds(let ms): return "\(max(1, Int(ms.rounded()))) ms"
        case .rpm(let rpm): return "\(Int(rpm.rounded())) RPM"
        case nil: return nil
        }
    }
}

/// Where a speed test stands.
public enum WifiSpeedState: Equatable, Sendable {
    case idle
    case running(since: Date)
    case result(WifiSpeedResult, at: Date, network: String)
    case failed(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// A result belongs to the network it was measured on: on another one
    /// it (or a failure) is forgotten. A running test is left alone.
    public func on(network: String) -> WifiSpeedState {
        switch self {
        case .result(_, _, let measured) where measured != network: return .idle
        default: return self
        }
    }
}

public enum WifiSpeedTest {
    public static let tool = "/usr/bin/networkQuality"
    /// Download and upload together (the tool's default): 15 s as measured.
    /// One after the other (`-s`) takes 20 to 29 s and doesn't say through a
    /// pipe which half is running.
    public static let arguments = ["-c"]
    /// What a run takes, for the bar.
    public static let expected: TimeInterval = 15
    /// A run that hasn't ended by then is stopped.
    public static let timeout: TimeInterval = 60
    public static let failureLine = "The speed test didn't finish"

    /// The bar: the time passed against `expected`, held just short of full
    /// while the tool is still at it.
    public static func progress(elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return min(0.97, elapsed / expected)
    }

    /// "just now", "2 min ago", "3 h ago".
    public static func age(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }
}
