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
// `--audit-accessibility <state>|all [--tree]`: the same windows, walked
// for controls that say nothing of themselves. Offscreen like a render.
if let flag = CommandLine.arguments.firstIndex(of: "--audit-accessibility") {
    AccessibilityAudit.run(Array(CommandLine.arguments[(flag + 1)...]))
}
// `--time-list [rows]`: how long the list takes over a large folder (made
// up, not read), printed in milliseconds. Offscreen like a render.
if let flag = CommandLine.arguments.firstIndex(of: "--time-list") {
    ListTiming.run(Array(CommandLine.arguments[(flag + 1)...]))
}
ExplorerApp.main()
