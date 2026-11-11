import Foundation
import Testing
@testable import GroveThemesCore

@Suite struct ClientTests {
    @Test func listReturnsTheFixture() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers())
        let list = try await GroveThemesClient(runner: runner).list()
        let expected = try GroveThemesClient.decoder.decode(SchemeList.self, from: Fixture.data("list.json"))
        #expect(list == expected)
        #expect(await runner.calls == [["list", "--json"]])
    }

    @Test func setPassesTheSchemeAndExit() async throws {
        var answers = try fixtureAnswers()
        answers["set"] = .ok(try Fixture.data("set-needs-you.json"), status: 1)
        let runner = FakeRunner(answers: answers)
        let (result, exit) = try await GroveThemesClient(runner: runner).set("light-soft")
        #expect(result.scheme == "light-soft")
        #expect(exit == 1)
        #expect(await runner.calls == [["set", "light-soft", "--json"]])
    }

    @Test func setLogoRunsLogoWithJSON() async throws {
        let runner = FakeRunner(answers: ["logo": .ok(Data(#"{"logo": "avatar"}"#.utf8))])
        let client = GroveThemesClient(runner: runner)
        #expect(try await client.setLogo("avatar") == "avatar")
        #expect(await runner.calls == [["logo", "avatar", "--json"]])
    }

    @Test func logAsksForTheLimit() async throws {
        let runner = FakeRunner(answers: try fixtureAnswers())
        let entries = try await GroveThemesClient(runner: runner).log(limit: 5)
        #expect(entries.count == 2)
        #expect(await runner.calls == [["log", "-n", "5", "--json"]])
    }

    @Test func exitTwoIsUsage() async {
        let stderr = "grove-themes: unknown scheme: dark-pink\nschemes:\n  dark-hard"
        let runner = FakeRunner(answers: ["set": CLIOutput(status: 2, stdout: Data(), stderr: stderr + "\n")])
        await #expect(throws: CLIError.usage(stderr)) {
            _ = try await GroveThemesClient(runner: runner).set("dark-pink")
        }
        #expect(CLIError.usage(stderr).message == stderr)
    }

    @Test func nonJSONIsUnreadable() async {
        let runner = FakeRunner(answers: ["list": .ok(Data("not json\nmore".utf8))])
        await #expect(throws: CLIError.unreadable("not json")) {
            _ = try await GroveThemesClient(runner: runner).list()
        }
        #expect(CLIError.unreadable("not json").message
            == "grove-themes gave an answer the app couldn't read: not json")
    }

    @Test func missingCLIIsNotInstalled() async {
        let path = URL(fileURLWithPath: "/nonexistent/grove-themes")
        await #expect(throws: CLIError.notInstalled(path.path)) {
            _ = try await ProcessRunner(path: path).run(["list", "--json"])
        }
        #expect(CLIError.notInstalled(path.path).message == "grove-themes isn't installed. Run grove install.")
    }

    @Test func processRunnerCollectsOutput() async throws {
        let output = try await ProcessRunner(path: URL(fileURLWithPath: "/bin/sh"))
            .run(["-c", "printf out; printf err >&2; exit 3"])
        #expect(output.status == 3)
        #expect(output.stdout == Data("out".utf8))
        #expect(output.stderr == "err")
    }
}
