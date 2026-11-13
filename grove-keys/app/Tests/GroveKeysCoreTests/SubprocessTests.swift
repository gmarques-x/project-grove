import Testing
@testable import GroveKeysCore

struct SubprocessTests {
    @Test func standardErrorIsIncludedByDefault() {
        let run = Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2"], timeout: 5)
        #expect(run.status == 0)
        #expect(run.output.contains("out") && run.output.contains("err"))
    }

    /// For output that is parsed whole (`system_profiler -json`): a warning
    /// on standard error mustn't spoil it.
    @Test func standardErrorCanBeLeftOut() {
        let run = Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2"], timeout: 5, includeErrors: false)
        #expect(run.status == 0)
        #expect(run.output == "out\n")
    }
}
