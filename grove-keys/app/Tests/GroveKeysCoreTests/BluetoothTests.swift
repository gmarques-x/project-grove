import Foundation
import Testing
@testable import GroveKeysCore

/// `system_profiler SPBluetoothDataType -json`, anonymised by hand (the repo is
/// public): invented names, addresses 00:00:00:00:00:0N, no serials.
struct BluetoothTests {
    private func state(_ name: String) throws -> BluetoothState {
        BluetoothState.parse(systemProfilerJSON: Data(try fixture(name).utf8))
    }

    private func json(_ text: String) -> BluetoothState {
        BluetoothState.parse(systemProfilerJSON: Data(text.utf8))
    }

    @Test func parsesConnectedDevices() throws {
        let state = try state("bluetooth-on.json")
        #expect(state.power == true)
        #expect(state.connected == [
            BluetoothDevice(id: "00:00:00:00:00:01", name: "Headphones", kind: .headphones, battery: 60),
            BluetoothDevice(id: "00:00:00:00:00:02", name: "Keyboard", kind: .keyboard, battery: 45),
            BluetoothDevice(id: "00:00:00:00:00:03", name: "Mouse", kind: .mouse, battery: nil),
        ])
    }

    @Test func powerOff() throws {
        let state = try state("bluetooth-off.json")
        #expect(state.power == false)
        #expect(state.connected.isEmpty)
        #expect(BluetoothIcon.icon(for: state) == .off)
    }

    @Test(arguments: ["{}", "not json", "", "[]", #"{"SPBluetoothDataType": []}"#,
                      #"{"SPBluetoothDataType": [{"controller_properties": {}}]}"#])
    func missingControllerIsOff(_ text: String) {
        let state = json(text)
        #expect(state.power == nil)
        #expect(state.connected.isEmpty)
        #expect(BluetoothIcon.icon(for: state) == .off)
    }

    @Test func airPodsShowTheLowestBattery() {
        let state = json("""
            {"SPBluetoothDataType": [{
              "controller_properties": {"controller_state": "attrib_on"},
              "device_connected": [{"AirPods": {
                "device_address": "00:00:00:00:00:05",
                "device_batteryLevelLeft": "80%",
                "device_batteryLevelRight": "60%",
                "device_batteryLevelCase": "100%"
              }}]
            }]}
            """)
        #expect(state.connected.map(\.battery) == [60])
        #expect(state.connected.map(\.kind) == [.headphones])
    }

    @Test func caseAloneIsTheBattery() {
        let state = json("""
            {"SPBluetoothDataType": [{
              "controller_properties": {"controller_state": "attrib_on"},
              "device_connected": [{"Headphones": {"device_batteryLevelCase": "35%"}}]
            }]}
            """)
        #expect(state.connected.map(\.battery) == [35])
        // No address: the name stands in as the id.
        #expect(state.connected.map(\.id) == ["Headphones"])
    }

    @Test(arguments: [
        ("Headphones", "Gadget", BluetoothDevice.Kind.headphones),
        ("Headset", "Gadget", .headphones),
        ("Keyboard", "Gadget", .keyboard),
        ("Mouse", "Gadget", .mouse),
        ("Trackpad", "Gadget", .trackpad),
        ("Speaker", "Gadget", .speaker),
        ("Loudspeaker", "Gadget", .speaker),
        ("", "Magic Trackpad", .trackpad),
        ("", "Earbuds", .headphones),
        ("", "Gadget", .other),
    ])
    func kinds(minorType: String, name: String, kind: BluetoothDevice.Kind) {
        #expect(BluetoothDevice.Kind(minorType: minorType.isEmpty ? nil : minorType, name: name) == kind)
    }

    @Test func iconStates() throws {
        #expect(BluetoothIcon.icon(for: BluetoothState(power: nil, connected: [])) == .off)
        #expect(BluetoothIcon.icon(for: BluetoothState(power: false, connected: [])) == .off)
        #expect(BluetoothIcon.icon(for: BluetoothState(power: true, connected: [])) == .on)
        #expect(BluetoothIcon.icon(for: try state("bluetooth-on.json")) == .connected)
        #expect(BluetoothIcon.connected.rawValue == "connected")
    }
}
