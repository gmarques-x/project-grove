import Foundation
import Testing
@testable import GroveKeysCore

/// AeroSpaceCLI against small scripts standing in for the aerospace binary.
@Suite struct AeroSpaceCLITests {
    func script(_ body: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("aerospace")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url.path
    }

    @Test func dryRunPassesTheFirstLineAndStatus() async throws {
        let bad = AeroSpaceCLI(binary: try script("echo 'unknown command: foo'; echo more; exit 1"))
        let r = await bad.dryRun()
        #expect(!r.ok)
        #expect(r.message == "unknown command: foo")
        let good = AeroSpaceCLI(binary: try script("exit 0"))
        #expect(await good.dryRun().ok)
    }

    @Test func aHungAeroSpaceTimesOut() async throws {
        let cli = AeroSpaceCLI(binary: try script("exec /bin/sleep 30"), timeout: 0.5)
        let start = Date()
        let r = await cli.dryRun()
        #expect(!r.ok)
        #expect(r.message == "aerospace didn't answer")
        await cli.reload()  // returns too
        #expect(Date().timeIntervalSince(start) < 5)
    }

    /// A hung script whose child keeps the output pipe open still returns.
    @Test func aHungChildHoldingThePipeTimesOut() async throws {
        let cli = AeroSpaceCLI(binary: try script("/bin/sleep 30"), timeout: 0.5)
        let start = Date()
        let r = await cli.dryRun()
        #expect(r.message == "aerospace didn't answer")
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
