import Foundation

/// What one `set` step did, as `grove-themes set --json` reports it.
public enum StepResult: String, Decodable, Sendable {
    case live
    case nextPrompt = "next-prompt"
    case nextLaunch = "next-launch"
    case needsYou = "needs-you"
    case failed
}

public struct Step: Decodable, Equatable, Sendable {
    public let name: String
    public let result: StepResult
    public let message: String

    public init(name: String, result: StepResult, message: String) {
        self.name = name
        self.result = result
        self.message = message
    }
}

/// One scheme's palette from `list --json`: `colors` maps bg0 … purple and the
/// four roles (border, on_accent, dim, lockup_ink) to `#RRGGBB`.
public struct Palette: Decodable, Equatable, Sendable {
    public let name: String
    public let appearance: String
    public let colors: [String: String]

    public init(name: String, appearance: String, colors: [String: String]) {
        self.name = name
        self.appearance = appearance
        self.colors = colors
    }
}

/// `grove-themes list --json`.
public struct SchemeList: Decodable, Equatable, Sendable {
    public let current: String
    public let schemes: [String]
    public let palettes: [String: Palette]
    /// The terminal logo (`grove` or `avatar`) and the choices, in menu order.
    /// A CLI older than the logo command sends neither: grove and both logos.
    public let logo: String
    public let logos: [String]
    /// The wallpaper set (`grove` or `avatar`) and the choices; same defaults.
    public let wallpaper: String
    public let wallpapers: [String]

    public static let defaultLogos = ["grove", "avatar"]
    public static let defaultWallpapers = ["grove", "avatar"]

    public init(current: String, schemes: [String], palettes: [String: Palette],
                logo: String = "grove", logos: [String] = SchemeList.defaultLogos,
                wallpaper: String = "grove", wallpapers: [String] = SchemeList.defaultWallpapers) {
        self.current = current
        self.schemes = schemes
        self.palettes = palettes
        self.logo = logo
        self.logos = logos
        self.wallpaper = wallpaper
        self.wallpapers = wallpapers
    }

    private enum CodingKeys: String, CodingKey {
        case current, schemes, palettes, logo, logos, wallpaper, wallpapers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = try c.decode(String.self, forKey: .current)
        schemes = try c.decode([String].self, forKey: .schemes)
        palettes = try c.decode([String: Palette].self, forKey: .palettes)
        logo = try c.decodeIfPresent(String.self, forKey: .logo) ?? "grove"
        logos = try c.decodeIfPresent([String].self, forKey: .logos) ?? Self.defaultLogos
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper) ?? "grove"
        wallpapers = try c.decodeIfPresent([String].self, forKey: .wallpapers) ?? Self.defaultWallpapers
    }
}

/// `grove-themes wallpaper NAME --json`: the set it saved and its one step.
public struct WallpaperResult: Decodable, Equatable, Sendable {
    public let wallpaper: String
    public let steps: [Step]

    public init(wallpaper: String, steps: [Step]) {
        self.wallpaper = wallpaper
        self.steps = steps
    }
}

/// `grove-themes set SCHEME --json`.
public struct SwitchResult: Decodable, Equatable, Sendable {
    public let scheme: String
    public let steps: [Step]

    public init(scheme: String, steps: [Step]) {
        self.scheme = scheme
        self.steps = steps
    }
}

/// One line of the switch log (`log --json` entries); `time` is ISO 8601 with an offset.
public struct LogEntry: Decodable, Equatable, Sendable {
    public let time: Date
    public let scheme: String
    public let exit: Int
    public let steps: [Step]

    public init(time: Date, scheme: String, exit: Int, steps: [Step]) {
        self.time = time
        self.scheme = scheme
        self.exit = exit
        self.steps = steps
    }

    /// The configs weren't written: nothing else ran, and the CLI didn't log it.
    public var configsFailed: Bool {
        steps.contains { $0.name == "configs" && $0.result == .failed }
    }
}
