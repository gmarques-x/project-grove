import Foundation
import Testing
@testable import GroveKeysCore

/// What the Wi-Fi dropdown's Bluetooth section shows, and when the reader
/// reads (spec 2026-11-13-bar-wifi-bluetooth-design).
struct BluetoothSectionTests {
    private let headphones = BluetoothDevice(id: "00:00:00:00:00:01", name: "Headphones", kind: .headphones, battery: 60)

    @Test func devicesWhenOn() {
        let content = BluetoothSectionContent(state: BluetoothState(power: true, connected: [headphones]),
                                              permission: .allowed)
        #expect(content == .devices([headphones]))
        #expect(content.switchOn && content.switchEnabled && content.showsSwitch)
    }

    @Test func onWithNothingConnected() {
        let content = BluetoothSectionContent(state: BluetoothState(power: true, connected: []), permission: .allowed)
        #expect(content == .devices([]))
        #expect(content.line == "No devices connected")
    }

    /// "Bluetooth is off" only when the controller says off.
    @Test func offOnlyWhenTheControllerSaysOff() {
        let off = BluetoothSectionContent(state: BluetoothState(power: false, connected: []), permission: .allowed)
        #expect(off == .off)
        #expect(off.line == "Bluetooth is off")
        #expect(!off.switchOn && off.switchEnabled && off.showsSwitch)
        // Not asked yet is not refused.
        #expect(BluetoothSectionContent(state: BluetoothState(power: false, connected: []),
                                        permission: .undetermined) == .off)
    }

    /// Unknown power (no controller, unreadable) says nothing, and the switch
    /// can't be used: it would guess.
    @Test func unknownPowerShowsTheHeaderOnly() {
        for permission in [BluetoothPermission.allowed, .undetermined] {
            let content = BluetoothSectionContent(state: BluetoothState(power: nil, connected: []), permission: permission)
            #expect(content == .unknown)
            #expect(content.line == nil)
            #expect(content.showsSwitch && !content.switchEnabled && !content.switchOn)
        }
        let reading = BluetoothSectionContent(state: nil, permission: .allowed)
        #expect(reading == .reading)
        #expect(reading.line == nil)
        #expect(reading.showsSwitch && !reading.switchEnabled)
    }

    /// Refused: the section says so (with its button), whatever was read,
    /// and has no switch (Grove Keys may not use Bluetooth, and never asks again).
    @Test func refusedSaysSo() {
        for state in [nil, BluetoothState(power: nil, connected: []), BluetoothState(power: false, connected: []),
                      BluetoothState(power: true, connected: [headphones])] {
            let content = BluetoothSectionContent(state: state, permission: .refused)
            #expect(content == .refused)
            #expect(content.line == "Grove Keys needs Bluetooth permission")
            #expect(!content.showsSwitch && !content.switchEnabled)
        }
    }

    @Test func batteryText() {
        #expect(headphones.batteryText == "60%")
        #expect(BluetoothDevice(id: "m", name: "Mouse", kind: .mouse, battery: nil).batteryText == nil)
    }
}

struct BluetoothPaceTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A wake and an overdue timer gave two readings in a row: the second,
    /// under 5 s after the first finished, is skipped; a forced one (after the
    /// switch) never is.
    @Test func skipsAReadingSoonAfterTheLast() {
        var pace = BluetoothPace()
        #expect(pace.due(at: start, force: false))
        _ = pace.finished(at: start, failure: false)
        #expect(!pace.due(at: start.addingTimeInterval(1), force: false))
        #expect(!pace.due(at: start.addingTimeInterval(4.9), force: false))
        #expect(pace.due(at: start.addingTimeInterval(1), force: true))
        #expect(pace.due(at: start.addingTimeInterval(5), force: false))
        #expect(BluetoothPace.gap == 5)
    }

    /// A failed reading is logged once until one succeeds.
    @Test func logsAFailureOnceUntilASuccess() {
        var pace = BluetoothPace()
        let logged = [true, true, true, false, true].enumerated().map { index, failure in
            pace.finished(at: start.addingTimeInterval(Double(index) * 30), failure: failure)
        }
        #expect(logged == [true, false, false, false, true])
    }

    /// A failure still counts as a reading for the gap: a broken
    /// system_profiler isn't run twice in a row either.
    @Test func aFailureCountsForTheGap() {
        var pace = BluetoothPace()
        _ = pace.finished(at: start, failure: true)
        #expect(!pace.due(at: start.addingTimeInterval(2), force: false))
    }
}
