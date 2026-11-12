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

/// `--check-menu <file> [<local file>]`: reads the Grove menu's file (and the
/// local one over it) as the app would, for grove's tests. Prints the number
/// of rows; an error goes to stderr as "<file> line N: message".
func checkMenu(_ files: [String]) -> Never {
    guard let main = files.first, files.count <= 2 else {
        fail("usage: GroveKeys --check-menu <file> [<local file>]")
    }
    func read(_ path: String) -> (name: String, text: String) {
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fail("\(url.lastPathComponent): can't be read")
        }
        return (url.lastPathComponent, text)
    }
    let tracked = read(main), local = files.dropFirst().first.map(read)
    do {
        let menu = try GroveMenu.strict(main: tracked.text, mainName: tracked.name,
                                        local: local?.text, localName: local?.name ?? "")
        print("\(menu.count) rows")
    } catch {
        fail(error.description)
    }
    exit(0)
}

// The internal flags for grove (spec §8) run before any app code.
if CommandLine.arguments.contains("--render-aerospace") { renderAeroSpace() }
if let flag = CommandLine.arguments.firstIndex(of: "--check-menu") {
    checkMenu(Array(CommandLine.arguments[(flag + 1)...]))
}
// `--render-panel <name> <out.png> [scheme] [left|right]`: a bar panel on its
// sample data, drawn to a PNG. No window is shown and the app never starts.
if let flag = CommandLine.arguments.firstIndex(of: "--render-panel") {
    BarPanelRender.run(Array(CommandLine.arguments[(flag + 1)...]))
}
GroveKeysApp.main()
