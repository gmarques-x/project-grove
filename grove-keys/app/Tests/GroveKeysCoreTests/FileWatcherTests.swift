import Foundation
import Testing
@testable import GroveKeysCore

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func hit() { lock.withLock { n += 1 } }
}

@Suite struct FileWatcherTests {
    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gkw-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func renameSave(_ text: String, into file: URL) throws {
        let tmp = file.deletingLastPathComponent().appendingPathComponent("x.tmp")
        try Data(text.utf8).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }

    func wait(until condition: () -> Bool, timeout: Double = 2) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func settle() async { try? await Task.sleep(nanoseconds: 300_000_000) }

    @Test func seesRenameSave() async throws {
        let dir = try tempDir()
        let file = dir.appendingPathComponent("keys.toml")
        try Data("a\n".utf8).write(to: file)
        let hits = Counter()
        let w = FileWatcher(file: file) { hits.hit() }
        w.start()
        defer { w.stop() }
        try renameSave("b\n", into: file)
        await wait { hits.count >= 1 }
        await settle()
        #expect(hits.count == 1)
        try renameSave("c\n", into: file)
        await wait { hits.count >= 2 }
        await settle()
        #expect(hits.count == 2)
    }

    @Test func seesInPlaceWrite() async throws {
        let dir = try tempDir()
        let file = dir.appendingPathComponent("keys.toml")
        try Data("a\n".utf8).write(to: file)
        let hits = Counter()
        let w = FileWatcher(file: file) { hits.hit() }
        w.start()
        defer { w.stop() }
        try Data("b\n".utf8).write(to: file)
        await wait { hits.count >= 1 }
        await settle()
        #expect(hits.count == 1)
    }

    @Test func ignoresOwnWrite() async throws {
        let dir = try tempDir()
        let file = dir.appendingPathComponent("keys.toml")
        try Data("a\n".utf8).write(to: file)
        let hits = Counter()
        let w = FileWatcher(file: file) { hits.hit() }
        w.start()
        defer { w.stop() }
        let mine = Data("mine\n".utf8)
        w.ignoreNextChange(contents: mine)
        try renameSave("mine\n", into: file)
        await settle()
        #expect(hits.count == 0)
        try renameSave("theirs\n", into: file)
        await wait { hits.count >= 1 }
        await settle()
        #expect(hits.count == 1)
    }
}
