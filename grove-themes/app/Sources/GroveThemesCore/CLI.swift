import Foundation

public struct CLIOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public init(status: Int32, stdout: Data, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CLIError: Error, Equatable, Sendable {
    /// No executable CLI at this path.
    case notInstalled(String)
    /// The CLI's answer wasn't the JSON we expected; holds its first line.
    case unreadable(String)
    /// Exit 2: holds the CLI's stderr.
    case usage(String)

    public var message: String {
        switch self {
        case .notInstalled: "grove-themes isn't installed. Run grove install."
        case .unreadable(let line): "grove-themes gave an answer the app couldn't read: \(line)"
        case .usage(let text): text
        }
    }
}

public protocol CLIRunner: Sendable {
    func run(_ arguments: [String]) async throws -> CLIOutput
}

/// Runs the real CLI with `Process`, passing this process's environment through
/// (so `GROVE_STATE` and friends reach it when set).
public struct ProcessRunner: CLIRunner {
    public let path: URL
    public let environment: [String: String]

    public init(path: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.path = path
        self.environment = environment
    }

    public func run(_ arguments: [String]) async throws -> CLIOutput {
        guard FileManager.default.isExecutableFile(atPath: path.path) else {
            throw CLIError.notInstalled(path.path)
        }
        let path = self.path
        let environment = self.environment
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.runBlocking(path, arguments, environment))
                } catch {
                    continuation.resume(throwing: CLIError.notInstalled(path.path))
                }
            }
        }
    }

    private static func runBlocking(_ path: URL, _ arguments: [String],
                                    _ environment: [String: String]) throws -> CLIOutput {
        let process = Process()
        process.executableURL = path
        process.arguments = arguments
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Read stderr on its own thread so neither pipe can fill up and stall the CLI.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return CLIOutput(status: process.terminationStatus, stdout: stdout,
                         stderr: String(decoding: errBox.data, as: UTF8.self))
    }
}

/// Written by one thread, read by another after a `DispatchGroup.wait()`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// The CLI's `--json` commands, decoded.
public struct GroveThemesClient: Sendable {
    let runner: any CLIRunner

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(runner: any CLIRunner) {
        self.runner = runner
    }

    public func list() async throws -> SchemeList {
        let output = try await call(["list", "--json"])
        return try decode(SchemeList.self, output)
    }

    /// Exit 1 (a step failed or needs you) still returns the result: the configs were written.
    public func set(_ scheme: String) async throws -> (SwitchResult, exit: Int32) {
        let output = try await call(["set", scheme, "--json"])
        return (try decode(SwitchResult.self, output), exit: output.status)
    }

    /// Newest first. An entry that doesn't decode is dropped; the rest are kept.
    public func log(limit: Int) async throws -> [LogEntry] {
        let output = try await call(["log", "-n", String(limit), "--json"])
        do {
            return try decodeLog(output.stdout)
        } catch {
            throw CLIError.unreadable(Self.firstLine(output))
        }
    }

    func decodeLog(_ data: Data) throws -> [LogEntry] {
        try Self.decoder.decode(LogPage.self, from: data).entries.compactMap(\.entry)
    }

    private func call(_ arguments: [String]) async throws -> CLIOutput {
        let output = try await runner.run(arguments)
        if output.status == 2 {
            throw CLIError.usage(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func decode<T: Decodable>(_ type: T.Type, _ output: CLIOutput) throws -> T {
        do {
            return try Self.decoder.decode(type, from: output.stdout)
        } catch {
            throw CLIError.unreadable(Self.firstLine(output))
        }
    }

    /// The first non-empty line of stdout, else of stderr.
    static func firstLine(_ output: CLIOutput) -> String {
        for text in [String(decoding: output.stdout, as: UTF8.self), output.stderr] {
            if let line = text.split(whereSeparator: \.isNewline).first {
                return String(line).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}

private struct LogPage: Decodable {
    let entries: [MaybeEntry]
}

/// Decodes a `LogEntry` or nothing, so one bad entry doesn't sink the page.
private struct MaybeEntry: Decodable {
    let entry: LogEntry?

    init(from decoder: Decoder) throws {
        entry = try? LogEntry(from: decoder)
    }
}
