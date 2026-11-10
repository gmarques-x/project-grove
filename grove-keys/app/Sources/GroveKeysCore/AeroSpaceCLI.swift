import Foundation

public protocol AeroSpaceRunning: Sendable {
    func isRunning() async -> Bool
    func dryRun() async -> (ok: Bool, message: String)
    func reload() async
}

/// The real AeroSpace, driven through its command line.
public struct AeroSpaceCLI: AeroSpaceRunning {
    public static let binary = "/opt/homebrew/bin/aerospace"

    public init() {}

    public func isRunning() async -> Bool {
        let r = Self.run("/bin/ps", ["-axo", "comm="])
        return r.output.split(separator: "\n").contains {
            ($0.split(separator: "/").last.map(String.init) ?? "") == "AeroSpace"
        }
    }

    public func dryRun() async -> (ok: Bool, message: String) {
        let r = Self.run(Self.binary, ["reload-config", "--dry-run"])
        return (r.status == 0, r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func reload() async {
        _ = Self.run(Self.binary, ["reload-config"])
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "cannot run \(path): \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
