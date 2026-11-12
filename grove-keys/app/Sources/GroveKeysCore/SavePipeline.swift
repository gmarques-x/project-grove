import Foundation
import GroveThemesCore

public enum SaveResult: Equatable, Sendable {
    case applied(KeysFile, MonitorsFile)
    case unchanged(KeysFile, MonitorsFile)
    case keysInvalid(TomlError)
    /// keys.toml was read, but monitors.toml has an error, can't be read, or
    /// (line 0, any other message) couldn't be written. Nothing was rendered.
    case monitorsInvalid(KeysFile, TomlError)
    case aerospaceRejected(KeysFile, MonitorsFile, message: String)
    /// Both files were read, but aerospace.base.toml wasn't there to render with.
    case baseMissing(KeysFile, MonitorsFile)

    /// The line under the tabs, or nil when all is well. Line 0 means the
    /// problem is not in a line of the file (a missing or unreadable file).
    public var redLine: String? {
        switch self {
        case .applied, .unchanged: return nil
        case .baseMissing: return "aerospace.base.toml is missing"
        case .keysInvalid(let e):
            return e.line == 0 ? e.message : "keys.toml line \(e.line): \(e.message)"
        case .monitorsInvalid(_, let e):
            return e.line == 0 ? e.message : "monitors.toml line \(e.line): \(e.message)"
        case .aerospaceRejected(_, _, let message):
            return message.hasSuffix(SavePipeline.notRestored)
                ? "AeroSpace refused the config: \(message)"
                : "AeroSpace refused the config: \(message) · previous config kept"
        }
    }

    /// keys.toml as read and parsed this run, if it was.
    public var keys: KeysFile? {
        switch self {
        case .applied(let k, _), .unchanged(let k, _), .aerospaceRejected(let k, _, _), .baseMissing(let k, _),
             .monitorsInvalid(let k, _):
            return k
        case .keysInvalid: return nil
        }
    }

    /// monitors.toml as read and parsed this run, if it was (no file reads
    /// as no assignments).
    public var monitors: MonitorsFile? {
        switch self {
        case .applied(_, let m), .unchanged(_, let m), .aerospaceRejected(_, let m, _), .baseMissing(_, let m): return m
        case .keysInvalid, .monitorsInvalid: return nil
        }
    }

    /// keys.toml on disk must not be written over: it has an error on a line,
    /// or it is there but can't be read. A missing file, or a write that
    /// failed, doesn't block edits.
    public var blocksEdits: Bool {
        guard case .keysInvalid(let e) = self else { return false }
        return e.line > 0 || e.message == SavePipeline.unreadable
    }

    /// The same for monitors.toml. The two are apart: an error in
    /// monitors.toml never blocks edits to keys.toml.
    public var blocksMonitorEdits: Bool {
        guard case .monitorsInvalid(_, let e) = self else { return false }
        return e.line > 0 || e.message == MonitorsFile.unreadable
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

/// Spec §8 steps 1 and 3-5. Reads keys.toml, monitors.toml and the base file
/// fresh each run.
/// An actor, so a run from the window and one from the watcher never overlap.
public actor SavePipeline {
    static let notRestored = " · could not restore the previous config"
    public static let missing = "keys.toml is missing"
    public static let unreadable = "keys.toml can't be read"
    let paths: KeysPaths
    let aerospace: any AeroSpaceRunning
    /// A render AeroSpace refused that may still be on disk (restore failed).
    private var refused: Data?

    public init(paths: KeysPaths, aerospace: any AeroSpaceRunning) {
        self.paths = paths; self.aerospace = aerospace
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

    public func write(_ monitors: MonitorsFile) throws {
        try writeAtomically(Data(monitors.document.serialized().utf8), to: paths.monitors)
    }

    /// `writeOverValid` for monitors.toml: a file that is there but has an
    /// error or can't be read is left alone; a missing one is created.
    public func writeOverValid(_ monitors: MonitorsFile) -> TomlError? {
        do { _ = try MonitorsFile.read(from: paths.monitors) } catch { return error }
        do { try write(monitors) } catch {
            return TomlError(line: 0, message: "cannot write monitors.toml: \(error.localizedDescription)")
        }
        return nil
    }

    /// The Monitors panel's save: the write, then a run. A write that was
    /// refused or failed is reported when the run has no failure of its own
    /// to show (a broken monitors.toml is reported by the run itself).
    public func save(_ monitors: MonitorsFile) async -> SaveResult {
        let refused = writeOverValid(monitors)
        let result = await run()
        if let refused, result.redLine == nil, let keys = result.keys { return .monitorsInvalid(keys, refused) }
        return result
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
        let monitors: MonitorsFile
        do { monitors = try MonitorsFile.read(from: paths.monitors) } catch { return .monitorsInvalid(keys, error) }
        guard let base = try? String(contentsOf: paths.base, encoding: .utf8) else {
            return .baseMissing(keys, monitors)
        }

        let new = Data(AeroSpaceRenderer.render(keys: keys, base: base, monitors: monitors.assignments).utf8)
        let old = try? Data(contentsOf: paths.output)
        if old == new {
            // Equal to a refused render that could not be put back: validate it again.
            if refused != new, !forceReload { return .unchanged(keys, monitors) }
        } else {
            do { try writeAtomically(new, to: paths.output) } catch {
                return .aerospaceRejected(keys, monitors, message: "cannot write \(paths.output.path): \(error.localizedDescription)")
            }
        }
        guard await aerospace.isRunning() else { return .applied(keys, monitors) }

        let dry = await aerospace.dryRun()
        guard dry.ok else {
            do {
                if let old, old != new { try writeAtomically(old, to: paths.output) }
                else if old == nil { try FileManager.default.removeItem(at: paths.output) }
                else { throw CocoaError(.fileWriteUnknown) }  // old == new: nothing to go back to
                refused = nil
                return .aerospaceRejected(keys, monitors, message: dry.message)
            } catch {
                refused = new
                return .aerospaceRejected(keys, monitors, message: dry.message + Self.notRestored)
            }
        }
        refused = nil
        await aerospace.reload()
        return .applied(keys, monitors)
    }
}
