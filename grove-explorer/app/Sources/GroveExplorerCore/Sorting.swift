import Foundation

public enum SortColumn: String, Codable, Sendable {
    case name, size, modified, kind
}

public struct SortOrder: Equatable, Codable, Sendable {
    public var column: SortColumn
    public var ascending: Bool

    public init(column: SortColumn, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }

    public static let byName = SortOrder(column: .name, ascending: true)
}

/// Orders a folder's entries for the list.
public enum Sorting {
    /// Folders first whatever the direction: folders and links to folders,
    /// nothing else (a package sorts as the file it looks like). Names are
    /// compared as Finder does: numbers by value, case and accents ignored.
    /// By size, date or kind, entries that are equal go by name ascending,
    /// and those without a value (a folder whose size isn't known yet) go last
    /// in both directions.
    ///
    /// `folderSizes` holds the totals known so far, keyed by `Entry.url`; an
    /// entry in it is ordered by that total rather than by its own size.
    public static func sorted(
        _ entries: [Entry], by order: SortOrder, folderSizes: [URL: Int64] = [:]
    ) -> [Entry] {
        let keys = keys(for: entries, column: order.column, folderSizes: folderSizes)
        let ascending = order.ascending
        let byName = order.column == .name

        let indices = sortedIndices(count: entries.count) { first, second in
            let a = keys[first], b = keys[second]
            if a.isFolder != b.isFolder { return a.isFolder }
            if !byName {
                switch (a.value, b.value) {
                case (nil, nil): break
                case (nil, _?): return false
                case (_?, nil): return true
                case let (x?, y?):
                    if x != y { return ascending ? x < y : x > y }
                }
            }
            let names = a.name.localizedStandardCompare(b.name as String)
            return names == (byName && !ascending ? .orderedDescending : .orderedAscending)
        }
        return indices.map { entries[$0] }
    }

    // MARK: Keys

    /// What one entry is compared by, worked out once before sorting.
    private struct Key {
        let isFolder: Bool
        /// As an `NSString`, so a comparison doesn't convert it each time.
        let name: NSString
        /// The column's value as a number; nil when there is none, and always
        /// nil for the name column. A size in bytes (exact up to 2^53, about
        /// 9 PB), seconds for a date, the rank of a type's description.
        let value: Double?
    }

    private static func keys(
        for entries: [Entry], column: SortColumn, folderSizes: [URL: Int64]
    ) -> [Key] {
        // A folder has a few dozen types at most: put those in order once
        // rather than compare two descriptions for every pair of entries.
        var kindRank: [String: Double] = [:]
        if column == .kind {
            let descriptions = Set(entries.map(\.typeDescription))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for (rank, description) in descriptions.enumerated() {
                kindRank[description] = Double(rank)
            }
        }

        return entries.map { entry in
            let value: Double?
            switch column {
            case .name:
                value = nil
            case .size:
                let known = folderSizes.isEmpty ? nil : folderSizes[entry.url]
                value = (known ?? entry.size).map(Double.init)
            case .modified:
                value = entry.modified?.timeIntervalSinceReferenceDate
            case .kind:
                value = kindRank[entry.typeDescription]
            }
            return Key(isFolder: isFolder(entry.kind), name: entry.name as NSString, value: value)
        }
    }

    private static func isFolder(_ kind: Entry.Kind) -> Bool {
        switch kind {
        case .folder, .symlink(toFolder: true): true
        case .file, .package, .symlink(toFolder: false), .alias, .volume: false
        }
    }

    // MARK: The sort

    /// The numbers 0..<count in the order `precedes` gives; equal ones keep
    /// their place. A merge sort written out rather than `sort(by:)`: it asks
    /// a third fewer questions (about 770,000 against 1,150,000 for 50,000
    /// names), and comparing two names as Finder does is where the time goes.
    /// Nor does sorting on several cores help: those comparisons wait on one
    /// another. Two stretches already in order are joined with one question,
    /// so a list that arrives sorted costs next to nothing.
    private static func sortedIndices(count: Int, precedes: (Int, Int) -> Bool) -> [Int] {
        var items = Array(0..<count)
        var merged = items
        var width = 1
        while width < count {
            var start = 0
            while start < count {
                let middle = min(start + width, count)
                let end = min(start + 2 * width, count)
                defer { start = end }
                if middle == end || !precedes(items[middle], items[middle - 1]) {
                    // One stretch, or two in order as they are.
                    for index in start..<end { merged[index] = items[index] }
                    continue
                }
                var left = start, right = middle, out = start
                while left < middle, right < end {
                    if precedes(items[right], items[left]) {
                        merged[out] = items[right]
                        right += 1
                    } else {
                        merged[out] = items[left]
                        left += 1
                    }
                    out += 1
                }
                while left < middle {
                    merged[out] = items[left]
                    left += 1
                    out += 1
                }
                while right < end {
                    merged[out] = items[right]
                    right += 1
                    out += 1
                }
            }
            swap(&items, &merged)
            width *= 2
        }
        return items
    }
}
