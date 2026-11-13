import Foundation
@testable import GroveExplorerCore
import Testing

/// The spec's time limits, all in one suite that runs one test at a time,
/// so no two of them run beside each other or beside each other's load
/// (the full bundle once failed one by 0.2 ms with them spread over their
/// own suites). Each takes the best of three runs, the machine may be busy
/// during one, and prints its time. Folders on disk are temporary ones of
/// the test's own, removed when it ends, passed or failed.
@Suite(.serialized) struct TimingTests {
    // MARK: Fixtures

    private func entry(
        _ path: String, kind: Entry.Kind = .file, size: Int64? = nil, type: String = "Document"
    ) -> Entry {
        let url = URL(fileURLWithPath: path, isDirectory: kind == .folder)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: size, modified: nil,
            isHidden: false, typeDescription: type)
    }

    /// A temporary folder of the test's own, given to `body` and removed after it.
    private func inTemporaryFolder(_ label: String, _ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grove-explorer-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    /// `count` empty files in `folder`, made with `openat` (50,000 take a fraction of a second).
    private func makeEmptyFiles(_ count: Int, in folder: URL) throws {
        let directory = open(folder.path, O_RDONLY | O_DIRECTORY)
        try #require(directory >= 0)
        for index in 0..<count {
            let file = openat(directory, "file-\(index).txt", O_CREAT | O_WRONLY | O_EXCL, 0o644)
            if file >= 0 { close(file) }
        }
        close(directory)
    }

    // MARK: Sorting

    /// The spec's limit for a sort of 50,000 items, by three columns.
    @Test func sorts50kUnderHalfASecond() {
        var generator = SeededGenerator(seed: 7)
        let entries = (0..<50_000).map { index -> Entry in
            let number = Int.random(in: 0..<100_000, using: &generator)
            return entry(
                "/tmp/grove/Report \(number) é draft-\(index).txt",
                kind: index % 10 == 0 ? .folder : .file,
                size: Int64(number % 500), type: "Type \(number % 40)")
        }
        let clock = ContinuousClock()
        for column in [SortColumn.name, .size, .kind] {
            var sorted: [Entry] = []
            var best = Duration.seconds(3600)
            for _ in 0..<3 {
                let elapsed = clock.measure {
                    sorted = Sorting.sorted(entries, by: SortOrder(column: column, ascending: true))
                }
                best = min(best, elapsed)
            }
            print("sorts50kUnderHalfASecond: by \(column), best of 3: \(best)")
            #expect(best < .milliseconds(500), "by \(column): \(best)")
            // Outside the timed block: the order is the rule's, written
            // out again here and given to the library's own sort.
            #expect(sorted.count == 50_000)
            #expect(sorted.map(\.name) == reference(entries, by: column).map(\.name))
        }
    }

    /// `Sorting.sorted`'s rule, ascending, by the standard library's sort:
    /// folders first; then the column's value (a size by number, a kind by
    /// its description as Finder compares names); equal ones by name.
    private func reference(_ entries: [Entry], by column: SortColumn) -> [Entry] {
        func isFolder(_ entry: Entry) -> Bool { entry.kind == .folder }
        func before(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        return entries.sorted { a, b in
            if isFolder(a) != isFolder(b) { return isFolder(a) }
            switch column {
            case .size:
                if a.size != b.size { return (a.size ?? .max) < (b.size ?? .max) }
            case .kind:
                if a.typeDescription != b.typeDescription { return before(a.typeDescription, b.typeDescription) }
            case .name, .modified:
                break
            }
            return before(a.name, b.name)
        }
    }

    // MARK: The tree's rows

    /// 50,000 rows across 50 open folders of 1,000 items, arranged by the
    /// spec's limit for a sort: by name, by size and under a filter.
    @Test func fiftyThousandRowsAcrossOpenFoldersUnderHalfASecond() {
        var generator = SeededGenerator(seed: 11)
        var root: [Entry] = []
        var children: [URL: [Entry]] = [:]
        var open: Set<URL> = []
        var hasContents: [URL: Bool] = [:]
        for folder in 0..<50 {
            let path = "/big/Folder \(folder)"
            let url = URL(fileURLWithPath: path, isDirectory: true)
            root.append(entry(path, kind: .folder))
            open.insert(url)
            children[url] = (0..<1_000).map { index in
                let number = Int.random(in: 0..<100_000, using: &generator)
                let child = "\(path)/Report \(number) é draft-\(index).txt"
                if index % 10 == 0 { hasContents[URL(fileURLWithPath: child, isDirectory: true)] = index % 20 == 0 }
                return entry(child, kind: index % 10 == 0 ? .folder : .file, size: Int64(number % 500))
            }
        }
        let clock = ContinuousClock()
        let cases: [(String, GroveExplorerCore.SortOrder, String, Int)] = [
            ("by name", .byName, "", 50_050),
            ("by size", SortOrder(column: .size, ascending: false), "", 50_050),
            ("filtered", .byName, "report 7", -1),
        ]
        for (label, sort, filter, expected) in cases {
            let tree = TreeInput(
                root: root, children: children, open: open, hasContents: hasContents, sort: sort,
                folderSizes: [:], filter: filter, showHidden: false)
            var result: (items: [TreeItem], unfilteredRows: Int) = ([], 0)
            var best = Duration.seconds(3600)
            for _ in 0..<3 {
                let elapsed = clock.measure { result = Tree.itemsAndUnfilteredCount(tree) }
                best = min(best, elapsed)
            }
            print("fiftyThousandRowsAcrossOpenFoldersUnderHalfASecond: \(label), best of 3: \(best)")
            #expect(best < .milliseconds(500), "\(label): \(best)")
            #expect(result.unfilteredRows == 50_050)
            if expected > 0 {
                #expect(result.items.count == expected)
            } else {
                #expect(!result.items.isEmpty && result.items.count < 50_050)
            }
        }
    }

    // MARK: Folders on disk

    /// The spec's limit: a folder of 50,000 items opens without a visible pause.
    @Test func reads50kEntriesUnderTwoSeconds() async throws {
        try await inTemporaryFolder("reader") { root in
            let count = 50_000
            try makeEmptyFiles(count, in: root)
            var entries: [Entry] = []
            let clock = ContinuousClock()
            var best = Duration.seconds(3600)
            for _ in 0..<3 {
                let elapsed = try clock.measure { entries = try FolderReader().read(root) }
                best = min(best, elapsed)
            }
            print("reads50kEntriesUnderTwoSeconds: best of 3: \(best)")
            #expect(entries.count == count)
            #expect(entries.allSatisfy { $0.kind == .file && $0.size == 0 })
            #expect(best < .seconds(2), "reading \(count) entries took \(best)")
        }
    }

    /// The spec's limit for a tree of 20,000 files: 200 folders of 100
    /// empty files, and one file of two blocks.
    @Test func sizes20kFilesUnderThreeSeconds() async throws {
        try await inTemporaryFolder("sizes") { root in
            let block: Int64 = 4_096
            for folder in 0..<200 {
                let inside = root.appendingPathComponent("folder-\(folder)", isDirectory: true)
                try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
                try makeEmptyFiles(100, in: inside)
            }
            try Data(repeating: 0x61, count: 2 * Int(block)).write(to: root.appendingPathComponent("two-blocks.bin"))
            // Each walk by a calculator that knows nothing yet.
            let clock = ContinuousClock()
            var best = Duration.seconds(3600)
            for _ in 0..<3 {
                let calculator = SizeCalculator()
                let asked = clock.now
                let answer = await calculator.size(of: root)
                best = min(best, clock.now - asked)
                #expect(answer == 2 * block)
            }
            print("sizes20kFilesUnderThreeSeconds: best of 3: \(best)")
            #expect(best < .seconds(3), "the size of 20,000 files took \(best)")
        }
    }

    /// Looking into a folder for its chevron stops at its first item: a
    /// folder of 50,000 answers as fast as one of a few.
    @Test func peeksInto50kEntriesUnderFiveMilliseconds() async throws {
        try await inTemporaryFolder("peek") { root in
            try makeEmptyFiles(50_000, in: root)
            var answer: Bool?
            let clock = ContinuousClock()
            var best = Duration.seconds(3600)
            for _ in 0..<3 {
                let elapsed = clock.measure { answer = FolderPeek.hasContents(root, showHidden: false) }
                best = min(best, elapsed)
            }
            print("peeksInto50kEntriesUnderFiveMilliseconds: best of 3: \(best)")
            #expect(answer == true)
            #expect(best < .milliseconds(5), "looking into 50,000 entries took \(best)")
        }
    }
}

/// A fixed sequence, so a fixture is the same on every run.
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
