import Foundation

/// A command line tool run to its end, or stopped after `timeout` seconds
/// (the process is terminated), so a hung one can't stall the caller.
public enum Subprocess {
    private final class Box: @unchecked Sendable { var data = Data() }

    /// `output` is what it printed, standard error included; empty when it
    /// timed out.
    public static func run(_ path: String, _ args: [String], timeout: TimeInterval)
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
            return (-1, "", true)
        }
        guard read.wait(timeout: .now() + 1) == .success else { return (p.terminationStatus, "", false) }
        return (p.terminationStatus, String(decoding: box.data, as: UTF8.self), false)
    }
}
