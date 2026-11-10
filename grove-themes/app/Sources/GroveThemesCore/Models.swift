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

/// One scheme's palette from `list --json`: `colors` maps bg0 … purple to `#RRGGBB`.
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

    public init(current: String, schemes: [String], palettes: [String: Palette]) {
        self.current = current
        self.schemes = schemes
        self.palettes = palettes
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
}
