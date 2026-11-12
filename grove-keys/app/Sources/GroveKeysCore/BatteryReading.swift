import Foundation

// The battery panel's readings and words (spec 2026-11-12-bar-panels-design
// §6). Pure: the app reads IOKit's dictionaries and hands them here.

/// What the battery panel shows of the battery, as read at one moment.
public struct BatteryReading: Equatable, Sendable {
    /// False on a Mac without a battery: nothing else means anything then.
    public var present = true
    /// The charge, 0...100, as the menu bar shows it.
    public var percent = 0
    /// Drawing from the adapter.
    public var onAdapter = false
    public var charging = false
    /// Full, as macOS says it ("Is Charged").
    public var charged = false
    /// macOS's estimate, in minutes; nil while it is still working one out.
    public var minutesToFull: Int?
    public var minutesToEmpty: Int?
    /// The adapter's rating.
    public var adapterWatts: Int?
    /// What the whole Mac draws right now.
    public var macWatts: Double?
    /// Maximum capacity against the design's, in percent.
    public var health: Int?
    public var cycles: Int?
    /// °C; nil on the Macs that don't publish it.
    public var celsius: Double?

    public init() {}

    /// No battery in this Mac.
    public static let none: BatteryReading = {
        var reading = BatteryReading()
        reading.present = false
        return reading
    }()

    /// From IOKit's three dictionaries:
    /// - `source`: the internal battery's `IOPSGetPowerSourceDescription`;
    ///   nil when the Mac has none.
    /// - `registry`: the `AppleSmartBattery` entry's properties (empty when
    ///   it can't be read: the details are left out, the charge stays).
    /// - `adapter`: `IOPSCopyExternalPowerAdapterDetails`.
    public init(source: [String: Any]?, registry: [String: Any], adapter: [String: Any]?) {
        guard let source, source["Is Present"] as? Bool ?? true else {
            self = .none
            return
        }
        let current = Self.int(source["Current Capacity"]) ?? 0
        let max = Self.int(source["Max Capacity"]) ?? 100
        percent = max > 0 ? min(100, Swift.max(0, Int((Double(current) * 100 / Double(max)).rounded()))) : 0
        onAdapter = source["Power Source State"] as? String == "AC Power"
        charging = source["Is Charging"] as? Bool ?? false
        charged = source["Is Charged"] as? Bool ?? false
        // -1 while macOS is calculating; 0 for the one that doesn't apply.
        minutesToFull = Self.int(source["Time to Full Charge"]).flatMap { $0 > 0 ? $0 : nil }
        minutesToEmpty = Self.int(source["Time to Empty"]).flatMap { $0 > 0 ? $0 : nil }
        if onAdapter { adapterWatts = Self.int(adapter?["Watts"]).flatMap { $0 > 0 ? $0 : nil } }
        macWatts = Self.macWatts(registry, onAdapter: onAdapter)
        cycles = Self.int(registry["CycleCount"]).flatMap { $0 >= 0 ? $0 : nil }
        health = Self.measuredHealth(registry)
        celsius = Self.celsius(registry)
    }

    /// The Mac's draw in watts. The power telemetry's `SystemLoad` (mW) is
    /// the whole Mac's, on the adapter or not. Without it, on battery, the
    /// battery's own current times its voltage is the same thing (mA × mV);
    /// on the adapter that product is only what goes into the battery, so
    /// nothing is said.
    static func macWatts(_ registry: [String: Any], onAdapter: Bool) -> Double? {
        if let telemetry = registry["PowerTelemetryData"] as? [String: Any],
           let load = int(telemetry["SystemLoad"]), load > 0 {
            return Double(load) / 1000
        }
        guard !onAdapter, let amperage = int(registry["Amperage"]), let voltage = int(registry["Voltage"]),
              amperage != 0, voltage > 0 else { return nil }
        return abs(Double(amperage)) * Double(voltage) / 1_000_000
    }

    /// The measured capacity over the design's (`AppleRawMaxCapacity` /
    /// `DesignCapacity`, at the entry's top level on Intel and inside its
    /// `BatteryData` on Apple silicon), in percent, at most 100. The stand-by
    /// for System Settings' own figure (`BatteryHealth.settingsFigure`).
    static func measuredHealth(_ registry: [String: Any]) -> Int? {
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        guard let raw = int(registry["AppleRawMaxCapacity"]) ?? int(data["AppleRawMaxCapacity"]),
              let design = int(registry["DesignCapacity"]) ?? int(data["DesignCapacity"]),
              raw > 0, design > 0 else { return nil }
        return min(100, Int((Double(raw) * 100 / Double(design)).rounded()))
    }

    /// `Temperature` is in hundredths of a degree Celsius, where published.
    static func celsius(_ registry: [String: Any]) -> Double? {
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        guard let hundredths = int(registry["Temperature"]) ?? int(data["Temperature"]), hundredths > 0
        else { return nil }
        return Double(hundredths) / 100
    }

    /// A number out of a property list, whatever width it was stored in.
    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    // MARK: Rules

    /// The bar's low level: this or less, and not charging, is drawn in red.
    public static let lowPercent = 20

    /// Low: at or under 20% and not charging.
    public var isLow: Bool { present && percent <= Self.lowPercent && !charging }

    /// Ignore Lid is refused on battery under 20%: a closed, running Mac
    /// would empty what is left.
    public var refusesIgnoreLid: Bool { present && !onAdapter && percent < Self.lowPercent }

    /// The charge as the meter draws it, 0...1.
    public var share: Double { Double(percent) / 100 }

    // MARK: Words

    /// The one sentence under the charge bar.
    public var sentence: String {
        guard present else { return "This Mac has no battery." }
        if charging {
            return "Charging · " + (minutesToFull.map { BatteryText.clock(minutes: $0) + " to full" } ?? "calculating…")
        }
        if onAdapter {
            return charged || percent >= 100 ? "Fully charged" : "Not charging · held at \(percent)%"
        }
        return "On battery · " + (minutesToEmpty.map { BatteryText.clock(minutes: $0) + " left" } ?? "calculating…")
    }

    /// "94 W adapter · Mac using 17.7 W"; on battery "Mac using 9.2 W"; nil
    /// when neither is known.
    public var power: String? {
        let parts = [adapterWatts.map { "\($0) W adapter" }, macWatts.map { "Mac using \(BatteryText.watts($0)) W" }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "100% · 96 cycles", or the half that is known.
    public var healthText: String? {
        let parts = [health.map { "\($0)%" }, cycles.map { $0 == 1 ? "1 cycle" : "\($0) cycles" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "31 °C".
    public var temperature: String? {
        celsius.map { "\(Int($0.rounded())) °C" }
    }
}

/// Numbers as the battery panel writes them: the same in every locale.
public enum BatteryText {
    /// Minutes as "4:20" (hours and two digits of minutes); "0:13" under an hour.
    public static func clock(minutes: Int) -> String {
        let minutes = max(0, minutes)
        let rest = minutes % 60
        return "\(minutes / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// Watts with one decimal and a point, whatever the locale: "17.7".
    public static func watts(_ watts: Double) -> String {
        guard watts.isFinite else { return "0.0" }
        let tenths = Int((max(0, watts) * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }
}

/// The battery's health as System Settings shows it.
public enum BatteryHealth {
    /// "Maximum Capacity: 100%" out of `system_profiler SPPowerDataType`:
    /// the figure of System Settings › Battery › Battery Health, which on
    /// Apple silicon is not in the registry (macOS smooths the measured
    /// capacity before showing it). nil when the line isn't there.
    public static func settingsFigure(systemProfiler output: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Maximum Capacity" else { continue }
            let digits = parts[1].trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && $0.isNumber }
            if let value = Int(digits), (0...100).contains(value) { return value }
        }
        return nil
    }
}
