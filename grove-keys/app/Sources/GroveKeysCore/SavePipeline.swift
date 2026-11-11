import Foundation

public enum SaveResult: Equatable, Sendable {
    case applied(KeysFile)
    case unchanged(KeysFile)
    case keysInvalid(TomlError)
    case aerospaceRejected(KeysFile, message: String)

    /// The line under the tabs, or nil when all is well. Line 0 means the
    /// problem is not in a line of keys.toml (a missing file).
    public var redLine: String? {
        switch self {
        case .applied, .unchanged: return nil
        case .keysInvalid(let e):
            return e.line == 0 ? e.message : "keys.toml line \(e.line): \(e.message)"
        case .aerospaceRejected(_, let message):
            return message.hasSuffix(SavePipeline.notRestored)
                ? "AeroSpace refused the config: \(message)"
                : "AeroSpace refused the config: \(message) · previous config kept"
        }
    }
}

/// Writes a file atomically (temp file in the same folder, then rename),
/// creating its folder when needed.
public func writeAtomically(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

/// Spec §8 steps 1 and 3-5. Reads keys.toml and the base file fresh each run.
/// An actor, so a run from the window and one from the watcher never overlap.
public actor SavePipeline {
    static let notRestored = " · could not restore the previous config"
    let paths: KeysPaths
    let host: String
    let aerospace: any AeroSpaceRunning
    /// A render AeroSpace refused that may still be on disk (restore failed).
    private var refused: Data?

    public init(paths: KeysPaths, host: String, aerospace: any AeroSpaceRunning) {
        self.paths = paths; self.host = host; self.aerospace = aerospace
    }

    public func write(_ keys: KeysFile) throws {
        try writeAtomically(Data(keys.document.serialized().utf8), to: paths.keys)
    }

    public func run() async -> SaveResult {
        guard let keysText = try? String(contentsOf: paths.keys, encoding: .utf8) else {
            return .keysInvalid(TomlError(line: 0, message: "keys.toml is missing"))
        }
        let keys: KeysFile
        do { keys = try KeysFile(text: keysText) } catch { return .keysInvalid(error) }
        guard let base = try? String(contentsOf: paths.base, encoding: .utf8) else {
            return .keysInvalid(TomlError(line: 0, message: "aerospace.base.toml is missing"))
        }

        let new = Data(AeroSpaceRenderer.render(keys: keys, base: base, host: host).utf8)
        let old = try? Data(contentsOf: paths.output)
        if old == new {
            // Equal to a refused render that could not be put back: validate it again.
            if refused != new { return .unchanged(keys) }
        } else {
            do { try writeAtomically(new, to: paths.output) } catch {
                return .aerospaceRejected(keys, message: "cannot write \(paths.output.path): \(error.localizedDescription)")
            }
        }
        guard await aerospace.isRunning() else { return .applied(keys) }

        let dry = await aerospace.dryRun()
        guard dry.ok else {
            do {
                if let old, old != new { try writeAtomically(old, to: paths.output) }
                else if old == nil { try FileManager.default.removeItem(at: paths.output) }
                else { throw CocoaError(.fileWriteUnknown) }  // old == new: nothing to go back to
                refused = nil
                return .aerospaceRejected(keys, message: dry.message)
            } catch {
                refused = new
                return .aerospaceRejected(keys, message: dry.message + Self.notRestored)
            }
        }
        refused = nil
        await aerospace.reload()
        return .applied(keys)
    }
}
