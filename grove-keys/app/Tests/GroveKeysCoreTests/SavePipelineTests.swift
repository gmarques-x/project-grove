import Foundation
import Testing
@testable import GroveKeysCore
import GroveThemesCore

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
    /// No monitors.toml unless `monitors` is given: the usual state.
    func setUp(keys: String? = nil, base: String? = nil, monitors: String? = nil) throws -> (KeysPaths, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        let cfg = dir.appendingPathComponent("grove-keys"), aero = dir.appendingPathComponent("aerospace")
        try FileManager.default.createDirectory(at: cfg, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aero, withIntermediateDirectories: true)
        let paths = KeysPaths(keys: cfg.appendingPathComponent("keys.toml"),
                              monitors: cfg.appendingPathComponent("monitors.toml"),
                              base: aero.appendingPathComponent("aerospace.base.toml"),
                              output: aero.appendingPathComponent("aerospace.toml"))
        try (keys ?? fixture("keys.toml")).write(to: paths.keys, atomically: true, encoding: .utf8)
        try (base ?? fixture("aerospace.base.toml")).write(to: paths.base, atomically: true, encoding: .utf8)
        try monitors?.write(to: paths.monitors, atomically: true, encoding: .utf8)
        return (paths, dir)
    }

    @Test func appliesAndReloads() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        let result = await SavePipeline(paths: paths, aerospace: fake).run()
        guard case .applied = result else { Issue.record("\(result)"); return }
        let out = try String(contentsOf: paths.output, encoding: .utf8)
        #expect(out.hasPrefix(AeroSpaceRenderer.header))
        #expect(fake.dryRuns == 1)
        #expect(fake.reloads == 1)
    }

    @Test func unchangedSkipsReload() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        let pipeline = SavePipeline(paths: paths, aerospace: fake)
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
        let result = await SavePipeline(paths: paths, aerospace: fake).run()
        guard case .keysInvalid(let err) = result else { Issue.record("\(result)"); return }
        #expect(err.line == 4)
        #expect(result.redLine?.hasPrefix("keys.toml line 4:") == true)
        #expect(try Data(contentsOf: paths.output) == old)
        #expect(fake.dryRuns == 0 && fake.reloads == 0)
    }

    /// The base missing is a failure, but keys.toml was read: the result
    /// carries it, so the app shows and edits the real file, not the defaults.
    @Test func missingBaseIsAFailureThatCarriesTheKeys() async throws {
        let (paths, _) = try setUp()
        try FileManager.default.removeItem(at: paths.base)
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).run()
        let keys = try KeysFile(text: try fixture("keys.toml"))
        #expect(result == .baseMissing(keys, MonitorsFile()))
        #expect(result.keys == keys)
        #expect(result.redLine == "aerospace.base.toml is missing")
        #expect(!result.blocksEdits)
        #expect(!FileManager.default.fileExists(atPath: paths.output.path))
    }

    @Test func missingKeysIsReportedAndDoesNotBlockEdits() async throws {
        let (paths, _) = try setUp()
        try FileManager.default.removeItem(at: paths.keys)
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).run()
        #expect(result == .keysInvalid(TomlError(line: 0, message: "keys.toml is missing")))
        #expect(result.keysMissing)
        #expect(!result.blocksEdits)
        #expect(result.keys == nil)
    }

    /// keys.toml there but not UTF-8 (or not readable): never the defaults.
    @Test func unreadableKeysBlocksEdits() async throws {
        let (paths, _) = try setUp()
        try Data([0x5b, 0xff, 0xfe, 0x5d, 0x0a]).write(to: paths.keys)
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).run()
        #expect(result == .keysInvalid(TomlError(line: 0, message: "keys.toml can't be read")))
        #expect(result.redLine == "keys.toml can't be read")
        #expect(result.blocksEdits)
        #expect(!result.keysMissing)
        #expect(!FileManager.default.fileExists(atPath: paths.output.path))
    }

    @Test func aLineErrorBlocksEditsAndAWriteErrorDoesNot() {
        #expect(SaveResult.keysInvalid(TomlError(line: 3, message: "x")).blocksEdits)
        #expect(!SaveResult.keysInvalid(TomlError(line: 0, message: "cannot write keys.toml: no")).blocksEdits)
    }

    /// The app's first run reloads AeroSpace even when the render on disk is
    /// current: grove may have rendered it without AeroSpace reloading.
    @Test func forceReloadReloadsAnUnchangedRender() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        let pipeline = SavePipeline(paths: paths, aerospace: fake)
        _ = await pipeline.run()
        let result = await pipeline.run(forceReload: true)
        guard case .applied = result else { Issue.record("\(result)"); return }
        #expect(fake.dryRuns == 2)
        #expect(fake.reloads == 2)
        fake.running = false
        _ = await pipeline.run(forceReload: true)
        #expect(fake.reloads == 2)
    }

    @Test func rejectedRestoresOld() async throws {
        let (paths, _) = try setUp()
        let old = Data("old config\n".utf8)
        try old.write(to: paths.output)
        let fake = FakeAeroSpace()
        fake.dryRunResult = (false, "unknown command")
        let result = await SavePipeline(paths: paths, aerospace: fake).run()
        #expect(try Data(contentsOf: paths.output) == old)
        #expect(result.redLine == "AeroSpace refused the config: unknown command · previous config kept")
        #expect(fake.reloads == 0)
    }

    @Test func rejectedWithNoOldFileDeletesNew() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        fake.dryRunResult = (false, "nope")
        let result = await SavePipeline(paths: paths, aerospace: fake).run()
        guard case .aerospaceRejected = result else { Issue.record("\(result)"); return }
        #expect(!FileManager.default.fileExists(atPath: paths.output.path))
    }

    @Test func notRunningWritesWithoutReload() async throws {
        let (paths, _) = try setUp()
        let fake = FakeAeroSpace()
        fake.running = false
        let result = await SavePipeline(paths: paths, aerospace: fake).run()
        guard case .applied = result else { Issue.record("\(result)"); return }
        #expect(FileManager.default.fileExists(atPath: paths.output.path))
        #expect(fake.dryRuns == 0 && fake.reloads == 0)
        #expect(result.redLine == nil)
    }

    @Test func writeIsAtomicAndRoundTrips() async throws {
        let (paths, dir) = try setUp()
        let keys = try KeysFile(text: try fixture("keys.toml"))
        let pipeline = SavePipeline(paths: paths, aerospace: FakeAeroSpace())
        try await pipeline.write(keys)
        #expect(try String(contentsOf: paths.keys, encoding: .utf8) == keys.document.serialized())
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("grove-keys").path)
        #expect(left == ["keys.toml"])
    }

    @Test func writeOverValidKeepsABrokenHandEdit() async throws {
        let broken = "[hyper]\ntap = \"sideways\"\n"
        let (paths, _) = try setUp(keys: broken)
        let keys = try KeysFile(text: try fixture("keys.toml"))
        let pipeline = SavePipeline(paths: paths, aerospace: FakeAeroSpace())
        let error = await pipeline.writeOverValid(keys)
        #expect(error?.line == 2)
        #expect(try String(contentsOf: paths.keys, encoding: .utf8) == broken)
    }

    @Test func writeOverValidRefusesAnUnreadableFile() async throws {
        let (paths, _) = try setUp()
        let bytes = Data([0x5b, 0xff, 0xfe, 0x5d, 0x0a])
        try bytes.write(to: paths.keys)
        let keys = try KeysFile(text: try fixture("keys.toml"))
        let pipeline = SavePipeline(paths: paths, aerospace: FakeAeroSpace())
        #expect(await pipeline.writeOverValid(keys) == TomlError(line: 0, message: "keys.toml can't be read"))
        #expect(try Data(contentsOf: paths.keys) == bytes)
        // Not readable at all (no permission): the same.
        try fixture("keys.toml").write(to: paths.keys, atomically: true, encoding: .utf8)
        chmod(paths.keys.path, 0o200)
        defer { chmod(paths.keys.path, 0o644) }
        #expect(await pipeline.writeOverValid(keys) == TomlError(line: 0, message: "keys.toml can't be read"))
    }

    @Test func writeOverValidWritesOverAValidOrMissingFile() async throws {
        let (paths, _) = try setUp()
        var keys = try KeysFile(text: try fixture("keys.toml"))
        keys.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        let pipeline = SavePipeline(paths: paths, aerospace: FakeAeroSpace())
        #expect(await pipeline.writeOverValid(keys) == nil)
        #expect(try String(contentsOf: paths.keys, encoding: .utf8) == keys.document.serialized())
        try FileManager.default.removeItem(at: paths.keys)
        #expect(await pipeline.writeOverValid(keys) == nil)
        #expect(try String(contentsOf: paths.keys, encoding: .utf8) == keys.document.serialized())
    }

    // MARK: monitors.toml

    @Test func noMonitorsFileIsNoAssignmentsAndNotAnError() async throws {
        let (paths, _) = try setUp()
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).run()
        guard case .applied = result else { Issue.record("\(result)"); return }
        #expect(result.redLine == nil)
        #expect(result.monitors == MonitorsFile())
        #expect(!result.blocksMonitorEdits)
        #expect(!(try String(contentsOf: paths.output, encoding: .utf8)).contains("workspace-to-monitor-force-assignment"))
        #expect(!FileManager.default.fileExists(atPath: paths.monitors.path))  // reading creates nothing
    }

    @Test func monitorsAreRenderedAndAChangeIsApplied() async throws {
        let (paths, _) = try setUp(monitors: "[monitors]\n1 = \"main\"\n")
        let fake = FakeAeroSpace()
        let pipeline = SavePipeline(paths: paths, aerospace: fake)
        let first = await pipeline.run()
        #expect(first.monitors?.assignments.map(\.target) == ["main"])
        #expect((try String(contentsOf: paths.output, encoding: .utf8))
            .hasSuffix("\n[workspace-to-monitor-force-assignment]\n\"1\" = \"main\"\n"))
        // A hand edit of monitors.toml alone is a new render.
        try "[monitors]\n1 = \"secondary\"\n".write(to: paths.monitors, atomically: true, encoding: .utf8)
        let second = await pipeline.run()
        guard case .applied = second else { Issue.record("\(second)"); return }
        #expect((try String(contentsOf: paths.output, encoding: .utf8)).contains("\"1\" = \"secondary\""))
        #expect(fake.reloads == 2)
    }

    /// A broken monitors.toml stops the render (the old config stays), is
    /// named in the red line, and leaves keys.toml readable and editable.
    @Test func invalidMonitorsTouchesNothingAndCarriesTheKeys() async throws {
        let (paths, _) = try setUp(monitors: "[monitors]\n1 = \"main\"\n2 = 3\n")
        let old = Data("old config\n".utf8)
        try old.write(to: paths.output)
        let fake = FakeAeroSpace()
        let result = await SavePipeline(paths: paths, aerospace: fake).run()
        let keys = try KeysFile(text: try fixture("keys.toml"))
        #expect(result == .monitorsInvalid(keys, TomlError(line: 3, message: "workspace 2 must be assigned a monitor in quotes")))
        #expect(result.redLine == "monitors.toml line 3: workspace 2 must be assigned a monitor in quotes")
        #expect(result.keys == keys)
        #expect(result.monitors == nil)
        #expect(!result.blocksEdits && !result.keysMissing)
        #expect(result.blocksMonitorEdits)
        #expect(try Data(contentsOf: paths.output) == old)
        #expect(fake.dryRuns == 0 && fake.reloads == 0)
    }

    @Test func unreadableMonitorsBlocksMonitorEditsOnly() async throws {
        let (paths, _) = try setUp()
        try Data([0x5b, 0xff, 0xfe, 0x5d, 0x0a]).write(to: paths.monitors)
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).run()
        #expect(result.redLine == "monitors.toml can't be read")
        #expect(result.blocksMonitorEdits && !result.blocksEdits)
        #expect(result.keys != nil)
    }

    /// A keys.toml error is found first, and says nothing about monitors.toml.
    @Test func aKeysErrorIsReportedBeforeAMonitorsError() async throws {
        let (paths, _) = try setUp(keys: "[hyper]\ntap = \"sideways\"\n", monitors: "[monitors]\n1 = 3\n")
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).run()
        #expect(result.redLine?.hasPrefix("keys.toml line 2:") == true)
        #expect(result.blocksEdits && !result.blocksMonitorEdits)
        #expect(result.monitors == nil)
    }

    @Test func aMonitorsWriteErrorDoesNotBlockMonitorEdits() throws {
        let keys = try KeysFile(text: "")
        #expect(SaveResult.monitorsInvalid(keys, TomlError(line: 2, message: "x")).blocksMonitorEdits)
        let failed = SaveResult.monitorsInvalid(keys, TomlError(line: 0, message: "cannot write monitors.toml: no"))
        #expect(!failed.blocksMonitorEdits)
        #expect(failed.redLine == "cannot write monitors.toml: no")
    }

    /// The Monitors panel's first change: the file is created, with its
    /// comment header, and rendered; keys.toml is not touched.
    @Test func saveCreatesMonitorsTomlAndRendersIt() async throws {
        let (paths, dir) = try setUp()
        let keysBefore = try Data(contentsOf: paths.keys)
        var monitors = MonitorsFile()
        monitors.set(workspace: "1", target: "secondary")
        let fake = FakeAeroSpace()
        let result = await SavePipeline(paths: paths, aerospace: fake).save(monitors)
        guard case .applied = result else { Issue.record("\(result)"); return }
        #expect(result.monitors == monitors)
        let written = try String(contentsOf: paths.monitors, encoding: .utf8)
        #expect(written == monitors.document.serialized())
        #expect(written.hasPrefix("# Grove Keys: "))
        #expect(written.contains("\n[monitors] # workspace"))
        #expect((try String(contentsOf: paths.output, encoding: .utf8))
            .hasSuffix("\n[workspace-to-monitor-force-assignment]\n\"1\" = \"secondary\"\n"))
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("grove-keys").path)
        #expect(left.sorted() == ["keys.toml", "monitors.toml"])
        #expect(fake.reloads == 1)
    }

    @Test func saveKeepsABrokenHandEditedMonitorsToml() async throws {
        let broken = "[monitors]\n1 = main\n"
        let (paths, _) = try setUp(monitors: broken)
        var monitors = MonitorsFile()
        monitors.set(workspace: "1", target: "secondary")
        let pipeline = SavePipeline(paths: paths, aerospace: FakeAeroSpace())
        #expect(await pipeline.writeOverValid(monitors)?.line == 2)
        let result = await pipeline.save(monitors)
        #expect(result.redLine?.hasPrefix("monitors.toml line 2:") == true)
        #expect(result.blocksMonitorEdits)
        #expect(try String(contentsOf: paths.monitors, encoding: .utf8) == broken)
        // Not UTF-8: the same.
        let bytes = Data([0x5b, 0xff, 0xfe, 0x5d, 0x0a])
        try bytes.write(to: paths.monitors)
        #expect(await pipeline.writeOverValid(monitors) == TomlError(line: 0, message: "monitors.toml can't be read"))
        #expect(try Data(contentsOf: paths.monitors) == bytes)
    }

    @Test func saveWritesOverAValidMonitorsToml() async throws {
        let (paths, _) = try setUp(monitors: "# mine\n\n[monitors]\n1 = \"main\" # desk\n")
        let pipeline = SavePipeline(paths: paths, aerospace: FakeAeroSpace())
        var monitors = try #require(await pipeline.run().monitors)
        monitors.set(workspace: "1", target: "built-in")
        let result = await pipeline.save(monitors)
        guard case .applied = result else { Issue.record("\(result)"); return }
        #expect(try String(contentsOf: paths.monitors, encoding: .utf8) == "# mine\n\n[monitors]\n\"1\" = \"built-in\" # desk\n")
    }

    /// A write that fails is the red line, though the run after it is fine;
    /// the result has no monitors, so the app goes back to what is on disk.
    @Test func saveReportsAFailedWrite() async throws {
        let (paths, _) = try setUp()
        let folder = paths.monitors.deletingLastPathComponent()
        var monitors = MonitorsFile()
        monitors.set(workspace: "1", target: "secondary")
        chmod(folder.path, 0o555)
        let result = await SavePipeline(paths: paths, aerospace: FakeAeroSpace()).save(monitors)
        chmod(folder.path, 0o755)
        guard case .monitorsInvalid(_, let error) = result else { Issue.record("\(result)"); return }
        #expect(error.line == 0 && error.message.hasPrefix("cannot write monitors.toml: "))
        #expect(result.monitors == nil && result.keys != nil)
        #expect(!result.blocksMonitorEdits && !result.blocksEdits)
        #expect(!FileManager.default.fileExists(atPath: paths.monitors.path))
    }

    @Test func failedRestoreIsReportedAndRevalidated() async throws {
        let (paths, _) = try setUp()
        let folder = paths.output.deletingLastPathComponent()
        try Data("old config\n".utf8).write(to: paths.output)
        let fake = FakeAeroSpace()
        fake.dryRunResult = (false, "unknown command")
        fake.onDryRun = { chmod(folder.path, 0o555) }
        let pipeline = SavePipeline(paths: paths, aerospace: fake)
        let first = await pipeline.run()
        chmod(folder.path, 0o755)
        guard case .aerospaceRejected(_, _, let message) = first else { Issue.record("\(first)"); return }
        #expect(message == "unknown command · could not restore the previous config")
        #expect(first.redLine == "AeroSpace refused the config: unknown command · could not restore the previous config")
        // The refused render is still on disk; the next run must not call it unchanged.
        fake.onDryRun = nil
        let second = await pipeline.run()
        #expect(fake.dryRuns == 2)
        #expect(second.redLine == first.redLine)  // still refused, still not restorable
    }
}
