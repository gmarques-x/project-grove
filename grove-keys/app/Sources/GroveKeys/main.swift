import Foundation
import GroveKeysCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func localHostName() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
    p.arguments = ["--get", "LocalHostName"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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
    let text = AeroSpaceRenderer.render(keys: keys, base: base, host: localHostName())
    let out = env["GROVE_KEYS_RENDER_OUT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? paths.output
    do {
        try writeAtomically(Data(text.utf8), to: out)
    } catch {
        fail("cannot write \(out.path): \(error.localizedDescription)")
    }
    exit(0)
}

if CommandLine.arguments.contains("--render-aerospace") { renderAeroSpace() }
print("Grove Keys")
