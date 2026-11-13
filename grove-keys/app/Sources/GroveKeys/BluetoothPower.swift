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

    /// macOS's answer to the one prompt. Reading it never asks (the prompt
    /// is `BluetoothPermissionAsker`'s, once); a refusal stays refused until
    /// the owner changes it in the privacy setting.
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

/// The one thing in Grove Keys that makes macOS ask for Bluetooth: a
/// `CBCentralManager`, made the first time the live Wi-Fi dropdown opens
/// while the answer isn't known yet, and kept for the app's life (macOS
/// shows its prompt once; after a refusal it never asks again, and neither
/// does Grove Keys). It scans for nothing; its delegate only hears that the
/// answer (or the radio's state) changed. Never made by a render or a test.
@MainActor
final class BluetoothPermissionAsker: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothPermissionAsker()

    private var manager: CBCentralManager?
    private var changed: [@MainActor () -> Void] = []

    /// Asks once, when the answer isn't known. `onChange` runs on the main
    /// actor each time the manager reports (the prompt answered).
    func askIfUndetermined(onChange: @escaping @MainActor () -> Void) {
        guard manager == nil, BluetoothPower.permission == .undetermined else { return }
        changed.append(onChange)
        // A nil queue: the delegate is called on the main queue.
        // No "turn Bluetooth on" alert of its own: the section's switch is for that.
        manager = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            for change in changed { change() }
        }
    }
}
