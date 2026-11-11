import Foundation

/// Caps Lock → F18 for every keyboard, through `hidutil`. Set only while the
/// event tap is running, so Caps Lock is never left dead.
enum HIDMapping {
    static let setJSON = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
    static let clearJSON = #"{"UserKeyMapping":[]}"#

    /// True when hidutil took it.
    @discardableResult static func set() -> Bool { run(setJSON) }

    @discardableResult static func clear() -> Bool { run(clearJSON) }

    private static func run(_ json: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", json]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
