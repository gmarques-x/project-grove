import Foundation
@testable import GroveThemesCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}

/// A runner that answers each command (the first argument) with a canned output.
actor FakeRunner: CLIRunner {
    var answers: [String: CLIOutput]
    var failure: CLIError?
    private(set) var calls: [[String]] = []

    init(answers: [String: CLIOutput] = [:], failure: CLIError? = nil) {
        self.answers = answers
        self.failure = failure
    }

    func setFailure(_ failure: CLIError?) { self.failure = failure }
    func setAnswer(_ command: String, _ output: CLIOutput) { answers[command] = output }
    func count(_ command: String) -> Int { calls.filter { $0.first == command }.count }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        calls.append(arguments)
        if let failure { throw failure }
        guard let command = arguments.first, let answer = answers[command] else {
            return CLIOutput(status: 2, stdout: Data(), stderr: "no answer")
        }
        return answer
    }
}

extension CLIOutput {
    static func ok(_ data: Data, status: Int32 = 0) -> CLIOutput {
        CLIOutput(status: status, stdout: data, stderr: "")
    }
}

/// The fixtures' answers for list, set and log.
func fixtureAnswers() throws -> [String: CLIOutput] {
    [
        "list": .ok(try Fixture.data("list.json")),
        "set": .ok(try Fixture.data("set.json")),
        "log": .ok(try Fixture.data("log.json")),
    ]
}
