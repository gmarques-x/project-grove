import Foundation

/// What to do when a name already exists where an item is going.
public enum Conflict {
    public enum Choice: Equatable, Sendable { case replace, keepBoth, skip }

    /// What the prompt asks about one name: the item coming, the one that
    /// is there, how many more names there are after this one ("Apply to
    /// all (N more)"), and the size and date of both.
    public struct Question: Equatable, Sendable {
        public let incoming: URL
        public let existing: URL
        public let remaining: Int
        /// In bytes; nil for a folder and for what can't be read, as an
        /// `Entry`'s is. A link's is the link's own.
        public let incomingSize: Int64?
        /// When it was last changed.
        public let incomingDate: Date?
        public let existingSize: Int64?
        public let existingDate: Date?

        public init(
            incoming: URL, existing: URL, remaining: Int,
            incomingSize: Int64?, incomingDate: Date?, existingSize: Int64?, existingDate: Date?
        ) {
            self.incoming = incoming
            self.existing = existing
            self.remaining = remaining
            self.incomingSize = incomingSize
            self.incomingDate = incomingDate
            self.existingSize = existingSize
            self.existingDate = existingDate
        }

        /// With the sizes and dates read from the disk as they are now.
        public init(incoming: URL, existing: URL, remaining: Int) {
            let coming = Self.sizeAndDate(of: incoming)
            let there = Self.sizeAndDate(of: existing)
            self.init(
                incoming: incoming, existing: existing, remaining: remaining,
                incomingSize: coming.size, incomingDate: coming.date,
                existingSize: there.size, existingDate: there.date)
        }

        /// Of the item itself: a link is not followed.
        private static func sizeAndDate(of url: URL) -> (size: Int64?, date: Date?) {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return (nil, nil) }
            let seconds = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
            let hasOwnSize = info.st_mode & S_IFMT != S_IFDIR
            return (hasOwnSize ? Int64(info.st_size) : nil, Date(timeIntervalSince1970: seconds))
        }
    }

    // MARK: Free names

    /// The name "keep both" gives: the first of "notes 2.md", "notes 3.md"…
    /// that `taken` doesn't have. The number goes before the extension
    /// ("archive 2.tar.gz"); a folder's name is not split ("docs 2",
    /// "my.project 2" with `isFolder`).
    ///
    /// `taken` says whether a name is in use where the item is going, by
    /// whatever rule names are compared there. It must be false for some
    /// number: the search has no end otherwise.
    public static func freeName(for name: String, isFolder: Bool = false, taken: (String) -> Bool) -> String {
        let (stem, ending) = parts(of: name, isFolder: isFolder, tarIsExtension: true)
        var number = 2
        while true {
            let candidate = numbered(stem, number, ending)
            if !taken(candidate) { return candidate }
            number += 1
        }
    }

    /// `freeName` that gives up: nil when every name up to the one
    /// numbered `last` is taken.
    static func freeName(for name: String, isFolder: Bool = false, upTo last: Int, taken: (String) -> Bool) -> String? {
        let (stem, ending) = parts(of: name, isFolder: isFolder, tarIsExtension: true)
        return firstFree(stem, ending, from: 2, upTo: last, taken: taken)
    }

    /// The name a duplicate gets, beside its original: "notes copy.md",
    /// then "notes copy 2.md", "notes copy 3.md"; nil when all of them up
    /// to the one numbered `last` are taken. The extension is `freeName`'s:
    /// "copy" goes before it, ".tar.gz" being one ("archive copy.tar.gz",
    /// as Finder names it).
    static func duplicateName(for name: String, isFolder: Bool, upTo last: Int, taken: (String) -> Bool) -> String? {
        let (stem, ending) = parts(of: name, isFolder: isFolder, tarIsExtension: true)
        return firstFree(stem + " copy", ending, from: 1, upTo: last, taken: taken)
    }

    /// The first name not taken of those numbered `first` to `last`; the
    /// one numbered 1 has no number.
    private static func firstFree(
        _ stem: String, _ ending: String, from first: Int, upTo last: Int, taken: (String) -> Bool
    ) -> String? {
        var number = first
        while number <= last {
            let candidate = number == 1 ? stem + ending : numbered(stem, number, ending)
            if !taken(candidate) { return candidate }
            number += 1
        }
        return nil
    }

    private static func numbered(_ stem: String, _ number: Int, _ ending: String) -> String {
        "\(stem) \(number)\(ending)"
    }

    /// A name as what the number goes after and the extension that follows
    /// it. An extension is what comes after the last dot, when that isn't
    /// the first character, something follows it, and that has no space.
    /// With `tarIsExtension`, a ".tar" before it belongs to it (".tar.gz").
    private static func parts(
        of name: String, isFolder: Bool, tarIsExtension: Bool
    ) -> (stem: String, ending: String) {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex,
            name.index(after: dot) != name.endIndex, !name[dot...].contains(where: \.isWhitespace)
        else { return (name, "") }
        var stem = name[..<dot]
        var ending = name[dot...]
        if tarIsExtension, stem.count > 4, stem.suffix(4).lowercased() == ".tar" {
            stem = stem.dropLast(4)
            ending = name[stem.endIndex...]
        }
        return (String(stem), String(ending))
    }

    // MARK: The same name

    /// Whether two names are one name: always when they differ only by the
    /// way their accents are written ("é" as one character or as "e" and an
    /// accent), and by capitals too unless the volume tells them apart.
    ///
    /// For what is decided without the disk. Whether a name exists in a
    /// folder is asked of the volume itself, which has the last word.
    public static func sameName(_ a: String, _ b: String, caseSensitive: Bool) -> Bool {
        nameKey(a, caseSensitive: caseSensitive) == nameKey(b, caseSensitive: caseSensitive)
    }

    /// A name with its accents written one way and, unless `caseSensitive`,
    /// without its capitals: equal for two names exactly when `sameName` holds.
    static func nameKey(_ name: String, caseSensitive: Bool) -> String {
        let composed = name.precomposedStringWithCanonicalMapping
        return caseSensitive ? composed : composed.folding(options: .caseInsensitive, locale: nil)
    }
}

/// What the prompt's answers add up to: the choice for each name asked
/// about, and the one given for all the names after it.
public struct ConflictPlan: Equatable, Sendable {
    /// By the path of the item that is there.
    private var answers: [String: Conflict.Choice] = [:]
    private var forTheRest: Conflict.Choice?

    public init() {}

    /// Records the answer about `existing`. With `applyToAll` it is also
    /// the answer to every question not answered by itself.
    public mutating func answer(_ choice: Conflict.Choice, for existing: URL, applyToAll: Bool) {
        answers[Self.key(existing)] = choice
        if applyToAll { forTheRest = choice }
    }

    /// What was answered about `existing`; nil when it has yet to be asked.
    public func choice(for existing: URL) -> Conflict.Choice? {
        answers[Self.key(existing)] ?? forTheRest
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
