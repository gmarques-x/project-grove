import Foundation
import Testing
@testable import GroveKeysCore

final class FakeAeroSpace: AeroSpaceRunning, @unchecked Sendable {
    private let lock = NSLock()
    var running = true
    var dryRunResult: (ok: Bool, message: String) = (true, "")
    private var _dryRuns = 0, _reloads = 0
    var dryRuns: Int { lock.withLock { _dryRuns } }
    var reloads: Int { lock.withLock { _reloads } }
    var onDryRun: (@Sendable () -> Void)?
    func isRunning() async -> Bool { running }
    func dryRun() async -> (ok: Bool, message: String) { lock.withLock { _dryRuns += 1 }; onDryRun?(); return dryRunResult }
    func reload() async { lock.withLock { _reloads += 1 } }
}

@Suite struct SavePipelineTests {
    static let host = "Gustavos-MacBook-Air"

    func setUp(keys: String? = nil, base: String? = nil) throws -> (KeysPaths, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        let cfg = dir.appendingPathComponent("grove-keys"), aero = dir.appendingPathComponent("aerospace")
        try FileManager.default.createDirectory(at: cfg, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aero, withIntermediateDirectories: true)
        let paths = KeysPaths(keys: cfg.appendingPathComponent("keys.toml"),
                              base: aero.appendingPathComponent("aerospace.base.toml"),
                              output: aero.appendingPathComponent("aerospace.toml"))
        try (keys ?? fixture("keys.toml")).write(to: paths.keys, atomically: true, encoding: .utf8)
        try (base ?? fixture("aerospace.base.toml")).write(to: paths.base, atomically: true, encoding: .utf8)
        return (paths, dir)
    }

    @Test func appliesAndReloads() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        let result = await SavePipeline(paths: paths, host: Self.host, aerospace: fake).run()
        guard case .applied = result else { Issue.record("\(result)"); return }
        let out = try String(contentsOf: paths.output, encoding: .utf8)
        #expect(out.hasPrefix(AeroSpaceRenderer.header))
        #expect(fake.dryRuns == 1)
        #expect(fake.reloads == 1)
    }

    @Test func unchangedSkipsReload() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        let pipeline = SavePipeline(paths: paths, host: Self.host, aerospace: fake)
        _ = await pipeline.run()
        let result = await pipeline.run()
        guard case .unchanged = result else { Issue.record("\(result)"); return }
        #expect(fake.reloads == 1)
        #expect(fake.dryRuns == 1)
    }

    @Test func invalidKeysTouchesNothing() async throws {
        let (paths, _) = try setUp(keys: "[hyper]\nenabled = true\ntap = \"escape\"\nenabled = false\n")
        let old = Data("old config\n".utf8)
        try old.write(to: paths.output)
        let fake = FakeAeroSpace()
        let result = await SavePipeline(paths: paths, host: Self.host, aerospace: fake).run()
        guard case .keysInvalid(let err) = result else { Issue.record("\(result)"); return }
        #expect(err.line == 4)
        #expect(result.redLine?.hasPrefix("keys.toml line 4:") == true)
        #expect(try Data(contentsOf: paths.output) == old)
        #expect(fake.dryRuns == 0 && fake.reloads == 0)
    }

    @Test func missingBaseIsAFailure() async throws {
        let (paths, _) = try setUp()
        try FileManager.default.removeItem(at: paths.base)
        let result = await SavePipeline(paths: paths, host: Self.host, aerospace: FakeAeroSpace()).run()
        #expect(result == .keysInvalid(TomlError(line: 0, message: "aerospace.base.toml is missing")))
        #expect(result.redLine == "aerospace.base.toml is missing")
        #expect(!FileManager.default.fileExists(atPath: paths.output.path))
    }

    @Test func rejectedRestoresOld() async throws {
        let (paths, _) = try setUp()
        let old = Data("old config\n".utf8)
        try old.write(to: paths.output)
        let fake = FakeAeroSpace()
        fake.dryRunResult = (false, "unknown command")
        let result = await SavePipeline(paths: paths, host: Self.host, aerospace: fake).run()
        #expect(try Data(contentsOf: paths.output) == old)
        #expect(result.redLine == "AeroSpace refused the config: unknown command · previous config kept")
        #expect(fake.reloads == 0)
    }

    @Test func rejectedWithNoOldFileDeletesNew() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        fake.dryRunResult = (false, "nope")
        let result = await SavePipeline(paths: paths, host: Self.host, aerospace: fake).run()
        guard case .aerospaceRejected = result else { Issue.record("\(result)"); return }
        #expect(!FileManager.default.fileExists(atPath: paths.output.path))
    }

    @Test func notRunningWritesWithoutReload() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        fake.running = false
        let result = await SavePipeline(paths: paths, host: Self.host, aerospace: fake).run()
        guard case .applied = result else { Issue.record("\(result)"); return }
        #expect(FileManager.default.fileExists(atPath: paths.output.path))
        #expect(fake.dryRuns == 0 && fake.reloads == 0)
        #expect(result.redLine == nil)
    }

    @Test func writeIsAtomicAndRoundTrips() async throws {
        let (paths, dir) = try setUp()
        let keys = try KeysFile(text: try fixture("keys.toml"))
        let pipeline = SavePipeline(paths: paths, host: Self.host, aerospace: FakeAeroSpace())
        try await pipeline.write(keys)
        #expect(try String(contentsOf: paths.keys, encoding: .utf8) == keys.document.serialized())
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("grove-keys").path)
        #expect(left == ["keys.toml"])
    }

    @Test func failedRestoreIsReportedAndRevalidated() async throws {
        let (paths, _) = try setUp()
        let folder = paths.output.deletingLastPathComponent()
        try Data("old config\n".utf8).write(to: paths.output)
        let fake = FakeAeroSpace()
        fake.dryRunResult = (false, "unknown command")
        fake.onDryRun = { chmod(folder.path, 0o555) }
        let pipeline = SavePipeline(paths: paths, host: Self.host, aerospace: fake)
        let first = await pipeline.run()
        chmod(folder.path, 0o755)
        guard case .aerospaceRejected(_, let message) = first else { Issue.record("\(first)"); return }
        #expect(message == "unknown command · could not restore the previous config")
        #expect(first.redLine == "AeroSpace refused the config: unknown command · could not restore the previous config")
        // The refused render is still on disk; the next run must not call it unchanged.
        fake.onDryRun = nil
        let second = await pipeline.run()
        #expect(fake.dryRuns == 2)
        #expect(second.redLine == first.redLine)  // still refused, still not restorable
    }
}
