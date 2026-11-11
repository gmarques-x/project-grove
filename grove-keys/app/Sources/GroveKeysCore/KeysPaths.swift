import Foundation

public struct KeysPaths: Sendable {
    public var keys, monitors, base, output: URL

    public init(keys: URL, monitors: URL, base: URL, output: URL) {
        self.keys = keys; self.monitors = monitors; self.base = base; self.output = output
    }

    /// `$XDG_CONFIG_HOME` when set and non-empty, else `~/.config`.
    static func configDirectory(home: URL, environment: [String: String]) -> URL {
        if let x = environment["XDG_CONFIG_HOME"], !x.isEmpty {
            return URL(fileURLWithPath: x, isDirectory: true)
        }
        return home.appendingPathComponent(".config", isDirectory: true)
    }

    public static func standard(home: URL, environment: [String: String]) -> KeysPaths {
        let config = configDirectory(home: home, environment: environment)
        return KeysPaths(
            keys: config.appendingPathComponent("grove-keys/keys.toml"),
            monitors: config.appendingPathComponent("grove-keys/monitors.toml"),
            base: config.appendingPathComponent("aerospace/aerospace.base.toml"),
            output: config.appendingPathComponent("aerospace/aerospace.toml"))
    }
}

/// The Grove menu's two files: the tracked one, and the owner's beside it.
public struct MenuPaths: Sendable {
    public var main, local: URL

    public init(main: URL, local: URL) {
        self.main = main; self.local = local
    }

    public static func standard(home: URL, environment: [String: String]) -> MenuPaths {
        let config = KeysPaths.configDirectory(home: home, environment: environment)
        return MenuPaths(
            main: config.appendingPathComponent("grove/menu.toml"),
            local: config.appendingPathComponent("grove/menu.local.toml"))
    }
}
