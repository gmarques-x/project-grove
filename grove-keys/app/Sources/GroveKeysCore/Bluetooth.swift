import Foundation
import GroveThemesCore

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
        // Each entry is cast on its own: one that isn't a device is skipped,
        // not the whole list.
        let entries = (section["device_connected"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let devices = entries.flatMap { entry in
            entry.compactMap { name, value in (value as? [String: Any]).map { device(named: name, $0) } }
        }
        return BluetoothState(power: true, connected: unique(devices))
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

    /// Devices without an address stand in by name, and two can share one:
    /// the second and later get "#2", "#3"… (their place in the list), so
    /// every row has its own id.
    private static func unique(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        var seen = Set<String>()
        return devices.enumerated().map { index, device in
            var id = device.id
            if seen.contains(id) { id = "\(device.id)#\(index + 1)" }
            while seen.contains(id) { id += "'" }
            seen.insert(id)
            return BluetoothDevice(id: id, name: device.name, kind: device.kind, battery: device.battery)
        }
    }

    /// "80%", "80 %" (or a bare number) as 0...100.
    private static func percent(_ value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let text as String:
            number = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
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

/// The bar's Bluetooth icon state: `$GROVE_STATE/bluetooth`, one line,
/// `off`, `on` or `connected`. Grove Keys writes it, the bar's `bt` item
/// reads it; no file shows `off`.
public enum BluetoothBarFile {
    /// Next to keys.json: `$GROVE_STATE/bluetooth`, default
    /// `~/.local/state/grove/bluetooth`.
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("bluetooth")
    }

    /// Writes the icon's word and a newline atomically, readable by the owner
    /// only, unless the file already holds it (a 30 s read that changes
    /// nothing writes nothing); nil removes the file. True when the file
    /// changed, so the bar is told only then.
    @discardableResult
    public static func update(_ icon: BluetoothIcon?, at url: URL) throws -> Bool {
        guard let icon else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                return false
            }
            return true
        }
        let line = icon.rawValue + "\n"
        guard (try? String(contentsOf: url, encoding: .utf8)) != line else { return false }
        try writeAtomically(Data(line.utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
}

extension BluetoothDevice {
    /// The battery as the row shows it ("60%"); nil when none is reported.
    public var batteryText: String? { battery.map { "\($0)%" } }
}

/// Whether Grove Keys may use Bluetooth: macOS's answer to its one prompt
/// (CoreBluetooth's `CBManager.authorization`; restricted counts as refused).
public enum BluetoothPermission: Sendable {
    case undetermined, allowed, refused
}

/// What the Wi-Fi dropdown's Bluetooth section shows under its header.
public enum BluetoothSectionContent: Equatable, Sendable {
    /// No reading yet: the header alone.
    case reading
    /// The power is unknown (no controller, or the output can't be read):
    /// the header alone, its switch disabled ("off" would be a guess).
    case unknown
    /// Permission refused: says so, with a button to the privacy setting,
    /// over the devices that were read anyway (when on); no switch. Grove
    /// Keys never asks again (macOS wouldn't show it).
    case refused([BluetoothDevice])
    /// The controller says off.
    case off
    /// On: the connected devices, "No devices connected" when none.
    case devices([BluetoothDevice])

    public init(state: BluetoothState?, permission: BluetoothPermission) {
        if permission == .refused {
            self = .refused(state?.power == true ? state?.connected ?? [] : [])
            return
        }
        guard let state else {
            self = .reading
            return
        }
        switch state.power {
        case nil: self = .unknown
        case false?: self = .off
        case true?: self = .devices(state.connected)
        }
    }

    /// The section's one line of text, when it has one.
    public var line: String? {
        switch self {
        case .reading, .unknown: return nil
        case .refused: return "Grove Keys needs Bluetooth permission"
        case .off: return "Bluetooth is off"
        case .devices(let devices): return devices.isEmpty ? "No devices connected" : nil
        }
    }

    /// The header has its switch (not when permission is refused).
    public var showsSwitch: Bool {
        if case .refused = self { return false }
        return true
    }

    /// The device rows to draw.
    public var devices: [BluetoothDevice] {
        switch self {
        case .devices(let devices), .refused(let devices): return devices
        case .reading, .unknown, .off: return []
        }
    }

    /// The switch can be used: only when the power is known.
    public var switchEnabled: Bool {
        switch self {
        case .off, .devices: return true
        case .reading, .unknown, .refused: return false
        }
    }

    public var switchOn: Bool {
        if case .devices = self { return true }
        return false
    }
}

/// When the Bluetooth reader reads, and when it logs. A reading under
/// `gap` after the last one finished is skipped (a wake and an overdue
/// timer would give two in a row), unless forced (after the switch); a
/// failed reading is logged once until one succeeds.
public struct BluetoothPace: Sendable {
    public static let gap: TimeInterval = 5

    private var lastFinished: Date?
    private var failing = false

    public init() {}

    public func due(at now: Date, force: Bool) -> Bool {
        guard !force, let lastFinished else { return true }
        return now.timeIntervalSince(lastFinished) >= Self.gap
    }

    /// A reading finished. True when its failure should be logged.
    public mutating func finished(at now: Date, failure: Bool) -> Bool {
        lastFinished = now
        defer { failing = failure }
        return failure && !failing
    }
}

/// A reading as the reader publishes it: the state and the reading's
/// number, counted as readings start (so a later number started later).
public struct BluetoothReading: Equatable, Sendable {
    public let state: BluetoothState
    public let number: Int

    public init(state: BluetoothState, number: Int) {
        self.state = state
        self.number = number
    }
}

/// The section's switch while the power is being changed: it shows `on`
/// until a reading that started after the change arrives. Earlier readings
/// (one under way, the 30 s timer's) would flick it back.
public struct BluetoothPendingSwitch: Equatable, Sendable {
    public let on: Bool
    /// The number of the last reading started when the power had changed;
    /// nil while it is still being changed.
    private var after: Int?

    public init(on: Bool) { self.on = on }

    /// The power changed; `number` is the last reading started by then.
    public mutating func changed(afterReading number: Int) { after = number }

    public func settles(with reading: BluetoothReading) -> Bool {
        guard let after else { return false }
        return reading.number > after
    }
}
