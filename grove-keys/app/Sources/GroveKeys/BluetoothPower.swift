import CoreBluetooth
import Darwin
import GroveKeysCore

/// Bluetooth's power and Grove Keys' permission to use it (spec
/// 2026-11-13-bar-wifi-bluetooth-design): the switch in the Wi-Fi dropdown's
/// Bluetooth section.
///
/// The power goes through `IOBluetoothPreferenceSetControllerPowerState`, a
/// private IOBluetooth function looked up at run time; when it isn't there
/// (or the power doesn't follow) the section opens Bluetooth Settings instead.
enum BluetoothPower {
    /// System Settings ▸ Bluetooth.
    static let settingsURL = "x-apple.systempreferences:com.apple.preference.Bluetooth"
    /// System Settings ▸ Privacy & Security ▸ Bluetooth.
    static let privacyURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"

    private static let framework = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
    private typealias SetPower = @convention(c) (Int32) -> Void
    private typealias GetPower = @convention(c) () -> Int32

    /// macOS's answer to the one prompt. Reading it never asks: Grove Keys
    /// asks no more than macOS does (once, the first time it uses
    /// Bluetooth), and a refusal stays refused until the owner changes it in
    /// the privacy setting.
    static var permission: BluetoothPermission {
        switch CBManager.authorization {
        case .allowedAlways: return .allowed
        case .denied, .restricted: return .refused
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    /// Turns the controller on or off and waits (up to 2 s) for it to say
    /// so. False when the function isn't there or the power didn't follow:
    /// the caller opens Bluetooth Settings. Not on the main thread. Never
    /// called by a render or a test (the section's sample model has no
    /// switch to act on).
    static func set(_ on: Bool) -> Bool {
        guard let handle = dlopen(framework, RTLD_LAZY),
              let setter = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return false }
        unsafeBitCast(setter, to: SetPower.self)(on ? 1 : 0)
        // Without the getter there is nothing to wait on: the next reading tells.
        guard let getter = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return true }
        let power = unsafeBitCast(getter, to: GetPower.self)
        for _ in 0..<20 {
            if (power() != 0) == on { return true }
            usleep(100_000)
        }
        return false
    }
}
