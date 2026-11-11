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

/// Records the waits a retry loop asks for.
actor Sleeps {
    private(set) var intervals: [Duration] = []

    /// Returns how many waits there have been, this one included.
    func add(_ interval: Duration) -> Int {
        intervals.append(interval)
        return intervals.count
    }
}

/// A wait that lasts until the test opens it.
actor SleepGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var watchers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            watchers.forEach { $0.resume() }
            watchers = []
        }
    }

    func waitUntilWaiting() async {
        if waiting != nil { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        waiting?.resume()
        waiting = nil
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

    @Test func switchIsIgnoredWhileALogoOrWallpaperPickRuns() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers())
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        model.busyLogo = "avatar"
        await model.switchTo("light-soft")
        model.busyLogo = nil
        model.busyWallpaper = "avatar"
        await model.switchTo("light-soft")
        #expect(await runner.calls.isEmpty)
        #expect(model.busyScheme == nil)
        #expect(model.busyWallpaper == "avatar")
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

    @Test func refreshRetriesEveryIntervalUntilTheCLIIsInstalled() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers(), failure: .notInstalled("/missing/grove-themes"))
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        let sleeps = Sleeps()
        // grove install lands the CLI during the second wait.
        await model.refreshRetryingWhileNotInstalled(every: .seconds(5)) { interval in
            if await sleeps.add(interval) == 2 { await runner.setFailure(nil) }
        }
        #expect(await sleeps.intervals == [.seconds(5), .seconds(5)])
        #expect(await runner.count("list") == 3)
        #expect(model.error == nil)
        #expect(model.list?.current == "dark-medium")
    }

    @Test func refreshDoesNotRetryOtherErrors() async throws {
        var answers = try fixtureAnswers()
        answers["list"] = .ok(Data("oops".utf8))
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)))
        let sleeps = Sleeps()
        await model.refreshRetryingWhileNotInstalled(every: .seconds(5)) { _ = await sleeps.add($0) }
        #expect(await sleeps.intervals.isEmpty)
        #expect(model.error == .unreadable("oops"))
    }

    @Test func retryingStopsWhenItsTaskIsCancelled() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers(), failure: .notInstalled("/missing/grove-themes"))
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        await model.refreshRetryingWhileNotInstalled(every: .seconds(5)) { _ in throw CancellationError() }
        #expect(await runner.count("list") == 1)
        #expect(model.error == .notInstalled("/missing/grove-themes"))
        // The loop is over, so a later call retries again.
        let sleeps = Sleeps()
        await model.refreshRetryingWhileNotInstalled(every: .seconds(5)) {
            _ = await sleeps.add($0)
            await runner.setFailure(nil)
        }
        #expect(await sleeps.intervals == [.seconds(5)])
        #expect(model.error == nil)
    }

    @Test func aSecondCallWhileRetryingOnlyRefreshesOnce() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers(), failure: .notInstalled("/missing/grove-themes"))
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        let gate = SleepGate()
        let first = Task { await model.refreshRetryingWhileNotInstalled(every: .seconds(5)) { _ in await gate.wait() } }
        await gate.waitUntilWaiting()
        let sleeps = Sleeps()
        await model.refreshRetryingWhileNotInstalled(every: .seconds(5)) { _ = await sleeps.add($0) }
        #expect(await sleeps.intervals.isEmpty)
        #expect(await runner.count("list") == 2)
        await runner.setFailure(nil)
        await gate.open()
        await first.value
        #expect(await runner.count("list") == 3)
        #expect(model.error == nil)
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

@Suite @MainActor struct ThemesModelLogoTests {
    @Test func pickLogoRunsTheCLIThenRefreshes() async throws {
        var answers = try fixtureAnswers()
        answers["logo"] = .ok(Data(#"{"logo": "avatar"}"#.utf8))
        let runner = FakeRunner(answers: answers)
        let model = ThemesModel(client: GroveThemesClient(runner: runner))
        await model.pickLogo("avatar")
        #expect(await runner.calls.first == ["logo", "avatar", "--json"])
        #expect(await runner.count("list") == 1)
        #expect(model.error == nil)
        #expect(model.busyLogo == nil)
    }

    @Test func pickLogoShowsAFailureLikeASwitch() async throws {
        var answers = try fixtureAnswers()
        answers["logo"] = CLIOutput(status: 2, stdout: Data(), stderr: "usage: grove-themes")
        let model = ThemesModel(client: GroveThemesClient(runner: FakeRunner(answers: answers)))
        await model.pickLogo("banana")
        #expect(model.error == .usage("usage: grove-themes"))
    }
}

@Suite @MainActor struct ThemesModelWallpaperTests {
    @Test func pickWallpaperRunsTheCLIRecordsTheStepAndRefreshes() async throws {
        var answers = try fixtureAnswers()
        let json = #"{"wallpaper": "avatar", "steps": [{"name": "wallpaper", "result": "needs-you", "message": "allow it"}]}"#
        answers["wallpaper"] = .ok(Data(json.utf8), status: 1)
        let runner = FakeRunner(answers: answers)
        let model = ThemesModel(client: GroveThemesClient(runner: runner), now: { Date(timeIntervalSince1970: 9_999_999_999) })
        await model.pickWallpaper("avatar")
        #expect(await runner.calls.first == ["wallpaper", "avatar", "--json"])
        #expect(await runner.count("list") == 1)
        #expect(model.busyWallpaper == nil)
        #expect(model.lastSwitch?.exit == 1)
        #expect(model.lastSwitch?.steps.first?.result == .needsYou)
    }
}
