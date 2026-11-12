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
}
