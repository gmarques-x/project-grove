import Foundation

public struct KeysPaths: Sendable {
    public var keys, monitors, base, output: URL

    public init(keys: URL, monitors: URL, base: URL, output: URL) {
        self.keys = keys; self.monitors = monitors; self.base = base; self.output = output
    }

    /// `$XDG_CONFIG_HOME` when set and non-empty, else `~/.config`.
    public static func standard(home: URL, environment: [String: String]) -> KeysPaths {
        let config: URL
        if let x = environment["XDG_CONFIG_HOME"], !x.isEmpty {
            config = URL(fileURLWithPath: x, isDirectory: true)
        } else {
            config = home.appendingPathComponent(".config", isDirectory: true)
        }
        return KeysPaths(
            keys: config.appendingPathComponent("grove-keys/keys.toml"),
            monitors: config.appendingPathComponent("grove-keys/monitors.toml"),
            base: config.appendingPathComponent("aerospace/aerospace.base.toml"),
            output: config.appendingPathComponent("aerospace/aerospace.toml"))
    }
}
