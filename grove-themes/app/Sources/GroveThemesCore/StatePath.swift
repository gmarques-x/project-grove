import Foundation

public enum StatePath {
    /// The CLI's state file: `$GROVE_STATE/theme`, default `~/.local/state/grove/theme`.
    public static func url(environment: [String: String], home: URL) -> URL {
        let base: URL
        if let state = environment["GROVE_STATE"], !state.isEmpty {
            base = URL(fileURLWithPath: state, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".local/state/grove", isDirectory: true)
        }
        return base.appendingPathComponent("theme")
    }
}
