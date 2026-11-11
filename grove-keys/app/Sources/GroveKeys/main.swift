import Foundation
import GroveKeysCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func renderAeroSpace() -> Never {
    let env = ProcessInfo.processInfo.environment
    let paths = KeysPaths.standard(home: FileManager.default.homeDirectoryForCurrentUser, environment: env)
    let keysText: String, base: String
    do {
        keysText = try String(contentsOf: paths.keys, encoding: .utf8)
        base = try String(contentsOf: paths.base, encoding: .utf8)
    } catch {
        fail("cannot read config: \(error.localizedDescription)")
    }
    let keys: KeysFile
    do { keys = try KeysFile(text: keysText) } catch {
        fail("keys.toml line \(error.line): \(error.message)")
    }
    // This Mac's own file; not there means no assignments.
    let monitors: MonitorsFile
    do { monitors = try MonitorsFile.read(from: paths.monitors) } catch {
        fail(error.line == 0 ? error.message : "monitors.toml line \(error.line): \(error.message)")
    }
    let text = AeroSpaceRenderer.render(keys: keys, base: base, monitors: monitors.assignments)
    let out = env["GROVE_KEYS_RENDER_OUT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? paths.output
    do {
        try writeAtomically(Data(text.utf8), to: out)
    } catch {
        fail("cannot write \(out.path): \(error.localizedDescription)")
    }
    exit(0)
}

// The internal flag for grove (spec §8) runs before any app code.
if CommandLine.arguments.contains("--render-aerospace") { renderAeroSpace() }
GroveKeysApp.main()
