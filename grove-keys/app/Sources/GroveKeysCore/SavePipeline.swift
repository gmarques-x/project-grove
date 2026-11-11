import Foundation

public enum SaveResult: Equatable, Sendable {
    case applied(KeysFile)
    case unchanged(KeysFile)
    case keysInvalid(TomlError)
    case aerospaceRejected(KeysFile, message: String)
    /// keys.toml was read, but aerospace.base.toml wasn't there to render with.
    case baseMissing(KeysFile)

    /// The line under the tabs, or nil when all is well. Line 0 means the
    /// problem is not in a line of keys.toml (a missing or unreadable file).
    public var redLine: String? {
        switch self {
        case .applied, .unchanged: return nil
        case .baseMissing: return "aerospace.base.toml is missing"
        case .keysInvalid(let e):
            return e.line == 0 ? e.message : "keys.toml line \(e.line): \(e.message)"
        case .aerospaceRejected(_, let message):
            return message.hasSuffix(SavePipeline.notRestored)
                ? "AeroSpace refused the config: \(message)"
                : "AeroSpace refused the config: \(message) · previous config kept"
        }
    }

    /// keys.toml as read and parsed this run, if it was.
    public var keys: KeysFile? {
        switch self {
        case .applied(let k), .unchanged(let k), .aerospaceRejected(let k, _), .baseMissing(let k): return k
        case .keysInvalid: return nil
        }
    }

    /// keys.toml on disk must not be written over: it has an error on a line,
    /// or it is there but can't be read. A missing file, or a write that
    /// failed, doesn't block edits.
    public var blocksEdits: Bool {
        guard case .keysInvalid(let e) = self else { return false }
        return e.line > 0 || e.message == SavePipeline.unreadable
    }

    /// keys.toml doesn't exist: the defaults stand in for it.
    public var keysMissing: Bool {
        self == .keysInvalid(TomlError(line: 0, message: SavePipeline.missing))
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
    public static let missing = "keys.toml is missing"
    public static let unreadable = "keys.toml can't be read"
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

    /// The window's write: keys.toml is read again first and left alone when
    /// it no longer parses (a hand edit the app hasn't seen yet), so a broken
    /// hand edit is never overwritten. Returns that error, a line-0 error
    /// when the file is there but can't be read (or isn't UTF-8), or one when
    /// the write fails; nil when written. Only a missing file is written fresh.
    public func writeOverValid(_ keys: KeysFile) -> TomlError? {
        if FileManager.default.fileExists(atPath: paths.keys.path) {
            guard let text = try? String(contentsOf: paths.keys, encoding: .utf8) else {
                return TomlError(line: 0, message: Self.unreadable)
            }
            do { _ = try KeysFile(text: text) } catch { return error }
        }
        do { try write(keys) } catch {
            return TomlError(line: 0, message: "cannot write keys.toml: \(error.localizedDescription)")
        }
        return nil
    }

    /// `forceReload`: validate and reload AeroSpace even when the render on
    /// disk is already current (the app's first run: grove may have rendered
    /// it while AeroSpace kept the config it had).
    public func run(forceReload: Bool = false) async -> SaveResult {
        guard FileManager.default.fileExists(atPath: paths.keys.path) else {
            return .keysInvalid(TomlError(line: 0, message: Self.missing))
        }
        guard let keysText = try? String(contentsOf: paths.keys, encoding: .utf8) else {
            return .keysInvalid(TomlError(line: 0, message: Self.unreadable))
        }
        let keys: KeysFile
        do { keys = try KeysFile(text: keysText) } catch { return .keysInvalid(error) }
        guard let base = try? String(contentsOf: paths.base, encoding: .utf8) else {
            return .baseMissing(keys)
        }

        let new = Data(AeroSpaceRenderer.render(keys: keys, base: base, host: host).utf8)
        let old = try? Data(contentsOf: paths.output)
        if old == new {
            // Equal to a refused render that could not be put back: validate it again.
            if refused != new, !forceReload { return .unchanged(keys) }
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
