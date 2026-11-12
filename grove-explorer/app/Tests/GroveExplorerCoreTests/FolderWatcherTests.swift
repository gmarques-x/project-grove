import CoreServices
import Foundation
@testable import GroveExplorerCore
import Testing

/// Counts a watcher's calls and lets a test wait for them.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var latest = ContinuousClock.now

    var total: Int { lock.withLock { count } }

    func record() {
        lock.withLock {
            count += 1
            latest = .now
        }
    }

    /// Whether a call beyond the first `seen` came before `timeout` was over.
    /// The limit is generous so a busy machine doesn't fail the test; a
    /// watcher that works answers in about its latency.
    func more(than seen: Int, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while total <= seen {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// Waits until no call came for `quiet`, and says how many there were.
    /// FSEvents hands a new watcher the changes made just before it began
    /// (the test's own preparation); this lets them pass first.
    func settled(quiet: Duration = .seconds(1)) async -> Int {
        while true {
            let (count, latest) = lock.withLock { (self.count, self.latest) }
            if ContinuousClock.now - latest >= quiet { return count }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Watching real folders: each test gets its own temporary folder, removed
/// when the test ends, passed or failed. The folder is given as macOS hands
/// it out, under /var, which is a link to /private/var where the events are
/// reported: the watcher has to match the two itself.
@Suite final class FolderWatcherTests {
    private let root: URL
    private let files = FileManager.default

    init() throws {
        root = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-watcher-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func path(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func makeFile(_ name: String, _ contents: String = "x") throws {
        try Data(contents.utf8).write(to: path(name))
    }

    /// A watcher of `folder` whose calls are counted, past the calls for
    /// what was made before it.
    private func watch(_ folder: URL) async -> (watcher: FolderWatcher, calls: Calls, before: Int) {
        let calls = Calls()
        let watcher = FolderWatcher(folder: folder) { calls.record() }
        return (watcher, calls, await calls.settled())
    }

    @Test func creatingAFileCalls() async throws {
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        try makeFile("new.txt")
        #expect(await calls.more(than: before))
    }

    @Test func renamingAFileCalls() async throws {
        try makeFile("old.txt")
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        try files.moveItem(at: path("old.txt"), to: path("new.txt"))
        #expect(await calls.more(than: before))
    }

    @Test func deletingAFileCalls() async throws {
        try makeFile("doomed.txt")
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        try files.removeItem(at: path("doomed.txt"))
        #expect(await calls.more(than: before))
    }

    /// A file written in place changes its size and date in the list.
    @Test func writingToAFileCalls() async throws {
        try makeFile("notes.txt", "short")
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        let handle = try FileHandle(forWritingTo: path("notes.txt"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("and longer".utf8))
        try handle.close()
        #expect(await calls.more(than: before))
    }

    @Test func creatingAFolderCalls() async throws {
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        try files.createDirectory(at: path("Folder"), withIntermediateDirectories: false)
        #expect(await calls.more(than: before))
    }

    /// Only the folder's own level is watched. A second watcher, on the
    /// subfolder, tells when the change has been reported; the first is
    /// then given half a second more to (wrongly) call.
    @Test func aChangeInASubfolderDoesNotCall() async throws {
        try files.createDirectory(at: path("Sub/Deeper"), withIntermediateDirectories: true)
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        let (witness, witnessed, witnessedBefore) = await watch(path("Sub"))
        defer { witness.stop() }

        try makeFile("Sub/inner.txt")
        try makeFile("Sub/Deeper/innermost.txt")
        try #require(await witnessed.more(than: witnessedBefore))
        try await Task.sleep(for: .milliseconds(500))
        #expect(calls.total == before)

        // It was watching all along: a change at its own level is told.
        try makeFile("direct.txt")
        #expect(await calls.more(than: before))
    }

    /// As above, with a second watcher of the same folder as the witness.
    @Test func afterStopNothingIsCalled() async throws {
        let (watcher, calls, before) = await watch(root)
        let (witness, witnessed, witnessedBefore) = await watch(root)
        defer { witness.stop() }

        watcher.stop()
        try makeFile("new.txt")
        try #require(await witnessed.more(than: witnessedBefore))
        try await Task.sleep(for: .milliseconds(500))
        #expect(calls.total == before)

        watcher.stop() // a second stop is harmless
    }

    /// The watcher's own queue makes the calls; stopping from one of them
    /// must not wait for that queue.
    @Test func stoppingFromInsideACallReturnsAndStops() async throws {
        final class Holder: @unchecked Sendable { var watcher: FolderWatcher? }
        let holder = Holder()
        let calls = Calls()
        let returned = Calls()
        let watcher = FolderWatcher(folder: root) {
            calls.record()
            guard let watcher = holder.watcher else { return }
            watcher.stop()
            returned.record()
        }
        let before = await calls.settled()
        holder.watcher = watcher
        try makeFile("first.txt")
        // A stop that waited for its own queue would never return (and the
        // watcher, held by its own call, is then left as it is).
        try #require(await returned.more(than: 0))
        let stoppedAt = await calls.settled()
        #expect(stoppedAt == before + 1)

        try makeFile("second.txt")
        try await Task.sleep(for: .milliseconds(800))
        #expect(calls.total == stoppedAt)
        holder.watcher = nil
    }

    /// Many changes at once are gathered into a few calls.
    @Test func aBurstOfChangesIsGathered() async throws {
        let (watcher, calls, before) = await watch(root)
        defer { watcher.stop() }
        for index in 0..<200 { try makeFile("file-\(index).txt") }
        #expect(await calls.more(than: before))
        let after = await calls.settled()
        #expect(after - before < 20, "\(after - before) calls for 200 files")
    }

    /// The folder going away is a change too: what shows it must move on.
    @Test func removingTheFolderItselfCalls() async throws {
        try files.createDirectory(at: path("Watched"), withIntermediateDirectories: false)
        let (watcher, calls, before) = await watch(path("Watched"))
        defer { watcher.stop() }
        try files.removeItem(at: path("Watched"))
        #expect(await calls.more(than: before))
    }

    /// A folder opened through a link is watched where it really is.
    @Test func aFolderReachedThroughALinkIsWatched() async throws {
        try files.createDirectory(at: path("Real"), withIntermediateDirectories: false)
        try files.createSymbolicLink(atPath: path("link").path, withDestinationPath: "Real")
        let (watcher, calls, before) = await watch(path("link"))
        defer { watcher.stop() }
        try makeFile("Real/new.txt")
        #expect(await calls.more(than: before))
    }

    /// Which of FSEvents' reports are a change of the watched folder.
    @Test func onlyTheFoldersOwnLevelTells() {
        func tells(_ event: String, _ flags: Int = kFSEventStreamEventFlagNone, of folder: String = "/a/b") -> Bool {
            FolderWatcher.tells(event, flags: FSEventStreamEventFlags(flags), of: folder)
        }
        #expect(tells("/a/b/"))
        #expect(tells("/a/b"))
        #expect(tells("/a/b/c/") == false)
        #expect(tells("/a/b/c/d/") == false)
        #expect(tells("/a/") == false)
        #expect(tells("/a/bc/") == false)
        // The disk's top folder is all slash.
        #expect(tells("/", of: "/"))
        #expect(tells("/a/", of: "/") == false)
        // The folder itself moved or went.
        #expect(tells("/a/b", kFSEventStreamEventFlagRootChanged))
        // FSEvents lost count somewhere beneath: look again, wherever it was.
        #expect(tells("/a/b/c/", kFSEventStreamEventFlagMustScanSubDirs))
        #expect(tells("/a/b/c/", kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped))
        #expect(tells("/a/b/c/", kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped))
    }
}
