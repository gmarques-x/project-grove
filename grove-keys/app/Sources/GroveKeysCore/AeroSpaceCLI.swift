import Foundation

public protocol AeroSpaceRunning: Sendable {
    func isRunning() async -> Bool
    func dryRun() async -> (ok: Bool, message: String)
    func reload() async
}

/// The real AeroSpace, driven through its command line. Every call gives up
/// after `timeout` seconds (the process is terminated), so a hung AeroSpace
/// can't stall the save path.
public struct AeroSpaceCLI: AeroSpaceRunning {
    public static let binary = "/opt/homebrew/bin/aerospace"
    static let noAnswer = "aerospace didn't answer"

    let binary: String
    let timeout: TimeInterval

    public init(binary: String = AeroSpaceCLI.binary, timeout: TimeInterval = 5) {
        self.binary = binary
        self.timeout = timeout
    }

    public func isRunning() async -> Bool {
        let r = Self.run("/bin/ps", ["-axo", "comm="], timeout: timeout)
        return r.output.split(separator: "\n").contains {
            ($0.split(separator: "/").last.map(String.init) ?? "") == "AeroSpace"
        }
    }

    public func dryRun() async -> (ok: Bool, message: String) {
        let r = Self.run(binary, ["reload-config", "--dry-run"], timeout: timeout)
        if r.timedOut { return (false, Self.noAnswer) }
        return (r.status == 0, r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
    }

    public func reload() async {
        _ = Self.run(binary, ["reload-config"], timeout: timeout)
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    private static func run(_ path: String, _ args: [String], timeout: TimeInterval)
        -> (status: Int32, output: String, timedOut: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { return (-1, "cannot run \(path): \(error.localizedDescription)", false) }
        // Read on another thread: a child left holding the pipe can't block us.
        let box = Box(), read = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global().async {
            box.data = handle.readDataToEndOfFile()
            read.signal()
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            p.terminate()
            return (-1, noAnswer, true)
        }
        guard read.wait(timeout: .now() + 1) == .success else { return (p.terminationStatus, "", false) }
        return (p.terminationStatus, String(decoding: box.data, as: UTF8.self), false)
    }
}
