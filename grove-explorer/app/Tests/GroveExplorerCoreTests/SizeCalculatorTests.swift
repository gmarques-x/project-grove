import Foundation
@testable import GroveExplorerCore
import Testing

/// Sizes of real trees: each test gets its own temporary folder, removed
/// when the test ends, passed or failed. Most files are written in blocks
/// of 4,096 bytes, which keeps the sums easy to read.
@Suite(.serialized) final class SizeCalculatorTests {
    private let root: URL
    private let files = FileManager.default
    /// Typed, and used for every expected size: with a bare product of
    /// literals on the right and nothing awaited, `#expect` failed on this
    /// toolchain while printing 8192 for both sides.
    private static let block: Int64 = 4_096

    init() throws {
        root = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-sizes-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func path(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func makeFolder(_ name: String) throws {
        try files.createDirectory(at: path(name), withIntermediateDirectories: true)
    }

    private func makeFile(_ name: String, blocks: Int) throws {
        try Data(repeating: 0x61, count: blocks * Int(Self.block)).write(to: path(name))
    }

    /// `folders` folders of `filesEach` empty files under `name`, made with
    /// `openat` (20,000 take a fraction of a second), and one file of two blocks.
    private func makeLargeTree(_ name: String, folders: Int, filesEach: Int) throws -> URL {
        for folder in 0..<folders {
            try makeFolder("\(name)/folder-\(folder)")
            let directory = open(path("\(name)/folder-\(folder)").path, O_RDONLY | O_DIRECTORY)
            try #require(directory >= 0)
            for index in 0..<filesEach {
                let file = openat(directory, "file-\(index).txt", O_CREAT | O_WRONLY | O_EXCL, 0o644)
                if file >= 0 { close(file) }
            }
            close(directory)
        }
        try makeFile("\(name)/two-blocks.bin", blocks: 2)
        return path(name)
    }

    /// The size, or a recorded failure and nil when it isn't there within
    /// `limit`: the walk is then cancelled, so a walk that would never end
    /// fails the test instead of hanging it.
    private func size(
        of folder: URL, within limit: Duration, from calculator: SizeCalculator
    ) async -> Int64? {
        await withTaskGroup(of: Int64??.self) { group in
            group.addTask { await calculator.size(of: folder) }
            group.addTask {
                try? await Task.sleep(for: limit)
                return Int64??.none
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            guard let answer = first else {
                await calculator.cancelAll()
                Issue.record("the size of \(folder.lastPathComponent) took longer than \(limit)")
                return nil
            }
            return answer
        }
    }

    @Test func aTreeIsTheSumOfItsFiles() async throws {
        try makeFolder("Tree/a/deep/deeper")
        try makeFolder("Tree/empty")
        try makeFile("Tree/one.bin", blocks: 1)
        try makeFile("Tree/a/two.bin", blocks: 2)
        try makeFile("Tree/a/deep/deeper/three.bin", blocks: 3)
        try makeFile("Tree/.hidden", blocks: 1)
        try Data().write(to: path("Tree/a/nothing.txt"))
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("Tree")) == 7 * Self.block)
        #expect(await calculator.size(of: path("Tree/a")) == 5 * Self.block)
        #expect(await calculator.size(of: path("Tree/empty")) == 0)
    }

    /// A folder's size is the lengths of its files, as the list shows each
    /// file's own, not the space they take on the disk (4,096 for the first).
    @Test func aSmallFileCountsItsLength() async throws {
        try makeFolder("Tree/Sub")
        try Data("hello".utf8).write(to: path("Tree/five-bytes.txt"))
        try Data(repeating: 0x61, count: 10_000).write(to: path("Tree/Sub/ten-thousand.bin"))
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("Tree")) == 10_005)
        #expect(await calculator.size(of: path("Tree/Sub")) == 10_000)
    }

    /// A link's own length (the path written in it) is not counted either.
    @Test func aSymlinkCountsNothing() async throws {
        try makeFolder("Tree")
        try Data("hello".utf8).write(to: path("Tree/five-bytes.txt"))
        try files.createSymbolicLink(atPath: path("Tree/link").path, withDestinationPath: "five-bytes.txt")
        try files.createSymbolicLink(atPath: path("Tree/dangling").path, withDestinationPath: "a/long/path/to/nowhere")
        #expect(await SizeCalculator().size(of: path("Tree")) == 5)
    }

    /// Review Focus 3: a link to a folder counts as a link, not as what it
    /// points at, whether that is inside the tree or outside it.
    @Test func aSymlinkToAFolderIsNotFollowed() async throws {
        try makeFolder("Tree/Real")
        try makeFile("Tree/Real/two.bin", blocks: 2)
        try makeFolder("Outside")
        try makeFile("Outside/hundred.bin", blocks: 100)
        try files.createSymbolicLink(atPath: path("Tree/link-inside").path, withDestinationPath: "Real")
        try files.createSymbolicLink(atPath: path("Tree/link-outside").path, withDestinationPath: "../Outside")
        try files.createSymbolicLink(atPath: path("Tree/link-to-file").path, withDestinationPath: "Real/two.bin")
        #expect(await SizeCalculator().size(of: path("Tree")) == 2 * Self.block)
    }

    /// Review Focus 3: links that lead back up the tree they are in.
    @Test func aSymlinkLoopReturnsAndDoesNotHang() async throws {
        try makeFolder("Tree/Sub")
        try makeFile("Tree/Sub/one.bin", blocks: 1)
        try files.createSymbolicLink(atPath: path("Tree/Sub/to-its-own-folder").path, withDestinationPath: path("Tree/Sub").path)
        try files.createSymbolicLink(atPath: path("Tree/Sub/to-dot").path, withDestinationPath: ".")
        try files.createSymbolicLink(atPath: path("Tree/Sub/to-the-top").path, withDestinationPath: "..")
        try files.createSymbolicLink(atPath: path("Tree/a").path, withDestinationPath: "b")
        try files.createSymbolicLink(atPath: path("Tree/b").path, withDestinationPath: "a")
        let calculator = SizeCalculator()
        #expect(await size(of: path("Tree"), within: .seconds(2), from: calculator) == Self.block)
        #expect(await size(of: path("Tree/Sub"), within: .seconds(2), from: calculator) == Self.block)
    }

    /// Asked for a link itself, there is no size: the list shows a link's own.
    @Test func aLinkAsTheFolderHasNoSize() async throws {
        try makeFolder("Real")
        try makeFile("Real/one.bin", blocks: 1)
        try files.createSymbolicLink(atPath: path("link").path, withDestinationPath: "Real")
        #expect(await SizeCalculator().size(of: path("link")) == nil)
    }

    /// An app is one item in the list and a tree on the disk.
    @Test func aPackageIsSummedAsATree() async throws {
        try makeFolder("Tree/Demo.app/Contents/MacOS")
        try makeFolder("Tree/Demo.app/Contents/Resources/Inner.bundle")
        try makeFile("Tree/Demo.app/Contents/MacOS/demo", blocks: 3)
        try makeFile("Tree/Demo.app/Contents/Resources/Inner.bundle/data.bin", blocks: 2)
        try makeFile("Tree/beside.bin", blocks: 1)
        try #require(try path("Tree/Demo.app").resourceValues(forKeys: [.isPackageKey]).isPackage == true)
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("Tree/Demo.app")) == 5 * Self.block)
        #expect(await calculator.size(of: path("Tree")) == 6 * Self.block)
    }

    @Test func whatCannotBeReadHasNoSize() async throws {
        try makeFile("plain.bin", blocks: 1)
        try makeFolder("Locked")
        try makeFile("Locked/secret.bin", blocks: 1)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path("Locked").path)
        // Back to readable before the test's folder is removed, passed or failed.
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path("Locked").path) }
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("not-here")) == nil)
        #expect(await calculator.size(of: path("plain.bin")) == nil)
        #expect(await calculator.size(of: path("Locked")) == nil)
    }

    /// Nil is of two kinds, which the list shows apart: a folder that can't
    /// be read ("--"), and a walk cancelled on its way (its size is still to come).
    @Test func aFolderThatCantBeReadIsToldFromACancelledWalk() async throws {
        try makeFolder("Locked")
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path("Locked").path)
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path("Locked").path) }
        try makeFile("plain.bin", blocks: 1)
        try makeFolder("Tree")
        try makeFile("Tree/one.bin", blocks: 1)
        let calculator = SizeCalculator()
        #expect(await calculator.answer(for: path("not-here")) == .unreadable)
        #expect(await calculator.answer(for: path("plain.bin")) == .unreadable)
        #expect(await calculator.answer(for: path("Locked")) == .unreadable)
        #expect(await calculator.answer(for: path("Tree")) == .total(Self.block))
    }

    /// One closed folder inside doesn't cost the tree its size: the rest is summed.
    @Test func anUnreadableFolderInsideIsLeftOut() async throws {
        try makeFolder("Tree/Locked")
        try makeFile("Tree/Locked/secret.bin", blocks: 4)
        try makeFile("Tree/open.bin", blocks: 1)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path("Tree/Locked").path)
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path("Tree/Locked").path) }
        #expect(await SizeCalculator().size(of: path("Tree")) == Self.block)
    }

    @Test func aSecondCallIsAnsweredFromTheCacheUntilInvalidated() async throws {
        try makeFolder("Tree")
        try makeFile("Tree/keep.bin", blocks: 1)
        try makeFile("Tree/doomed.bin", blocks: 2)
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("Tree")) == 3 * Self.block)
        try files.removeItem(at: path("Tree/doomed.bin"))
        #expect(await calculator.size(of: path("Tree")) == 3 * Self.block)
        await calculator.invalidate(path("Tree"))
        #expect(await calculator.size(of: path("Tree")) == Self.block)
    }

    /// A change in a folder changes the size of every folder above it, and
    /// of none beside it.
    @Test func invalidatingAFolderInvalidatesItsAncestors() async throws {
        try makeFolder("Top/Middle/Bottom")
        try makeFolder("Top/Beside")
        try makeFile("Top/Middle/Bottom/doomed.bin", blocks: 2)
        try makeFile("Top/Beside/doomed.bin", blocks: 1)
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("Top")) == 3 * Self.block)
        #expect(await calculator.size(of: path("Top/Middle")) == 2 * Self.block)
        #expect(await calculator.size(of: path("Top/Middle/Bottom")) == 2 * Self.block)
        #expect(await calculator.size(of: path("Top/Beside")) == Self.block)
        try files.removeItem(at: path("Top/Middle/Bottom/doomed.bin"))
        try files.removeItem(at: path("Top/Beside/doomed.bin"))

        await calculator.invalidate(path("Top/Middle/Bottom"))
        #expect(await calculator.size(of: path("Top/Middle/Bottom")) == 0)
        #expect(await calculator.size(of: path("Top/Middle")) == 0)
        #expect(await calculator.size(of: path("Top")) == 0)
        #expect(await calculator.size(of: path("Top/Beside")) == Self.block)
    }

    /// The same folder written another way is the same folder.
    @Test func theCacheGoesByTheStandardizedPath() async throws {
        try makeFolder("Tree/Sub")
        try makeFile("Tree/doomed.bin", blocks: 1)
        let calculator = SizeCalculator()
        #expect(await calculator.size(of: path("Tree")) == Self.block)
        try files.removeItem(at: path("Tree/doomed.bin"))
        let roundabout = URL(fileURLWithPath: path("Tree").path + "/Sub/../", isDirectory: true)
        #expect(await calculator.size(of: roundabout) == Self.block)
        await calculator.invalidate(roundabout)
        #expect(await calculator.size(of: path("Tree")) == 0)
    }

    @Test func cancelAllDuringAWalkOf20kFilesReturnsNilQuickly() async throws {
        let tree = try makeLargeTree("Large", folders: 200, filesEach: 100)
        let calculator = SizeCalculator()
        let clock = ContinuousClock()
        var answer: Int64? = 0
        var elapsed = Duration.zero
        // The walk takes some 60 ms. On a busy machine it can be over
        // before the cancel is sent, which says nothing about cancelling:
        // such a try is made again.
        for _ in 0..<5 where answer != nil {
            await calculator.invalidate(tree)
            let asked = Task { await calculator.size(of: tree) }
            // The calculator holds a question from when it is asked until it is answered.
            await until { await calculator.unanswered == 1 }
            let cancelled = clock.now
            await calculator.cancelAll()
            answer = await asked.value
            elapsed = clock.now - cancelled
        }
        #expect(answer == nil)
        #expect(elapsed < .seconds(1), "cancelling took \(elapsed)")

        // A cancelled walk leaves nothing behind: asked again, it is walked.
        #expect(await calculator.size(of: tree) == 2 * Self.block)
    }
}

/// Waits for `condition`, for five seconds at most: when it never comes
/// true the test goes on and fails at its next expectation.
private func until(_ condition: @Sendable () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while await !condition(), ContinuousClock.now < deadline { await Task.yield() }
}

/// The calculator's own bookkeeping, with a stand-in for the walk.
///
/// One test at a time: each stand-in holds a thread of Swift's pool (one per
/// core) while it waits, as a real walk holds one while it reads. Run all
/// together, the tests here held more threads than a ten-core Mac has, and
/// one or another then waited out its ten-second limit and failed.
@Suite(.serialized) struct SizeCalculatorQueueTests {
    /// What the stand-in walks saw.
    private final class Walks: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var most = 0
        private(set) var paths: [String] = []

        func begin(_ path: String) {
            lock.withLock {
                running += 1
                most = max(most, running)
                paths.append(path)
            }
        }

        func end() { lock.withLock { running -= 1 } }
        var count: Int { lock.withLock { paths.count } }
    }

    @Test func atMostTwoWalksRunAtOnce() async {
        let walks = Walks()
        let calculator = SizeCalculator { path in
            walks.begin(path)
            Thread.sleep(forTimeInterval: 0.05)
            walks.end()
            return Int64(path.utf8.count)
        }
        await withTaskGroup(of: Int64?.self) { group in
            for index in 0..<8 {
                group.addTask { await calculator.size(of: URL(fileURLWithPath: "/folder-\(index)")) }
            }
            for await answer in group { #expect(answer == 9) }
        }
        #expect(walks.count == 8)
        #expect(walks.most == 2)
    }

    @Test func aFolderAskedForTwiceAtOnceIsWalkedOnce() async {
        let walks = Walks()
        let calculator = SizeCalculator { path in
            walks.begin(path)
            Thread.sleep(forTimeInterval: 0.05)
            walks.end()
            return 42
        }
        let folder = URL(fileURLWithPath: "/folder")
        async let first = calculator.size(of: folder)
        async let second = calculator.size(of: folder)
        #expect(await first == 42)
        #expect(await second == 42)
        #expect(await calculator.size(of: folder) == 42)
        #expect(walks.count == 1)
    }

    /// A folder that changed while it was being walked: the walk's number
    /// would be an old one, so who asked gets nil and nothing is kept.
    @Test func aWalkInvalidatedOnTheWayAnswersNilAndIsNotCached() async {
        let walks = Walks()
        let proceed = DispatchSemaphore(value: 0)
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            if walks.count == 1 {
                _ = proceed.wait(timeout: .now() + 10)
                return 1
            }
            return 2
        }
        let folder = URL(fileURLWithPath: "/folder/inside")
        let first = Task { await calculator.size(of: folder) }
        await until { walks.count == 1 }
        await calculator.invalidate(folder)
        #expect(await calculator.unanswered == 0)
        proceed.signal()
        #expect(await first.value == nil)
        #expect(await calculator.size(of: folder) == 2)
        #expect(walks.count == 2)
    }

    /// A walk cancelled by a change (or by `cancelAll`) says so: it is no
    /// folder that can't be read. One whose stand-in finds nothing is.
    @Test func aCancelledWalkIsNotAnUnreadableFolder() async {
        let walks = Walks()
        let proceed = DispatchSemaphore(value: 0)
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            if path == "/closed" { return nil }
            _ = proceed.wait(timeout: .now() + 10)
            return 1
        }
        #expect(await calculator.answer(for: URL(fileURLWithPath: "/closed")) == .unreadable)
        let busy = URL(fileURLWithPath: "/busy/inside")
        let changed = Task { await calculator.answer(for: busy) }
        await until { walks.count == 2 }
        // A change inside it.
        await calculator.invalidate(URL(fileURLWithPath: "/busy/inside/deeper"))
        proceed.signal()
        #expect(await changed.value == .cancelled)
        let left = Task { await calculator.answer(for: busy) }
        await until { walks.count == 3 }
        await calculator.cancelAll()
        proceed.signal()
        #expect(await left.value == .cancelled)
        // Not kept as the folder's answer: asked again, it is walked.
        proceed.signal()
        #expect(await calculator.answer(for: busy) == .total(1))
        #expect(walks.count == 4)
    }

    /// An invalidated walk is cancelled, not left running out of reach: it
    /// ends at once and gives its turn back. `cancelAll` after it changes
    /// nothing.
    @Test func anInvalidatedWalkStopsAndGivesItsTurnBack() async {
        let walks = Walks()
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            guard path.hasPrefix("/slow") else { return 3 }
            // As the real walk: goes on until it is cancelled (ten seconds at most).
            let deadline = ContinuousClock.now + .seconds(10)
            while !Task.isCancelled, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.002) }
            return Task.isCancelled ? nil : 1
        }
        let slow = [URL(fileURLWithPath: "/slow/a"), URL(fileURLWithPath: "/slow/b")]
        let asked = slow.map { folder in Task { await calculator.size(of: folder) } }
        await until { walks.count == 2 }

        let clock = ContinuousClock()
        let invalidated = clock.now
        await calculator.invalidate(slow[0])
        await calculator.cancelAll()
        for task in asked { #expect(await task.value == nil) }
        // Both turns are free again.
        #expect(await calculator.size(of: URL(fileURLWithPath: "/quick")) == 3)
        let elapsed = clock.now - invalidated
        #expect(elapsed < .seconds(1), "it took \(elapsed)")
        #expect(await calculator.unanswered == 0)
    }

    /// Those waiting for their turn are answered at once, while both turns
    /// are still taken, and never walked.
    @Test func cancelAllAnswersTheWaitingWithNilAtOnce() async {
        let walks = Walks()
        let answered = Walks()
        let proceed = DispatchSemaphore(value: 0)
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            _ = proceed.wait(timeout: .now() + 10)
            return 7
        }
        let asked = (0..<5).map { index in
            Task {
                let answer = await calculator.size(of: URL(fileURLWithPath: "/folder-\(index)"))
                answered.begin("\(index)")
                return answer
            }
        }
        await until { await calculator.unanswered == 5 && walks.count == 2 }
        await calculator.cancelAll()
        #expect(await calculator.unanswered == 0)
        // The two walking are still held; the three waiting have their answer.
        await until { answered.count == 3 }
        #expect(answered.count == 3)
        // One for each asked: were more than two let in, none stays stuck.
        for _ in asked { proceed.signal() }
        for task in asked { #expect(await task.value == nil) }
        #expect(walks.count == 2)
    }

    /// The same for one folder invalidated while it waits; the others keep
    /// their places.
    @Test func aWaitingWalkInvalidatedLeavesTheQueue() async {
        let walks = Walks()
        let proceed = DispatchSemaphore(value: 0)
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            _ = proceed.wait(timeout: .now() + 10)
            return 7
        }
        func ask(_ name: String) -> Task<Int64?, Never> {
            Task { await calculator.size(of: URL(fileURLWithPath: "/\(name)")) }
        }
        let walking = [ask("a"), ask("b")]
        await until { walks.count == 2 }
        let waiting = ask("c")
        let patient = ask("d")
        await until { await calculator.unanswered == 4 }

        await calculator.invalidate(URL(fileURLWithPath: "/c"))
        #expect(await waiting.value == nil)
        #expect(await calculator.unanswered == 3)
        for _ in 0..<4 { proceed.signal() }
        for task in walking { #expect(await task.value == 7) }
        #expect(await patient.value == 7)
        #expect(walks.paths.sorted() == ["/a", "/b", "/d"])
    }

    /// One folder's walk given up (its rows are no longer shown): the other
    /// walks go on, and no size already known is forgotten, its own
    /// folders' included.
    @Test func cancellingOneWalkLeavesTheOthersAndTheCache() async {
        let walks = Walks()
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            guard path.hasPrefix("/big") else { return 5 }
            // As the real walk: goes on until it is cancelled (ten seconds at most).
            let deadline = ContinuousClock.now + .seconds(10)
            while !Task.isCancelled, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.002) }
            return Task.isCancelled ? nil : 9
        }
        // Known before: the folder the cancelled one is in.
        #expect(await calculator.size(of: URL(fileURLWithPath: "/home")) == 5)
        let left = Task { await calculator.size(of: URL(fileURLWithPath: "/big/left")) }
        let kept = Task { await calculator.size(of: URL(fileURLWithPath: "/big/kept")) }
        await until { walks.count == 3 }

        await calculator.cancel(URL(fileURLWithPath: "/big/left"))
        #expect(await left.value == nil)
        #expect(await calculator.unanswered == 1)
        // The other walk was not touched: it is still the one started first.
        #expect(walks.paths.filter { $0 == "/big/kept" }.count == 1)
        #expect(!kept.isCancelled)
        // The turn is free, and what was known still is (no second walk of it).
        #expect(await calculator.size(of: URL(fileURLWithPath: "/home")) == 5)
        #expect(walks.paths.filter { $0 == "/home" }.count == 1)
        // Nothing to cancel is nothing done.
        await calculator.cancel(URL(fileURLWithPath: "/never-asked"))
        await calculator.cancelAll()
        #expect(await kept.value == nil)
    }

    /// A waiting walk cancelled leaves the queue; asked for again later, it is walked.
    @Test func aCancelledFolderCanBeAskedForAgain() async {
        let walks = Walks()
        let proceed = DispatchSemaphore(value: 0)
        let calculator = SizeCalculator { path in
            walks.begin(path)
            defer { walks.end() }
            _ = proceed.wait(timeout: .now() + 10)
            return 7
        }
        func ask(_ name: String) -> Task<Int64?, Never> {
            Task { await calculator.size(of: URL(fileURLWithPath: "/\(name)")) }
        }
        let walking = [ask("a"), ask("b")]
        await until { walks.count == 2 }
        let waiting = ask("c")
        await until { await calculator.unanswered == 3 }
        await calculator.cancel(URL(fileURLWithPath: "/c"))
        #expect(await waiting.value == nil)
        let again = ask("c")
        for _ in 0..<3 { proceed.signal() }
        for task in walking { #expect(await task.value == 7) }
        #expect(await again.value == 7)
        #expect(walks.paths.sorted() == ["/a", "/b", "/c"])
    }
}
