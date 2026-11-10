import Foundation

/// One log chip: "10 now", "yazi next launch", "needs you: appearance", "failed: accent".
public struct Chip: Equatable, Sendable {
    public let text: String
    public let kind: StepResult
    public let message: String

    public init(text: String, kind: StepResult, message: String) {
        self.text = text
        self.kind = kind
        self.message = message
    }
}

/// Words for a switch (Ruling P1): every step but a working `configs` that is
/// `live` or `next-prompt` counts as "updated now"; `next-launch` steps are
/// named; `needs-you` and `failed` steps are named, with their message on the chip.
public enum StatusText {
    /// "Switched to Dark Medium at 13:10 · 10 updated now, yazi next launch · appearance needs you";
    /// a switch from another day reads "on 9 Nov at 13:10", and one whose configs
    /// failed "Couldn't switch to Dark Hard at 13:10 · configs failed".
    public static func line(for entry: LogEntry, now: Date, calendar: Calendar) -> String {
        let parts = Parts(entry.steps)
        var done: [String] = []
        if parts.now > 0 { done.append("\(parts.now) updated now") }
        done += parts.nextLaunch.map { "\($0.name) next launch" }
        let problems = parts.problems.map { "\($0.name) \($0.result == .failed ? "failed" : "needs you")" }

        let verb = entry.configsFailed ? "Couldn't switch to" : "Switched to"
        var line = "\(verb) \(displayName(entry.scheme)) \(when(entry.time, now: now, calendar: calendar))"
        if !done.isEmpty { line += " · " + done.joined(separator: ", ") }
        if !problems.isEmpty { line += " · " + problems.joined(separator: ", ") }
        return line
    }

    public static func chips(for entry: LogEntry) -> [Chip] {
        let parts = Parts(entry.steps)
        var chips: [Chip] = []
        if parts.now > 0 {
            chips.append(Chip(text: "\(parts.now) now", kind: .live,
                              message: parts.nowNames.joined(separator: ", ")))
        }
        chips += parts.nextLaunch.map { Chip(text: "\($0.name) next launch", kind: .nextLaunch, message: $0.message) }
        chips += parts.problems.map {
            Chip(text: "\($0.result == .failed ? "failed" : "needs you"): \($0.name)", kind: $0.result, message: $0.message)
        }
        return chips
    }

    /// "dark-medium" → "Dark Medium".
    public static func displayName(_ scheme: String) -> String {
        scheme.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func when(_ time: Date, now: Date, calendar: Calendar) -> String {
        let clock = format(time, "HH:mm", calendar)
        if calendar.isDate(time, inSameDayAs: now) { return "at \(clock)" }
        return "on \(format(time, "d MMM", calendar)) at \(clock)"
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private struct Parts {
        var now = 0
        var nowNames: [String] = []
        var nextLaunch: [Step] = []
        var problems: [Step] = []

        init(_ steps: [Step]) {
            for step in steps {
                switch step.result {
                case .live, .nextPrompt:
                    if step.name == "configs" { continue }
                    now += 1
                    nowNames.append(step.name)
                case .nextLaunch: nextLaunch.append(step)
                case .needsYou, .failed: problems.append(step)
                }
            }
        }
    }
}
