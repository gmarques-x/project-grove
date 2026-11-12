import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// `GroveExplorer --render <state> <out.png> [scheme]`: draws the window on
/// fixed sample data to a PNG at 2x and exits, for checking it against the
/// approved mock-ups in a dark and a light scheme without the live UI. No
/// window is ever shown, the app is never started (activation policy
/// `.prohibited`), and no folder is read: the rows are the mock-ups' own.
///
/// - `state`: one of `Render.states`.
/// - `scheme`: a scheme's name as grove-themes knows it (`dark-medium`, the
///   default; `light-medium`, …), or the path of a theme file
///   (`grove-dotfiles/theme/everforest-light-medium`).
@MainActor
enum Render {
    /// A state's name, the window's size and what it shows.
    private struct Scene {
        let size: CGSize
        let panes: [Sample.Pane]
        var showHidden = false
        var extras = Sample.Extras()
    }

    private static let full = CGSize(width: 1904, height: 1180)
    private static let half = CGSize(width: 948, height: 1180)
    /// The mock-ups' small windows for a pane's states and the sidebar's.
    private static let small = CGSize(width: 760, height: 420)
    /// One pane wide enough for all its columns and the free room.
    private static let wide = CGSize(width: 1100, height: 420)

    private static let scenes: [(name: String, scene: Scene)] = [
        // The mock-ups' windows: the full screen with one pane and with two
        // (the second tab under the pointer), and the half-width tile with
        // one pane and with two (where the sidebar is the rail).
        ("one-pane", Scene(size: full, panes: [Sample.grove(selected: ["grove-keys"])])),
        ("two-panes", Scene(size: full, panes: [
            Sample.grove(selected: ["grove-keys"], pointer: "grove-wallpapers", pointerTab: 1),
            Sample.downloads(selected: ["Screenshot 2026-11-11 at 17.30.02.png", "Screenshot 2026-11-12 at 09.12.44.png"]),
        ])),
        ("half-width", Scene(size: half, panes: [Sample.grove(selected: ["grove-keys"])])),
        ("sidebar-rail", Scene(size: half, panes: [
            Sample.grove(selected: ["grove-keys"], pointer: "grove-wallpapers"),
            Sample.downloads(selected: ["Screenshot 2026-11-11 at 17.30.02.png", "Screenshot 2026-11-12 at 09.12.44.png"]),
        ])),
        // ⌘L: the path bar as a field; and on a path that isn't there.
        ("path-field", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: ["grove-keys"])],
            extras: Sample.Extras(pathField: "~/Developer/project-grove/grove-d"))),
        ("path-field-missing", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: ["grove-keys"])],
            extras: Sample.Extras(pathField: "~/Developer/project-grove/grove-d", pathMissing: true))),
        // A pane with nothing to list.
        ("empty", Scene(size: small, panes: [
            Sample.bare(Sample.home.appendingPathComponent("Developer/new-folder", isDirectory: true)),
        ])),
        ("no-permission", Scene(size: CGSize(width: 900, height: 420), panes: [
            Sample.bare(
                Sample.home.appendingPathComponent("Desktop", isDirectory: true),
                problem: "Grove Explorer needs the Desktop Folder permission to open Desktop (Privacy & Security › Files and Folders)",
                needsPermission: true),
        ])),
        // Ejecting the external disk: the pointer on its button, the disk
        // being ejected, and the eject that failed.
        ("eject", Scene(size: small, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(ejectPointer: true))),
        ("ejecting", Scene(size: small, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(ejecting: true))),
        ("eject-failed", Scene(size: small, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(
            ejectFailure: "The disk “Backup” wasn’t ejected because Ghostty is using it."))),
        // The list's three fills side by side, and hidden items selected and
        // not: the active pane at the left, the other at the right.
        ("list-states", Scene(size: CGSize(width: 948, height: 480), panes: [
            Sample.grove(selected: [".github", "artifacts", ".gitignore"], pointer: "docs"),
            Sample.grove(selected: [".git", "grove-keys", "grove-themes"], pointer: "assets"),
        ], showHidden: true)),
        // File operations. The status bar while a copy runs, with its meter
        // and Cancel; what a move did, with ⌘Z; the items a copy could not
        // do, with the list a click shows.
        ("copying", Scene(size: wide, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(
            status: .running(run: 1, words: "Copying 128 of 342 to Downloads", fraction: 0.37, percent: "37%")))),
        ("undo-line", Scene(
            size: wide, panes: [Sample.downloads(selected: ["config.toml", "data-export.csv", "everforest-master.zip"])],
            extras: Sample.Extras(status: .done("Moved 3 items to Downloads", changed: true, hint: true)))),
        ("failures", Scene(size: wide, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(
            status: .failed(
                line: "3 items could not be copied", summary: "Copied 2 of 5 items (3 failed)",
                items: [
                    "Ghostty.dmg: you don't have permission",
                    "notes.md: an item with that name appeared",
                    "talk-recording.mp4: it is no longer there",
                ], changed: true),
            failuresShown: true))),
        // A name is taken: the prompt over the scrimmed window.
        ("conflict", Scene(
            size: CGSize(width: 1672, height: 668),
            panes: [Sample.downloads(selected: ["notes.md"]), Sample.documents()],
            extras: Sample.Extras(prompt: Sample.notesConflict()))),
        // Return: the name as a field; and with a name that can't be used.
        ("rename", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: ["README.md"])],
            extras: Sample.Extras(rename: "README.md"))),
        ("rename-bad-name", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: ["LICENSE"])],
            extras: Sample.Extras(
                rename: "LICENSE", renameText: "docs/LICENSE", renameReason: "A name can't have a “/” in it."))),
        // ⌘F: the field over the list, the names that match, "4 of 212".
        ("filter", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.manyDownloads()],
            extras: Sample.Extras(filter: "shot"))),
        // Three files dragged from the left pane over a folder in the right
        // one: the row marked. (The drag's image and the pointer are the system's.)
        ("drop-target", Scene(
            size: CGSize(width: 1672, height: 668),
            panes: [Sample.grove(selected: ["CHANGELOG.md", "LICENSE", "README.md"]), Sample.downloads(selected: [])],
            extras: Sample.Extras(dropRow: "invoices-2026"))),
        // The folder with each of its marks, at list size.
        ("folder-marks", Scene(size: CGSize(width: 474, height: 300), panes: [Sample.knownFolders()])),
    ]

    static func run(_ arguments: [String]) -> Never {
        let names = scenes.map(\.name).joined(separator: ", ")
        guard arguments.count == 2 || arguments.count == 3 else {
            fail("usage: GroveExplorer --render <state> <out.png> [scheme]\nstates: \(names)")
        }
        guard let scene = scenes.first(where: { $0.name == arguments[0] })?.scene else {
            fail("no state named \(arguments[0]); there are: \(names)")
        }
        let colors = theme(arguments.count == 3 ? arguments[2] : "dark-medium")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        GroveIcons.load()
        if let problem = GroveIcons.problem { fail(problem) }

        let model = Sample.model(panes: scene.panes, showHidden: scene.showHidden, colors: colors, extras: scene.extras)
        // Every command has its action, or the program stops here.
        _ = CommandTable.all
        let size = scene.size
        let view = WindowView(model: model).content
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) { WindowButtonsStandIn() }
            .clipShape(RoundedRectangle(cornerRadius: GroveRadius.window))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.window).strokeBorder(colors.line, lineWidth: 1))
            .environment(\.theme, colors)
        let hosting = offscreen(view, size: size, colors: colors)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { fail("cannot make the image") }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("cannot encode the image") }
        do {
            try png.write(to: URL(fileURLWithPath: arguments[1]))
        } catch {
            fail("cannot write \(arguments[1]): \(error.localizedDescription)")
        }
        print("\(arguments[1]) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        exit(0)
    }

    /// `view` laid out and drawn in a window that is never shown.
    static func offscreen(_ view: some View, size: CGSize, colors: ThemeColors) -> NSView {
        let hosting = NSHostingView(rootView: view)
        // Far off every screen, and never ordered in.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        // SwiftUI settles its layout, and the table its rows, over a few turns of the run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        windows.append(window)
        return hosting
    }

    /// Kept so the window outlives the call that made it.
    private static var windows: [NSWindow] = []

    /// A scheme's colours: from a theme file when `scheme` is a path, else
    /// from `grove-themes list --json`.
    static func theme(_ scheme: String) -> ThemeColors {
        if scheme.contains("/") {
            guard let text = try? String(contentsOfFile: scheme, encoding: .utf8) else { fail("\(scheme): can't be read") }
            var colors: [String: String] = [:]
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { colors[parts[0]] = parts[1] }
            }
            let light = URL(fileURLWithPath: scheme).lastPathComponent.contains("light")
            guard let theme = ThemeColors(palette: Palette(name: scheme, appearance: light ? "light" : "dark",
                                                           colors: colors)) else {
                fail("\(scheme): not a theme file")
            }
            return theme
        }
        let environment = ProcessInfo.processInfo.environment
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/grove-themes").path
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["list", "--json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { fail("grove-themes didn't run; give a theme file's path instead") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let list = try? JSONDecoder().decode(SchemeList.self, from: data)
        else { fail("grove-themes didn't list the schemes; give a theme file's path instead") }
        guard let theme = list.palettes[scheme].flatMap(ThemeColors.init(palette:)) else {
            fail("no scheme named \(scheme); there are: " + list.schemes.joined(separator: ", "))
        }
        return theme
    }
}

/// The window's own buttons, which the system draws on a real window: a
/// measured drawing (14 pt, from 9, as `WindowHeaderMetrics` measured), so a
/// render looks like the window and not like a sheet.
private struct WindowButtonsStandIn: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array([theme.red, theme.yellow, theme.green].enumerated()), id: \.offset) { button in
                Circle().fill(Color(button.element)).frame(width: 14, height: 14)
            }
        }
        .padding(.leading, 9).padding(.top, 9)
    }
}
