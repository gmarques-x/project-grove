import Foundation
import Testing
@testable import GroveThemesCore

/// A runner whose `set` waits until the test lets it go.
actor GatedRunner: CLIRunner {
    let answers: [String: CLIOutput]
    private(set) var calls: [[String]] = []
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    init(answers: [String: CLIOutput]) { self.answers = answers }

    func count(_ command: String) -> Int { calls.filter { $0.first == command }.count }

    func waitUntilSetStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        gate?.resume()
        gate = nil
    }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        calls.append(arguments)
        if arguments.first == "set" {
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters = []
            if !released { await withCheckedContinuation { gate = $0 } }
        }
        return answers[arguments.first ?? ""] ?? CLIOutput(status: 2, stdout: Data(), stderr: "no answer")
    }
}

@MainActor @Suite struct ThemesModelTests {
    @Test func refreshLoadsListAndLog() async throws {
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: try fixtureAnswers())))
        await model.refresh()
        #expect(model.list?.current == "dark-medium")
        #expect(model.log.map(\.scheme) == ["light-soft", "dark-medium"])
        #expect(model.error == nil)
        #expect(model.busyScheme == nil)
    }

    @Test func refreshRecoversOnceTheCLIWorks() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers(), failure: .notInstalled("/missing/grove-themes"))
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        await model.refresh()
        #expect(model.error == .notInstalled("/missing/grove-themes"))
        #expect(model.list == nil)
        await runner.setFailure(nil)
        await model.refresh()
        #expect(model.error == nil)
        #expect(model.list?.current == "dark-medium")
        #expect(model.log.count == 2)
    }

    @Test func unreadableListSetsError() async throws {
        var answers = try fixtureAnswers()
        answers["list"] = .ok(Data("oops".utf8))
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)))
        await model.refresh()
        #expect(model.error == .unreadable("oops"))
    }

    @Test func switchIsBusyDuringTheCallAndRefreshesAfter() async throws {
        let runner = GatedRunner(answers: try fixtureAnswers())
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        let task = Task { await model.switchTo("dark-medium") }
        await runner.waitUntilSetStarted()
        #expect(model.busyScheme == "dark-medium")
        #expect(model.isBusy)

        // A second click while the first runs does nothing.
        await model.switchTo("light-soft")
        #expect(await runner.count("set") == 1)
        #expect(model.busyScheme == "dark-medium")

        await runner.release()
        await task.value
        #expect(model.busyScheme == nil)
        #expect(await runner.count("set") == 1)
        #expect(await runner.calls.first == ["set", "dark-medium", "--json"])
        #expect(await runner.count("list") == 1)
        #expect(await runner.count("log") == 1)
        #expect(model.list?.current == "dark-medium")
        #expect(model.error == nil)
    }

    @Test func switchUsageErrorIsShown() async throws {
        var answers = try fixtureAnswers()
        answers["set"] = CLIOutput(status: 2, stdout: Data(), stderr: "grove-themes: unknown scheme: x")
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)))
        await model.switchTo("x")
        #expect(model.error == .usage("grove-themes: unknown scheme: x"))
        #expect(model.busyScheme == nil)
        #expect(model.list != nil)
    }

    @Test func switchThatNeedsYouIsNotAnError() async throws {
        var answers = try fixtureAnswers()
        answers["set"] = .ok(try Fixture.data("set-needs-you.json"), status: 1)
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)))
        await model.switchTo("light-soft")
        #expect(model.error == nil)
        #expect(model.busyScheme == nil)
    }

    /// The CLI doesn't log a switch whose configs step failed, so the model
    /// keeps it: without it the dropdown would still show the switch before.
    @Test func aFailedConfigsStepIsShownThoughTheCLIDidntLogIt() async throws {
        let failed = #"{"scheme": "dark-hard", "steps": [{"name": "configs", "result": "failed", "message": "could not write /state/theme"}]}"#
        var answers = try fixtureAnswers()
        answers["set"] = .ok(Data(failed.utf8), status: 1)
        // The fixture log's newest entry is 2026-11-10 13:43:58 UTC; this is a minute on.
        let now = Date(timeIntervalSince1970: 1_794_318_298)
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)), now: { now })
        await model.switchTo("dark-hard")
        #expect(model.error == nil)
        #expect(model.lastSwitch == LogEntry(time: now, scheme: "dark-hard", exit: 1,
                                             steps: [Step(name: "configs", result: .failed,
                                                          message: "could not write /state/theme")]))
        #expect(model.switches.map(\.scheme) == ["dark-hard", "light-soft", "dark-medium"])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let line = StatusText.line(for: try #require(model.switches.first), now: now, calendar: utc)
        #expect(line == "Couldn't switch to Dark Hard at 13:44 · configs failed")
        #expect(StatusText.chips(for: try #require(model.switches.first))
            == [Chip(text: "failed: configs", kind: .failed, message: "could not write /state/theme")])
    }

    @Test func aLoggedSwitchIsNotShownTwice() async throws {
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: try fixtureAnswers())),
                                now: { Date(timeIntervalSince1970: 1_794_318_298) })
        await model.switchTo("dark-medium")
        #expect(model.lastSwitch?.scheme == "dark-medium")
        #expect(model.switches == model.log)
    }

    @Test func aNewerLoggedSwitchReplacesTheFailedOne() async throws {
        let failed = #"{"scheme": "dark-hard", "steps": [{"name": "configs", "result": "failed", "message": "boom"}]}"#
        var answers = try fixtureAnswers()
        answers["set"] = .ok(Data(failed.utf8), status: 1)
        // An hour before the fixture log's newest entry: that switch came after.
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)),
                                now: { Date(timeIntervalSince1970: 1_794_314_638) })
        await model.switchTo("dark-hard")
        #expect(model.switches == model.log)
    }

    @Test func aBadLogEntryDropsOnlyThatEntry() async throws {
        let log = """
        {"entries": [\
        {"time": "2026-11-10T13:12:00+00:00", "scheme": "dark-soft", "exit": 0, "steps": [{"name": "ghostty", "result": "live", "message": ""}]}, \
        {"time": "2026-11-10T13:11:00+00:00", "scheme": "dark-hard", "exit": 0, "steps": [{"name": "ghostty", "result": "sideways", "message": ""}]}, \
        {"time": "2026-11-10T13:10:00+00:00", "scheme": "light-hard", "exit": 0, "steps": []}\
        ]}
        """
        var answers = try fixtureAnswers()
        answers["log"] = .ok(Data(log.utf8))
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)))
        await model.refresh()
        #expect(model.log.map(\.scheme) == ["dark-soft", "light-hard"])
        #expect(model.error == nil)
    }
}
