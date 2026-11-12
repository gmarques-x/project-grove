import AudioToolbox
import CoreAudio
import Foundation
import GroveKeysCore

// The Sound panel's CoreAudio side: `SoundSystem` over the HAL's properties,
// and the listeners that keep the panel current while it is open. Reads are
// in-process property lookups (no subprocess); everything here is called on
// the model's serial queue, never on the main thread while the panel is open.

/// The Mac's audio through CoreAudio. Stateless: safe from any thread.
struct CoreAudioSound: SoundSystem, Sendable {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The level every app's volume control moves; a device without it may
    /// still have a plain volume on its main element.
    private static let volumes = [
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput),
        address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput),
    ]
    private static let mute = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)

    // MARK: Reading

    func devices() -> [SoundDeviceInfo] {
        Self.ids(Self.system, Self.address(kAudioHardwarePropertyDevices)).map { id in
            let name = Self.string(id, kAudioObjectPropertyName) ?? Self.string(id, kAudioDevicePropertyDeviceNameCFString)
            let output = kAudioObjectPropertyScopeOutput, input = kAudioObjectPropertyScopeInput
            return SoundDeviceInfo(
                id: id, name: name ?? "", uid: Self.string(id, kAudioDevicePropertyDeviceUID) ?? "",
                transport: SoundTransport(code: Self.number(id, Self.address(kAudioDevicePropertyTransportType)) ?? 0),
                hasOutput: !Self.ids(id, Self.address(kAudioDevicePropertyStreams, output)).isEmpty,
                hasInput: !Self.ids(id, Self.address(kAudioDevicePropertyStreams, input)).isEmpty,
                canBeDefaultOutput: Self.number(id, Self.address(kAudioDevicePropertyDeviceCanBeDefaultDevice, output)) != 0,
                canBeDefaultInput: Self.number(id, Self.address(kAudioDevicePropertyDeviceCanBeDefaultDevice, input)) != 0,
                hidden: Self.number(id, Self.address(kAudioDevicePropertyIsHidden)) == 1,
                outputSource: Self.number(id, Self.address(kAudioDevicePropertyDataSource, output)))
        }
    }

    func defaultOutput() -> UInt32? { Self.device(kAudioHardwarePropertyDefaultOutputDevice) }
    func defaultInput() -> UInt32? { Self.device(kAudioHardwarePropertyDefaultInputDevice) }

    func volume(of device: UInt32) -> Double? {
        guard var address = Self.volumeAddress(device) else { return nil }
        var value = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    func muted(of device: UInt32) -> Bool? {
        guard Self.settable(device, Self.mute), let value: UInt32 = Self.number(device, Self.mute) else { return nil }
        return value != 0
    }

    // MARK: Changing (only ever from a control or a key of the open panel)

    func setVolume(_ level: Double, of device: UInt32) {
        guard var address = Self.volumeAddress(device) else { return }
        var value = Float32(SoundVolume.clamped(level))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    func setMuted(_ muted: Bool, of device: UInt32) {
        var address = Self.mute, value: UInt32 = muted ? 1 : 0
        guard Self.settable(device, address) else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func setDefaultOutput(_ device: UInt32) {
        // The second is where alerts play: they follow, as in Sound Settings.
        Self.setDevice(kAudioHardwarePropertyDefaultOutputDevice, device)
        Self.setDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, device)
    }

    func setDefaultInput(_ device: UInt32) {
        Self.setDevice(kAudioHardwarePropertyDefaultInputDevice, device)
    }

    // MARK: Properties

    /// The first volume property the device has and lets be set.
    private static func volumeAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
        volumes.first { settable(device, $0) }
    }

    private static func settable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address, settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address) else { return false }
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    private static func device(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        let id: UInt32? = number(system, address(selector))
        return id == kAudioObjectUnknown ? nil : id
    }

    private static func setDevice(_ selector: AudioObjectPropertySelector, _ device: AudioObjectID) {
        var address = address(selector), value = device
        AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    /// A 32-bit property (an ID, a flag, a four-character code); nil when
    /// the object doesn't have it.
    private static func number(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address, value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(object, &address),
              AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// A property that is a list of object IDs (the devices, a device's streams).
    private static func ids(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address, size: UInt32 = 0
        guard AudioObjectHasProperty(object, &address),
              AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else { return [] }
        return Array(list.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector), size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectHasProperty(object, &address) else { return nil }
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// CoreAudio's notices while the panel is open: the list of devices, the
/// default output and input, and the current output's volume, mute and data
/// source (headphones plugged into an Intel Mac). `start` and `stop` are
/// called on `queue`, where the notices arrive too; `stop` removes every
/// listener, so a closed panel hears nothing.
final class SoundWatcher: @unchecked Sendable {
    private typealias Listener = (object: AudioObjectID, address: AudioObjectPropertyAddress)

    private let queue: DispatchQueue
    private var onChange: (@Sendable () -> Void)?
    /// One block for every listener: removing needs the very block added.
    private var block: AudioObjectPropertyListenerBlock?
    private var system: [Listener] = []
    private var device: [Listener] = []
    private var watched: AudioObjectID?

    init(queue: DispatchQueue) { self.queue = queue }

    /// `onChange` runs on `queue` after any of the above changed.
    func start(_ onChange: @escaping @Sendable () -> Void) {
        stop()
        self.onChange = onChange
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }
        self.block = block
        system = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                  kAudioHardwarePropertyDefaultInputDevice]
            .map { (CoreAudioSound.system, CoreAudioSound.address($0)) }
            .filter(add)
        follow()
    }

    func stop() {
        (system + device).forEach(remove)
        system = []
        device = []
        watched = nil
        block = nil
        onChange = nil
    }

    private func changed() {
        guard let onChange else { return }
        follow()
        onChange()
    }

    /// Listens to the current output device, and no longer to the last one.
    private func follow() {
        let output = CoreAudioSound().defaultOutput()
        guard output != watched else { return }
        device.forEach(remove)
        device = []
        watched = output
        guard let output else { return }
        let scope = kAudioObjectPropertyScopeOutput
        device = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar,
                  kAudioDevicePropertyMute, kAudioDevicePropertyDataSource]
            .map { (output, CoreAudioSound.address($0, scope)) }
            .filter(add)
    }

    private func add(_ listener: Listener) -> Bool {
        guard let block else { return false }
        var address = listener.address
        return AudioObjectAddPropertyListenerBlock(listener.object, &address, queue, block) == noErr
    }

    /// A device that is gone took its listeners with it; the error is nothing.
    private func remove(_ listener: Listener) {
        guard let block else { return }
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, queue, block)
    }
}
