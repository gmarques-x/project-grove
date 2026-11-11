import Foundation
import GroveThemesCore

/// The Wi-Fi network's name for the Grove bar: `$GROVE_STATE/wifi-name`, one
/// line. macOS gives the name only to an app allowed Location, so Grove Keys
/// writes it and the bar's Wi-Fi popup reads it. No file means "no name" (not
/// allowed, Wi-Fi off, not joined, or the app isn't running), and the bar says
/// "Wi-Fi" instead.
public enum WifiName {
    /// The longest name a network can have: 32 bytes, so at most 32 characters.
    public static let maxLength = 32

    /// Next to keys.json: `$GROVE_STATE/wifi-name`, default
    /// `~/.local/state/grove/wifi-name`.
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("wifi-name")
    }

    /// The name as one safe line, or nil when nothing is left. Whoever runs
    /// the network chooses the name, and the bar hands it to `sketchybar`, so
    /// line breaks, control and invisible formatting characters are dropped,
    /// the ends are trimmed and the rest is cut to `maxLength` characters.
    public static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator,
                 .surrogate, .privateUse, .unassigned:
                return false
            default:
                return true
            }
        }
        let trimmed = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        let name = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// What the file should hold: the name when Location is allowed and the
    /// Mac has joined a network, else nil (no file).
    public static func contents(authorized: Bool, ssid: String?) -> String? {
        authorized ? sanitize(ssid) : nil
    }

    /// Writes the name and a newline atomically, readable by the owner only;
    /// nil removes the file (already gone is fine).
    public static func write(_ contents: String?, to url: URL) throws {
        guard let contents else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                return
            }
            return
        }
        try writeAtomically(Data((contents + "\n").utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
