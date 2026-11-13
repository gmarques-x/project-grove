import Foundation
import GroveExplorerCore
import Testing

@Suite struct SortingTests {
    private func entry(
        _ name: String, kind: Entry.Kind = .file, size: Int64? = nil,
        modified: Date? = nil, type: String = "Document"
    ) -> Entry {
        Entry(
            url: URL(fileURLWithPath: "/tmp/grove/\(name)"), name: name, kind: kind,
            size: size, modified: modified, isHidden: false, typeDescription: type
        )
    }

    private func names(_ entries: [Entry]) -> [String] { entries.map(\.name) }

    /// The fixture's lines, which are in the order expected of a sort by name.
    private func fixtureNames() throws -> [String] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/names.txt")
        return try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    // MARK: Names

    @Test func theAwkwardNamesComeOutInTheFixturesOrder() throws {
        let expected = try fixtureNames()
        #expect(expected.count == 30)
        // One name is stored decomposed (e + U+0301), as a volume may give it.
        #expect(expected.contains { $0.unicodeScalars.contains("\u{301}") })

        let reversed = expected.reversed().map { entry($0) }
        #expect(names(Sorting.sorted(reversed, by: .byName)) == expected)

        // Whatever order they arrive in.
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<5 {
            let shuffled = expected.shuffled(using: &generator).map { entry($0) }
            #expect(names(Sorting.sorted(shuffled, by: .byName)) == expected)
        }
    }

    @Test func descendingIsTheSameOrderReversed() throws {
        let expected = try fixtureNames()
        let sorted = Sorting.sorted(
            expected.map { entry($0) }, by: SortOrder(column: .name, ascending: false))
        #expect(names(sorted) == expected.reversed())
    }

    @Test func numbersGoByValueAndCaseAndAccentsAreIgnored() {
        let sorted = Sorting.sorted(
            ["file10", "Zebra", "file2", "éclair 2", "apple", "eclair 3", "Eclair 1", "File3"]
                .map { entry($0) },
            by: .byName)
        #expect(names(sorted) == [
            "apple", "Eclair 1", "éclair 2", "eclair 3", "file2", "File3", "file10", "Zebra",
        ])
    }

    @Test func byNameIsTheDefaultOrder() {
        #expect(SortOrder.byName == SortOrder(column: .name, ascending: true))
    }

    // MARK: Folders on top

    @Test func foldersAndLinksToFoldersComeFirstInBothDirections() {
        let entries = [
            entry("b.txt"),
            entry("Grove.app", kind: .package),
            entry("zeta", kind: .folder),
            entry("link-to-file", kind: .symlink(toFolder: false)),
            entry("link-to-folder", kind: .symlink(toFolder: true)),
            entry("Alias", kind: .alias),
            entry("alpha", kind: .folder),
            entry("Disk", kind: .volume),
        ]
        #expect(names(Sorting.sorted(entries, by: .byName)) == [
            "alpha", "link-to-folder", "zeta",
            "Alias", "b.txt", "Disk", "Grove.app", "link-to-file",
        ])
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .name, ascending: false))) == [
            "zeta", "link-to-folder", "alpha",
            "link-to-file", "Grove.app", "Disk", "b.txt", "Alias",
        ])
    }

    @Test func foldersStayOnTopWhateverTheColumn() {
        let entries = [
            entry("big.bin", size: 9_000, modified: Date(timeIntervalSince1970: 900), type: "Archive"),
            entry("docs", kind: .folder, modified: Date(timeIntervalSince1970: 100), type: "Folder"),
            entry("small.txt", size: 10, modified: Date(timeIntervalSince1970: 500), type: "Text"),
        ]
        for column in [SortColumn.name, .size, .modified, .kind] {
            for ascending in [true, false] {
                let sorted = Sorting.sorted(entries, by: SortOrder(column: column, ascending: ascending))
                #expect(sorted.first?.name == "docs", "\(column) ascending \(ascending)")
            }
        }
    }

    // MARK: Size

    @Test func bySizeFilesGoByTheirSize() {
        let entries = [entry("b", size: 300), entry("a", size: 20), entry("c", size: 1_000)]
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .size, ascending: true))) == ["a", "b", "c"])
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .size, ascending: false))) == ["c", "b", "a"])
    }

    @Test func bySizeFoldersUseTheSizesGivenAndUnknownOnesGoLast() {
        let big = entry("big", kind: .folder), small = entry("small", kind: .folder)
        let pending = entry("pending", kind: .folder), another = entry("another", kind: .folder)
        let file = entry("file.txt", size: 1)
        let entries = [pending, file, big, another, small]
        let sizes = [big.url: Int64(5_000_000), small.url: Int64(40)]

        let ascending = Sorting.sorted(
            entries, by: SortOrder(column: .size, ascending: true), folderSizes: sizes)
        #expect(names(ascending) == ["small", "big", "another", "pending", "file.txt"])

        // Unknown stays last when the direction turns, each group in name order.
        let descending = Sorting.sorted(
            entries, by: SortOrder(column: .size, ascending: false), folderSizes: sizes)
        #expect(names(descending) == ["big", "small", "another", "pending", "file.txt"])
    }

    @Test func aFileWithoutASizeGoesAfterThoseWithOne() {
        let entries = [entry("unreadable"), entry("b", size: 5), entry("a", size: 7)]
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .size, ascending: true))) == ["b", "a", "unreadable"])
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .size, ascending: false))) == ["a", "b", "unreadable"])
    }

    /// A package has no size of its own; the calculator's total is used for it too.
    @Test func aPackageUsesTheSizeGivenForIt() {
        let app = entry("Grove.app", kind: .package)
        let entries = [entry("a.txt", size: 500), app, entry("b.txt", size: 90_000)]
        let sorted = Sorting.sorted(
            entries, by: SortOrder(column: .size, ascending: true), folderSizes: [app.url: 2_000])
        #expect(names(sorted) == ["a.txt", "Grove.app", "b.txt"])
    }

    // MARK: Date and kind

    @Test func byDateOldestFirstThenNewestFirstAndNoDateLast() {
        func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
        let entries = [
            entry("new", modified: at(3_000)), entry("undated"),
            entry("old", modified: at(1_000)), entry("mid", modified: at(2_000)),
        ]
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .modified, ascending: true))) == ["old", "mid", "new", "undated"])
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .modified, ascending: false))) == ["new", "mid", "old", "undated"])
    }

    @Test func byKindGoesByWhatTheTypeIsCalled() {
        let entries = [
            entry("b.png", type: "PNG image"), entry("notes.md", type: "Markdown"),
            entry("a.png", type: "PNG image"), entry("x.zip", type: "ZIP archive"),
            entry("app.js", type: "JavaScript script"),
        ]
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .kind, ascending: true))) == ["app.js", "notes.md", "a.png", "b.png", "x.zip"])
        #expect(names(Sorting.sorted(entries, by: SortOrder(column: .kind, ascending: false))) == ["x.zip", "a.png", "b.png", "notes.md", "app.js"])
    }

    // MARK: Ties

    @Test func tiesFallBackToTheNameAscendingInBothDirections() {
        let date = Date(timeIntervalSince1970: 1_000)
        let entries = ["file10", "file2", "File3"].map { entry($0, size: 7, modified: date) }
        for column in [SortColumn.size, .modified, .kind] {
            for ascending in [true, false] {
                let sorted = Sorting.sorted(entries, by: SortOrder(column: column, ascending: ascending))
                #expect(names(sorted) == ["file2", "File3", "file10"], "\(column) ascending \(ascending)")
            }
        }
    }

    @Test func nothingIsLostOrMadeUp() {
        #expect(Sorting.sorted([], by: .byName).isEmpty)
        let entries = (0..<200).map { entry("item \($0 % 50)-\($0)", size: Int64($0 % 7)) }
        for column in [SortColumn.name, .size, .modified, .kind] {
            let sorted = Sorting.sorted(entries, by: SortOrder(column: column, ascending: false))
            #expect(Set(sorted) == Set(entries))
            #expect(sorted.count == entries.count)
        }
    }

    @Test func aSortOrderSurvivesBeingSaved() throws {
        let order = SortOrder(column: .modified, ascending: false)
        let data = try JSONEncoder().encode(order)
        #expect(try JSONDecoder().decode(SortOrder.self, from: data) == order)
        #expect(String(decoding: data, as: UTF8.self).contains("\"modified\""))
    }
}

/// A fixed sequence, so a shuffle is the same on every run.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
