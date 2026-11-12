import Foundation

// The Sound panel's pure parts (spec 2026-11-12-bar-panels-design §6): which
// audio devices are choices, what each looks like, the level's maths, and
// what a click or a key does, over a `SoundSystem` the app target fills
// with CoreAudio and the tests with a fake.

/// How a device is attached (`kAudioDevicePropertyTransportType`).
public enum SoundTransport: Equatable, Sendable {
    case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, virtual, aggregate, continuity, other

    /// From CoreAudio's four-character code ("bltn", "blue", "usb "…).
    public init(code: UInt32) {
        switch code {
        case Self.code("bltn"): self = .builtIn
        case Self.code("blue"), Self.code("blea"): self = .bluetooth
        case Self.code("usb "): self = .usb
        case Self.code("hdmi"): self = .hdmi
        case Self.code("dprt"): self = .displayPort
        case Self.code("airp"): self = .airPlay
        case Self.code("thun"): self = .thunderbolt
        case Self.code("virt"): self = .virtual
        case Self.code("grup"): self = .aggregate
        // An iPhone used as a microphone, wired or not.
        case Self.code("ccwd"), Self.code("ccwl"): self = .continuity
        default: self = .other
        }
    }

    /// A four-character code as CoreAudio's number ("bltn" is 0x626C746E).
    public static func code(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}

/// One audio device as CoreAudio describes it, before any choice is made.
public struct SoundDeviceInfo: Equatable, Sendable {
    /// The `AudioObjectID`.
    public var id: UInt32
    public var name: String
    public var uid: String
    public var transport: SoundTransport
    /// Has streams in that direction (`kAudioDevicePropertyStreams`).
    public var hasOutput: Bool
    public var hasInput: Bool
    /// `kAudioDevicePropertyDeviceCanBeDefaultDevice` per direction; true
    /// when the device doesn't say.
    public var canBeDefaultOutput: Bool
    public var canBeDefaultInput: Bool
    /// `kAudioDevicePropertyIsHidden`.
    public var hidden: Bool
    /// The output's data source (`kAudioDevicePropertyDataSource`), where a
    /// built-in device tells headphones ("hdpn") from speakers ("ispk").
    public var outputSource: UInt32?

    public init(id: UInt32, name: String, uid: String = "", transport: SoundTransport, hasOutput: Bool = false,
                hasInput: Bool = false, canBeDefaultOutput: Bool = true, canBeDefaultInput: Bool = true,
                hidden: Bool = false, outputSource: UInt32? = nil) {
        self.id = id
        self.name = name
        self.uid = uid
        self.transport = transport
        self.hasOutput = hasOutput
        self.hasInput = hasInput
        self.canBeDefaultOutput = canBeDefaultOutput
        self.canBeDefaultInput = canBeDefaultInput
        self.hidden = hidden
        self.outputSource = outputSource
    }
}

/// What a device is drawn as.
public enum SoundDeviceKind: Equatable, Sendable {
    case speakers, headphones, airPods, bluetooth, display, airPlay, usb, other

    /// From how the device is attached and what it is called. The name
    /// decides inside a transport (AirPods among Bluetooth devices, a display
    /// or a headset on USB); the built-in device says headphones through its
    /// data source (Intel) or its name ("External Headphones", Apple silicon).
    public init(transport: SoundTransport, name: String, outputSource: UInt32? = nil) {
        let name = name.lowercased()
        let headphones = ["headphone", "headset", "earphone", "earbud"].contains { name.contains($0) }
        let display = ["display", "monitor"].contains { name.contains($0) }
        switch transport {
        case .builtIn:
            self = headphones || outputSource == SoundTransport.code("hdpn") ? .headphones : .speakers
        case .bluetooth:
            self = name.contains("airpods") ? .airPods : headphones ? .headphones : .bluetooth
        case .hdmi, .displayPort:
            self = .display
        case .airPlay:
            self = .airPlay
        case .usb:
            self = display ? .display : headphones ? .headphones : .usb
        case .thunderbolt:
            self = display ? .display : .other
        case .virtual, .aggregate, .continuity, .other:
            self = .other
        }
    }
}

/// A device as a row: one of the choices for a direction.
public struct SoundDevice: Equatable, Identifiable, Sendable {
    public var id: UInt32
    public var name: String
    public var kind: SoundDeviceKind

    public init(id: UInt32, name: String, kind: SoundDeviceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// The devices that are choices, in the system's order (stable: the order
/// CoreAudio lists them in, which is the order they appeared).
public enum SoundList {
    /// The name macOS gives the aggregates it builds for itself.
    static let systemAggregate = "CADefaultDeviceAggregate"

    /// A device is a choice for a direction when it has streams there, may
    /// be the default device there, is not marked hidden, and is not one of
    /// the system's own aggregates (by name or UID). Other aggregate and
    /// virtual devices stay: Sound Settings lists them too.
    static func listed(_ info: SoundDeviceInfo, output: Bool) -> Bool {
        guard output ? info.hasOutput && info.canBeDefaultOutput : info.hasInput && info.canBeDefaultInput else {
            return false
        }
        return !info.hidden && !info.name.hasPrefix(systemAggregate) && !info.uid.hasPrefix(systemAggregate)
    }

    public static func outputs(_ devices: [SoundDeviceInfo]) -> [SoundDevice] {
        devices.filter { listed($0, output: true) }.map(row)
    }

    public static func inputs(_ devices: [SoundDeviceInfo]) -> [SoundDevice] {
        devices.filter { listed($0, output: false) }.map(row)
    }

    private static func row(_ info: SoundDeviceInfo) -> SoundDevice {
        let name = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SoundDevice(id: info.id, name: name.isEmpty ? "Audio device" : name,
                           kind: SoundDeviceKind(transport: info.transport, name: name, outputSource: info.outputSource))
    }

    /// The row ↑ or ↓ moves to: from the row already lit, or else from the
    /// current device; it stops at the ends. Nil when there are no rows.
    public static func moved(from lit: Int?, by delta: Int, count: Int, current: Int?) -> Int? {
        guard count > 0 else { return nil }
        let start = lit ?? current ?? (delta > 0 ? -1 : count)
        return min(max(start + delta, 0), count - 1)
    }
}

/// The speaker drawn in the panel's header.
public enum SoundGlyph: Equatable, Sendable {
    case muted, silent, medium, loud
}

/// The level's maths. A level is 0...1, as CoreAudio's virtual main volume.
public enum SoundVolume {
    /// The volume keys move the level in sixteenths.
    public static let steps = 16

    public static func clamped(_ level: Double) -> Double {
        level.isNaN ? 0 : min(max(level, 0), 1)
    }

    /// 0...100, rounded.
    public static func percent(_ level: Double) -> Int {
        Int((clamped(level) * 100).rounded())
    }

    /// "62%": plain digits, the same in every locale.
    public static func label(_ level: Double) -> String {
        "\(percent(level))%"
    }

    /// One press of a volume key: the next sixteenth above or below (a level
    /// between two sixteenths lands on the nearest one in that direction).
    public static func stepped(_ level: Double, up: Bool) -> Double {
        let position = clamped(level) * Double(steps)
        // A level that is a sixteenth but for float noise counts as on it.
        let nearest = position.rounded()
        let onStep = abs(position - nearest) < 1e-4
        let next = onStep ? nearest + (up ? 1 : -1) : up ? position.rounded(.up) : position.rounded(.down)
        return clamped(next / Double(steps))
    }

    /// The bar's speaker fill in tenths, 0...10; anything above silence
    /// shows at least 1 (`sb_vol_level` in the bar's lib.sh; kept the same).
    public static func barLevel(percent: Int) -> Int {
        if percent <= 0 { return 0 }
        if percent < 10 { return 1 }
        if percent >= 100 { return 10 }
        return (percent + 5) / 10
    }

    /// The header's speaker: struck out when muted, without waves at
    /// silence, three waves from the bar's seventh tenth, two below. A device
    /// without a volume control (`level` nil) plays at its own level: two waves.
    public static func glyph(level: Double?, muted: Bool) -> SoundGlyph {
        if muted { return .muted }
        guard let level else { return .medium }
        switch barLevel(percent: percent(level)) {
        case 0: return .silent
        case 1...6: return .medium
        default: return .loud
        }
    }
}

/// Everything the panel shows.
public struct SoundState: Equatable, Sendable {
    public var outputs: [SoundDevice]
    public var inputs: [SoundDevice]
    /// The default output and input devices.
    public var output: UInt32?
    public var input: UInt32?
    /// The output's level, 0...1; nil when it has no volume control (HDMI,
    /// some displays).
    public var volume: Double?
    public var muted: Bool
    /// False when the output has no mute control.
    public var canMute: Bool

    public init(outputs: [SoundDevice] = [], inputs: [SoundDevice] = [], output: UInt32? = nil, input: UInt32? = nil,
                volume: Double? = nil, muted: Bool = false, canMute: Bool = false) {
        self.outputs = outputs
        self.inputs = inputs
        self.output = output
        self.input = input
        self.volume = volume
        self.muted = muted
        self.canMute = canMute
    }

    /// The header's value: "Muted", "62%", or nothing without a volume control.
    public var headline: String? {
        muted ? "Muted" : volume.map(SoundVolume.label)
    }

    public var glyph: SoundGlyph { SoundVolume.glyph(level: volume, muted: muted) }

    /// The current output's row.
    public var outputIndex: Int? { outputs.firstIndex { $0.id == output } }

    /// The current input's name; nil when there is none.
    public var inputName: String? { inputs.first { $0.id == input }?.name }
}

/// The Mac's audio, as the panel needs it. CoreAudio in the app; a fake in
/// the tests (which must never change this Mac's volume or devices).
public protocol SoundSystem {
    func devices() -> [SoundDeviceInfo]
    func defaultOutput() -> UInt32?
    func defaultInput() -> UInt32?
    /// The device's output level, 0...1; nil when it has none it lets be set.
    func volume(of device: UInt32) -> Double?
    /// Nil when the device has no mute control.
    func muted(of device: UInt32) -> Bool?
    func setVolume(_ level: Double, of device: UInt32)
    func setMuted(_ muted: Bool, of device: UInt32)
    /// Sound goes there, alerts included.
    func setDefaultOutput(_ device: UInt32)
    func setDefaultInput(_ device: UInt32)
}

/// Reads the panel's state and does what its controls ask, on the current
/// output device.
public struct SoundController<System: SoundSystem> {
    public let system: System

    public init(_ system: System) { self.system = system }

    public func state() -> SoundState {
        let devices = system.devices()
        let output = system.defaultOutput()
        let muted = output.flatMap(system.muted)
        return SoundState(outputs: SoundList.outputs(devices), inputs: SoundList.inputs(devices), output: output,
                          input: system.defaultInput(), volume: output.flatMap(system.volume).map(SoundVolume.clamped),
                          muted: muted ?? false, canMute: muted != nil)
    }

    /// The slider: the level alone.
    public func setVolume(_ level: Double) {
        guard let output = system.defaultOutput(), system.volume(of: output) != nil else { return }
        system.setVolume(SoundVolume.clamped(level), of: output)
    }

    /// ← or →: one sixteenth, and the sound comes back if it was muted, as
    /// with the keyboard's volume keys.
    public func step(up: Bool) {
        guard let output = system.defaultOutput(), let level = system.volume(of: output) else { return }
        system.setVolume(SoundVolume.stepped(level, up: up), of: output)
        if system.muted(of: output) == true { system.setMuted(false, of: output) }
    }

    public func setMuted(_ muted: Bool) {
        guard let output = system.defaultOutput(), let now = system.muted(of: output), now != muted else { return }
        system.setMuted(muted, of: output)
    }

    public func toggleMute() {
        guard let output = system.defaultOutput(), let now = system.muted(of: output) else { return }
        system.setMuted(!now, of: output)
    }

    /// A click on an output row. Only a listed device, and not the current one.
    public func selectOutput(_ device: UInt32) {
        guard device != system.defaultOutput(), SoundList.outputs(system.devices()).contains(where: { $0.id == device })
        else { return }
        system.setDefaultOutput(device)
    }

    public func selectInput(_ device: UInt32) {
        guard device != system.defaultInput(), SoundList.inputs(system.devices()).contains(where: { $0.id == device })
        else { return }
        system.setDefaultInput(device)
    }
}

extension SoundController: Sendable where System: Sendable {}
