import Foundation
import GroveExplorerCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// `--render <state> <out.png> [scheme]`: the window on fixed sample data,
// drawn to a PNG. No window is shown and the app never starts.
if let flag = CommandLine.arguments.firstIndex(of: "--render") {
    Render.run(Array(CommandLine.arguments[(flag + 1)...]))
}
ExplorerApp.main()
