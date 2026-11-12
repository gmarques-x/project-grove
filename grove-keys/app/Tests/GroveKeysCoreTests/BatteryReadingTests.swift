import Foundation
import Testing
@testable import GroveKeysCore

/// The bar's own captures (`ioreg`, `pmset`, `system_profiler` on the
/// owner's MacBook), shared with the bats tests.
private func barFixture(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // GroveKeysCoreTests
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // grove-keys
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent("grove-dotfiles/tests/fixtures/sketchybar/\(name)"),
                      encoding: .utf8)
}

/// IOKit's dictionaries with the numbers of `ioreg-battery.txt` (99%,
/// finishing its charge on a 94 W adapter) and of the same Mac read through
/// `IOPSGetPowerSourceDescription` on 2026-11-12.
private enum Captured {
    static var registry: [String: Any] { [
        "CycleCount": 96, "Amperage": 312, "Voltage": 13343, "IsCharging": true, "ExternalConnected": true,
        "CurrentCapacity": 99, "MaxCapacity": 100,
        "BatteryData": ["AppleRawMaxCapacity": 5493, "DesignCapacity": 5760, "NominalChargeCapacity": 5637],
        "PowerTelemetryData": ["SystemLoad": 7730, "SystemPowerIn": 11906, "BatteryPower": 4176],
    ] }
    static var adapter: [String: Any] { ["Watts": 94, "Name": "140W USB-C Power Adapter"] }

    static func source(_ changes: [String: Any] = [:]) -> [String: Any] {
        var source: [String: Any] = [
            "Current Capacity": 99, "Max Capacity": 100, "Is Charging": true, "Is Charged": false, "Is Present": true,
            "Power Source State": "AC Power", "Time to Empty": 0, "Time to Full Charge": 13,
            "Type": "InternalBattery",
        ]
        source.merge(changes) { $1 }
        return source
    }

    static var onBattery: [String: Any] { source([
        "Current Capacity": 64, "Is Charging": false, "Power Source State": "Battery Power", "Time to Empty": 260,
        "Time to Full Charge": 0,
    ]) }
}

@Suite struct BatteryReadingTests {
    @Test func chargingOnTheAdapter() {
        let reading = BatteryReading(source: Captured.source(), registry: Captured.registry, adapter: Captured.adapter)
        #expect(reading.present)
        #expect(reading.percent == 99)
        #expect(reading.sentence == "Charging · 0:13 to full")
        #expect(reading.power == "94 W adapter · Mac using 7.7 W")
        #expect(reading.healthText == "95% · 96 cycles")
        #expect(reading.temperature == nil)
        #expect(!reading.isLow)
        #expect(!reading.refusesIgnoreLid)
    }

    @Test func onBattery() {
        var registry = Captured.registry
        registry["PowerTelemetryData"] = nil
        registry["Amperage"] = -752
        registry["Voltage"] = 12234
        let reading = BatteryReading(source: Captured.onBattery, registry: registry, adapter: Captured.adapter)
        #expect(reading.percent == 64)
        #expect(reading.sentence == "On battery · 4:20 left")
        // No adapter's watts on battery, even if a stale dictionary is handed in.
        #expect(reading.power == "Mac using 9.2 W")
    }

    @Test func theMacsDrawPrefersTheTelemetry() {
        #expect(BatteryReading.macWatts(Captured.registry, onAdapter: true) == 7.73)
        // On the adapter the battery's current is its charge, not the Mac's draw.
        #expect(BatteryReading.macWatts(["Amperage": 312, "Voltage": 13343], onAdapter: true) == nil)
        #expect(BatteryReading.macWatts(["Amperage": 0, "Voltage": 13298], onAdapter: false) == nil)
        #expect(BatteryReading.macWatts([:], onAdapter: false) == nil)
        // Full on the adapter (read live): the telemetry still says what the Mac draws.
        let full: [String: Any] = ["Amperage": 0, "Voltage": 13298, "PowerTelemetryData": ["SystemLoad": 5499]]
        #expect(BatteryReading.macWatts(full, onAdapter: true) == 5.499)
    }

    @Test func sentences() {
        func sentence(_ changes: [String: Any]) -> String {
            BatteryReading(source: Captured.source(changes), registry: [:], adapter: nil).sentence
        }
        #expect(sentence(["Time to Full Charge": -1]) == "Charging · calculating…")
        #expect(sentence(["Current Capacity": 100, "Is Charging": false, "Is Charged": true, "Time to Full Charge": 0])
            == "Fully charged")
        #expect(sentence(["Current Capacity": 100, "Is Charging": false]) == "Fully charged")
        #expect(sentence(["Current Capacity": 80, "Is Charging": false, "Time to Full Charge": 0])
            == "Not charging · held at 80%")
        let battery: [String: Any] = ["Is Charging": false, "Power Source State": "Battery Power"]
        #expect(sentence(battery.merging(["Time to Empty": -1]) { $1 }) == "On battery · calculating…")
        #expect(sentence(battery.merging(["Time to Empty": 41]) { $1 }) == "On battery · 0:41 left")
        #expect(sentence(battery.merging(["Time to Empty": 536]) { $1 }) == "On battery · 8:56 left")
    }

    @Test func lowIsTwentyOrLessAndNotCharging() {
        func reading(_ percent: Int, charging: Bool, adapter: Bool) -> BatteryReading {
            BatteryReading(source: Captured.source([
                "Current Capacity": percent, "Is Charging": charging,
                "Power Source State": adapter ? "AC Power" : "Battery Power",
            ]), registry: [:], adapter: nil)
        }
        #expect(reading(20, charging: false, adapter: false).isLow)
        #expect(!reading(21, charging: false, adapter: false).isLow)
        #expect(!reading(12, charging: true, adapter: true).isLow)
        // Plugged into an adapter too weak to charge: still low.
        #expect(reading(12, charging: false, adapter: true).isLow)

        #expect(reading(19, charging: false, adapter: false).refusesIgnoreLid)
        #expect(!reading(20, charging: false, adapter: false).refusesIgnoreLid)
        #expect(!reading(5, charging: true, adapter: true).refusesIgnoreLid)
        #expect(!BatteryReading.none.refusesIgnoreLid)
        #expect(!BatteryReading.none.isLow)
    }

    @Test func noBattery() {
        #expect(BatteryReading(source: nil, registry: [:], adapter: Captured.adapter) == .none)
        #expect(BatteryReading(source: ["Is Present": false], registry: [:], adapter: nil) == .none)
        #expect(BatteryReading.none.sentence == "This Mac has no battery.")
        #expect(BatteryReading.none.power == nil)
        #expect(BatteryReading.none.healthText == nil)
    }

    @Test func percentIsOfTheMaximum() {
        func percent(_ current: Int, _ max: Int) -> Int {
            BatteryReading(source: Captured.source(["Current Capacity": current, "Max Capacity": max]), registry: [:],
                           adapter: nil).percent
        }
        #expect(percent(99, 100) == 99)
        #expect(percent(2719, 5438) == 50)
        #expect(percent(120, 100) == 100)
        #expect(percent(5, 0) == 0)
    }

    @Test func healthAndTemperature() {
        // Intel: at the entry's top level, with the temperature.
        let intel: [String: Any] = ["AppleRawMaxCapacity": 4500, "DesignCapacity": 5000, "Temperature": 3098,
                                    "CycleCount": 1]
        let reading = BatteryReading(source: Captured.source(), registry: intel, adapter: nil)
        #expect(reading.healthText == "90% · 1 cycle")
        #expect(reading.temperature == "31 °C")
        #expect(BatteryReading.measuredHealth(["AppleRawMaxCapacity": 5800, "DesignCapacity": 5760]) == 100)
        #expect(BatteryReading.measuredHealth(["DesignCapacity": 5760]) == nil)
        #expect(BatteryReading.measuredHealth(["AppleRawMaxCapacity": 5800, "DesignCapacity": 0]) == nil)
        #expect(BatteryReading.celsius(["Temperature": 0]) == nil)

        var known = reading
        known.health = 100
        known.cycles = 96
        #expect(known.healthText == "100% · 96 cycles")
        known.cycles = nil
        #expect(known.healthText == "100%")
    }

    @Test func settingsFigureFromSystemProfiler() throws {
        #expect(BatteryHealth.settingsFigure(systemProfiler: try barFixture("system_profiler-power.txt")) == 100)
        #expect(BatteryHealth.settingsFigure(systemProfiler: "      Maximum Capacity: 87%\n") == 87)
        #expect(BatteryHealth.settingsFigure(systemProfiler: "Power:\n\n    Hardware Configuration:\n") == nil)
        #expect(BatteryHealth.settingsFigure(systemProfiler: "Maximum Capacity: n/a") == nil)
        #expect(BatteryHealth.settingsFigure(systemProfiler: "") == nil)
    }

    @Test func numbersAreTheSameInEveryLocale() {
        #expect(BatteryText.watts(17.7) == "17.7")
        #expect(BatteryText.watts(9.2) == "9.2")
        #expect(BatteryText.watts(12) == "12.0")
        #expect(BatteryText.watts(0.04) == "0.0")
        #expect(BatteryText.watts(9.96) == "10.0")
        #expect(BatteryText.watts(-3) == "0.0")
        #expect(BatteryText.watts(.nan) == "0.0")
        #expect(BatteryText.clock(minutes: 13) == "0:13")
        #expect(BatteryText.clock(minutes: 260) == "4:20")
        #expect(BatteryText.clock(minutes: 60) == "1:00")
        #expect(BatteryText.clock(minutes: 605) == "10:05")
        #expect(BatteryText.clock(minutes: -4) == "0:00")
    }
}

@Suite struct BatteryIgnoreLidTests {
    @Test func sleepDisabledFromPmset() throws {
        #expect(IgnoreLid.sleepDisabled(pmset: try barFixture("pmset-g.txt")) == false)
        // The same Mac with Ignore Lid on (`pmset -g`, 2026-11-12).
        let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby              1\n"
        #expect(IgnoreLid.sleepDisabled(pmset: on) == true)
        #expect(IgnoreLid.sleepDisabled(pmset: "Currently in use:\n standby              1\n") == nil)
        #expect(IgnoreLid.sleepDisabled(pmset: " SleepDisabled\t\tmaybe\n") == nil)
        #expect(IgnoreLid.sleepDisabled(pmset: "") == nil)
    }

    @Test func theCommandGoesThroughTheSystemsPrompt() {
        #expect(IgnoreLid.osascript == "/usr/bin/osascript")
        #expect(IgnoreLid.arguments(on: true)
            == ["-e", "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges"])
        #expect(IgnoreLid.arguments(on: false)
            == ["-e", "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges"])
    }

    @Test func aDismissedPromptIsNotAnError() {
        #expect(IgnoreLid.outcome(status: 0, output: "") == .done)
        #expect(IgnoreLid.outcome(status: 1, output: "0:79: execution error: User canceled. (-128)\n") == .cancelled)
        #expect(IgnoreLid.outcome(status: 1, output: "0:79: execution error: Cancelado pelo usuário. (-128)\n")
            == .cancelled)
        #expect(IgnoreLid.outcome(status: -1, output: "", timedOut: true) == .cancelled)
        #expect(IgnoreLid.outcome(status: 1, output: "0:79: execution error: pmset: not found (127)\n")
            == .failed("0:79: execution error: pmset: not found (127)"))
        #expect(IgnoreLid.outcome(status: 2, output: "") == .failed("pmset could not be run (status 2)"))
    }
}
