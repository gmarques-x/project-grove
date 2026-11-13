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
                      #"{"SPBluetoothDataType": [{"controller_properties": {}}]}"#,
                      // A section without controller_properties.
                      #"{"SPBluetoothDataType": [{}]}"#])
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

    @Test func oneBadEntryKeepsTheOthers() {
        let state = json("""
            {"SPBluetoothDataType": [{
              "controller_properties": {"controller_state": "attrib_on"},
              "device_connected": [
                {"Keyboard": {"device_address": "00:00:00:00:00:02"}},
                "not a device",
                {"Mouse": {"device_address": "00:00:00:00:00:03"}}
              ]
            }]}
            """)
        #expect(state.connected.map(\.name) == ["Keyboard", "Mouse"])
    }

    @Test(arguments: [("80 %", 80), (" 45% ", 45), ("100", 100), ("n/a", nil)] as [(String, Int?)])
    func batteryWithSpaces(_ text: String, _ level: Int?) {
        let state = json("""
            {"SPBluetoothDataType": [{
              "controller_properties": {"controller_state": "attrib_on"},
              "device_connected": [{"Mouse": {"device_batteryLevelMain": "\(text)"}}]
            }]}
            """)
        #expect(state.connected.map(\.battery) == [level])
    }

    @Test func sameNameWithoutAddressGetsUniqueIds() {
        let state = json("""
            {"SPBluetoothDataType": [{
              "controller_properties": {"controller_state": "attrib_on"},
              "device_connected": [
                {"Speaker": {}},
                {"Speaker": {}},
                {"Mouse": {"device_address": "00:00:00:00:00:03"}}
              ]
            }]}
            """)
        let ids = state.connected.map(\.id)
        #expect(Set(ids).count == 3)
        #expect(ids.first == "Speaker")
        #expect(ids.last == "00:00:00:00:00:03")
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

/// `$GROVE_STATE/bluetooth`, the bar's icon state.
struct BluetoothBarFileTests {
    @Test func pathIsBesideTheOtherState() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(BluetoothBarFile.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/bluetooth")
        #expect(BluetoothBarFile.url(environment: [:], home: home).path
            == "/Users/someone/.local/state/grove/bluetooth")
    }

    @Test func writesOnlyWhenTheIconChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = BluetoothBarFile.url(environment: ["GROVE_STATE": dir.path], home: URL(fileURLWithPath: "/nowhere"))

        // No folder yet: made, and the word written with a newline.
        #expect(try BluetoothBarFile.update(.on, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "on\n")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        // The same icon again: nothing written (the bar isn't redrawn every 30 s).
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.02)
        #expect(try !BluetoothBarFile.update(.on, at: url))
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)
        #expect(try BluetoothBarFile.update(.connected, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "connected\n")
        #expect(try BluetoothBarFile.update(.off, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "off\n")
        // nil removes the file (the bar then shows off); already gone is no change.
        #expect(try BluetoothBarFile.update(nil, at: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try !BluetoothBarFile.update(nil, at: url))
    }

    @Test func aFileLeftByAnotherRunCounts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = BluetoothBarFile.url(environment: ["GROVE_STATE": dir.path], home: URL(fileURLWithPath: "/nowhere"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("connected\n".utf8).write(to: url)
        #expect(try !BluetoothBarFile.update(.connected, at: url))
        try Data("garbage".utf8).write(to: url)
        #expect(try BluetoothBarFile.update(.connected, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "connected\n")
    }
}
