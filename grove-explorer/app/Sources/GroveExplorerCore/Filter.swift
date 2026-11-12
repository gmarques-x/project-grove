import Foundation

/// The ⌘F filter and type-to-jump: which names match what was typed.
public enum Filter {
    /// Upper and lower case are one letter, and so are a letter and its
    /// accented forms, composed or decomposed.
    private static let loose: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The entries whose name contains every word of `words`, anywhere in it
    /// and in any order, kept in the order given. Words are separated by
    /// spaces; with none, every entry matches.
    public static func matches(_ entries: [Entry], words: String) -> [Entry] {
        let words = words.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            words.allSatisfy { entry.name.range(of: $0, options: loose) != nil }
        }
    }

    /// Where the first entry whose name begins with `typed` is, in the order
    /// given; nil when there is none or nothing was typed. A space typed is
    /// part of the prefix.
    public static func jumpIndex(in entries: [Entry], typed: String) -> Int? {
        guard !typed.isEmpty else { return nil }
        let options = loose.union(.anchored)
        return entries.firstIndex { $0.name.range(of: typed, options: options) != nil }
    }

    /// What is left of `selection` under a filter: the items among `shown`.
    /// A row the filter hides is never selected, so no command acts on
    /// what the user can't see.
    public static func visibleSelection(_ selection: Set<URL>, among shown: [Entry]) -> Set<URL> {
        guard !selection.isEmpty else { return [] }
        return selection.intersection(shown.map(\.url))
    }

    /// ↑ (`step` −1) and ↓ (1) pressed in the filter field: the one row of
    /// `shown` to select next. From no selection ↓ takes the first row and
    /// ↑ the last; from several, the move starts at the end it goes
    /// towards; at the list's ends it stays. Nil when there are no rows.
    public static func moved(from selection: Set<URL>, by step: Int, in shown: [Entry]) -> URL? {
        guard !shown.isEmpty else { return nil }
        let rows = shown.indices.filter { selection.contains(shown[$0].url) }
        guard let first = rows.first, let last = rows.last else {
            return step > 0 ? shown[0].url : shown[shown.count - 1].url
        }
        let next = (step > 0 ? last : first) + step
        return shown[min(max(next, 0), shown.count - 1)].url
    }
}
