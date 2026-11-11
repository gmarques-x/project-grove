import Foundation
import GroveThemesCore

/// What the app reports to grove's module 96: the two permissions and whether
/// the Caps Lock → F18 mapping is set right now. `$GROVE_STATE/keys.json`.
public struct KeysState: Codable, Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var mapping: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, mapping: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.mapping = mapping
    }

    enum CodingKeys: String, CodingKey {
        case accessibility
        case inputMonitoring = "input_monitoring"
        case mapping
    }

    /// Next to grove-themes' state file: `$GROVE_STATE/keys.json`, default
    /// `~/.local/state/grove/keys.json`.
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("keys.json")
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeAtomically(encoder.encode(self) + Data("\n".utf8), to: url)
    }
}
