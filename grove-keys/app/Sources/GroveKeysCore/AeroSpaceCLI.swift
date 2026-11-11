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
        let r = Subprocess.run("/bin/ps", ["-axo", "comm="], timeout: timeout)
        return r.output.split(separator: "\n").contains {
            ($0.split(separator: "/").last.map(String.init) ?? "") == "AeroSpace"
        }
    }

    public func dryRun() async -> (ok: Bool, message: String) {
        let r = Subprocess.run(binary, ["reload-config", "--dry-run"], timeout: timeout)
        if r.timedOut { return (false, Self.noAnswer) }
        return (r.status == 0, r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
    }

    public func reload() async {
        _ = Subprocess.run(binary, ["reload-config"], timeout: timeout)
    }

    /// One command as a binding would run it (`focus left` as `["focus", "left"]`);
    /// what it prints is dropped.
    public func run(_ arguments: [String]) {
        _ = Subprocess.run(binary, arguments, timeout: timeout)
    }
}
