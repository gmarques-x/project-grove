import Foundation

// Bluetooth beside Wi-Fi in the bar (spec 2026-11-13-bar-wifi-bluetooth-design):
// the controller's power and the connected devices, read from
// `system_profiler SPBluetoothDataType -json`, and the bar icon they make.
//
// The JSON, as macOS 26 writes it:
//   {"SPBluetoothDataType": [{
//     "controller_properties": {"controller_state": "attrib_on" | "attrib_off", …},
//     "device_connected": [{"<name>": {"device_address": "…", "device_minorType": "Headphones",
//                                      "device_batteryLevelLeft": "80%", …}}, …],
//     "device_not_connected": [ … the same … ]
//   }]}
// `device_connected` is left out when nothing is connected.

/// A connected device, as one row of the Bluetooth section.
public struct BluetoothDevice: Equatable, Sendable, Identifiable {
    /// The address ("00:00:00:00:00:01"); the name when there is none.
    public let id: String
    public let name: String
    public let kind: Kind
    /// 0...100; the lowest of the parts a device reports (AirPods: left,
    /// right, then the case alone); nil when it reports none.
    public let battery: Int?

    public enum Kind: Sendable {
        case headphones, keyboard, mouse, trackpad, speaker, other

        /// From `device_minorType` ("Headphones", "Keyboard"…), else the name.
        public init(minorType: String?, name: String) {
            self = Self.match(minorType ?? "") ?? Self.match(name) ?? .other
        }

        private static func match(_ text: String) -> Kind? {
            let text = text.lowercased()
            func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
            if has("headphone", "headset", "airpods", "earbud", "earphone", "buds") { return .headphones }
            if has("keyboard") { return .keyboard }
            if has("trackpad") { return .trackpad }
            if has("mouse") { return .mouse }
            if has("speaker") { return .speaker }
            return nil
        }
    }

    public init(id: String, name: String, kind: Kind, battery: Int?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.battery = battery
    }
}

/// What the bar and the Bluetooth section show.
public struct BluetoothState: Equatable, Sendable {
    /// The controller's power; nil when the Mac reports no controller (or
    /// the output can't be read).
    public var power: Bool?
    /// In the order macOS lists them; empty when off.
    public var connected: [BluetoothDevice]

    public init(power: Bool?, connected: [BluetoothDevice]) {
        self.power = power
        self.connected = connected
    }

    public static func parse(systemProfilerJSON data: Data) -> BluetoothState {
        let none = BluetoothState(power: nil, connected: [])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let section = sections.first(where: { $0["controller_properties"] != nil }),
              let controller = section["controller_properties"] as? [String: Any],
              let state = controller["controller_state"] as? String
        else { return none }
        let power: Bool
        switch state {
        case "attrib_on": power = true
        case "attrib_off": power = false
        default: return none
        }
        guard power else { return BluetoothState(power: false, connected: []) }
        let entries = section["device_connected"] as? [[String: Any]] ?? []
        let devices = entries.flatMap { entry in
            entry.compactMap { name, value in (value as? [String: Any]).map { device(named: name, $0) } }
        }
        return BluetoothState(power: true, connected: devices)
    }

    private static func device(named rawName: String, _ fields: [String: Any]) -> BluetoothDevice {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Bluetooth device" : trimmed
        let address = (fields["device_address"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let parts = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelMain"]
            .compactMap { percent(fields[$0]) }
        let battery = parts.min() ?? percent(fields["device_batteryLevelCase"])
        return BluetoothDevice(id: address ?? name, name: name,
                               kind: .init(minorType: fields["device_minorType"] as? String, name: name),
                               battery: battery)
    }

    /// "80%" (or a bare number) as 0...100.
    private static func percent(_ value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let text as String:
            number = Int(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
        case let int as Int: number = int
        default: number = nil
        }
        return number.map { min(max($0, 0), 100) }
    }
}

/// The bar's Bluetooth icon; the raw value is what Grove Keys writes to
/// `$GROVE_STATE/bluetooth`.
public enum BluetoothIcon: String, Sendable {
    case off, on, connected

    /// Off when the power is off or unknown; connected when a device is.
    public static func icon(for state: BluetoothState) -> BluetoothIcon {
        guard state.power == true else { return .off }
        return state.connected.isEmpty ? .on : .connected
    }
}
