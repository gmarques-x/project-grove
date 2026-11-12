import Foundation

/// The conflict prompt's questions, one name after the other, and what the
/// answers add up to: the plan the run resolves by and the answers the undo
/// stack keeps for a redo.
public struct ConflictAsking: Equatable, Sendable {
    /// The names that exist, as `existingNames` gave them.
    private let existing: [URL]
    /// One URL of each name, in order: a name given twice is asked about once.
    private let names: [URL]
    private var index = 0
    public private(set) var plan = ConflictPlan()

    public init(existing: [URL]) {
        self.existing = existing
        var seen: Set<String> = []
        names = existing.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// The name being asked about; nil once every name has its answer.
    public var current: URL? { names.indices.contains(index) ? names[index] : nil }

    /// How many names come after the current one: "Apply to all (N more)".
    public var remaining: Int { max(names.count - index - 1, 0) }

    /// The answer about the current name; with `applyToAll`, about every
    /// name after it too.
    public mutating func answer(_ choice: Conflict.Choice, applyToAll: Bool) {
        guard let current else { return }
        plan.answer(choice, for: current, applyToAll: applyToAll)
        index = applyToAll ? names.count : index + 1
    }

    /// The answer about each name that exists, by the URL `existingNames`
    /// gave for it: what `UndoStack.record` takes. A name not yet answered
    /// about is not in it.
    public var answers: [URL: Conflict.Choice] {
        var answers: [URL: Conflict.Choice] = [:]
        for url in existing {
            if let choice = plan.choice(for: url) { answers[url] = choice }
        }
        return answers
    }
}

/// The prompt's words.
public enum ConflictWords {
    public static func title(for existing: URL) -> String {
        "An item named “\(existing.lastPathComponent)” already exists in \(place(of: existing))."
    }

    /// Before the size and date of the item that is there.
    public static func thereLabel(for existing: URL) -> String {
        "In \(place(of: existing))"
    }

    /// Before the size and date of the item coming.
    public static func comingLabel(for operation: Operation) -> String {
        if case .move = operation { return "Being moved" }
        return "Being copied"
    }

    /// "2 KB · 9 Nov 2026 at 02:04"; a folder has no size of its own.
    public static func detail(size: Int64?, date: String?) -> String {
        let parts = [size.map(Formatting.size), date].compactMap { $0 }
        return parts.isEmpty ? "--" : parts.joined(separator: " · ")
    }

    public static func applyToAll(remaining: Int) -> String {
        "Apply to all (\(Wording.grouped(remaining)) more)"
    }

    private static func place(of existing: URL) -> String {
        Wording.place(existing.deletingLastPathComponent())
    }
}

/// The prompt's buttons, as they stand from left to right.
public enum ConflictButton: CaseIterable, Equatable, Sendable {
    case cancel, skip, replace, keepBoth

    /// The one Return takes when the keyboard hasn't moved: it loses nothing.
    public static let standard = ConflictButton.keepBoth

    public var title: String {
        switch self {
        case .cancel: "Cancel"
        case .skip: "Skip"
        case .replace: "Replace"
        case .keepBoth: "Keep Both"
        }
    }

    /// The answer it gives; nil for Cancel, which gives up the whole operation.
    public var choice: Conflict.Choice? {
        switch self {
        case .cancel: nil
        case .skip: .skip
        case .replace: .replace
        case .keepBoth: .keepBoth
        }
    }

    /// The button the keyboard goes to next (Tab, →), round to the first.
    public var next: ConflictButton { step(1) }
    /// And back (⇧Tab, ←).
    public var previous: ConflictButton { step(-1) }

    private func step(_ by: Int) -> ConflictButton {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + by + all.count) % all.count]
    }
}
