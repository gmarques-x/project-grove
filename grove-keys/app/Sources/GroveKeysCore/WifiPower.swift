import Foundation

/// One way of switching Wi-Fi on or off (CoreWLAN; `networksetup`).
public protocol WifiPowerSwitch {
    func setPower(_ on: Bool, interface: String) throws
}

/// Switching Wi-Fi: each way in turn until one works.
public enum WifiPower {
    public enum Outcome: Equatable, Sendable {
        case switched
        /// No way worked: the panel says so in one line and opens Wi-Fi Settings.
        case failed
    }

    public static let failureLine = "Can't switch Wi-Fi from here"

    public static func set(_ on: Bool, interface: String, using switches: [any WifiPowerSwitch]) -> Outcome {
        for way in switches {
            do {
                try way.setPower(on, interface: interface)
                return .switched
            } catch {
                continue
            }
        }
        return .failed
    }

    /// `/usr/sbin/networksetup`'s arguments for it.
    public static func networksetupArguments(_ on: Bool, interface: String) -> [String] {
        ["-setairportpower", interface, on ? "on" : "off"]
    }

    /// An interface's name as a command's argument: "en0", nothing else.
    public static func isInterfaceName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 16 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
