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
        // The path bar's copy button: at rest, under the pointer, just
        // copied; and in the half-width tile's narrow panes, deep in a
        // path, where the parts are cut and the button stays whole.
        ("path-copy", Scene(size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: [])])),
        ("path-copy-hover", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: [])],
            extras: Sample.Extras(copyPointer: true))),
        ("path-copied", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.grove(selected: [])],
            extras: Sample.Extras(pathCopied: true))),
        ("path-copy-narrow", Scene(size: CGSize(width: 948, height: 420), panes: [
            Sample.tree(
                Sample.project.appendingPathComponent("grove-explorer/app/Sources/GroveExplorerCore", isDirectory: true),
                [
                    .file("Entry.swift", 2_000, Sample.date(2026, 11, 11, 10, 5)),
                    .file("FolderReader.swift", 6_000, Sample.date(2026, 11, 11, 12, 44)),
                    .file("LinkText.swift", 3_000, Sample.date(2026, 11, 13, 9, 30)),
                    .file("PathBar.swift", 4_000, Sample.date(2026, 11, 11, 14, 9)),
                ]),
            Sample.iCloudNotes(),
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
        // An eject asked for while a copy goes to the disk: refused, and why.
        ("eject-refused", Scene(size: small, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(
            ejectFailure: VolumeUse.ejectRefusal(
                of: Sample.backup.name, at: Sample.backup.url,
                // By its path: the sample's disk is not asked for on this Mac.
                commands: [.operation(.copy(items: [], to: Sample.backup.url))], device: { _ in nil }),
            status: .running(run: 1, words: "Copying 128 of 342 to Backup", fraction: 0.37, percent: "37%")))),
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
        // A refusal said in the pane while the copy runs: the notice, with
        // the percent and Cancel still there.
        ("notice-while-copying", Scene(size: wide, panes: [Sample.downloads(selected: [])], extras: Sample.Extras(
            status: .running(run: 1, words: "Copying 128 of 342 to Downloads", fraction: 0.37, percent: "37%"),
            notice: "“fonts” can't be put inside itself."))),
        // The same in the right pane of the half-width tile: Cancel whole.
        ("notice-while-copying-narrow", Scene(
            size: half, panes: [Sample.grove(selected: []), Sample.downloads(selected: [])],
            extras: Sample.Extras(
                status: .running(run: 1, words: "Copying 128 of 342 to Downloads", fraction: 0.37, percent: "37%"),
                statusSide: .right, notice: "“invoices-2026” can't be put inside itself."))),
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
        // Cloud places: OneDrive's accounts under their own header below
        // iCloud. Inside iCloud Drive at the left (its row lit, the path bar
        // from "iCloud Drive", a tab on it), OneDrive's Documents at the
        // right; and OneDrive's own folder active, its row lit.
        ("cloud", Scene(
            size: CGSize(width: 1672, height: 668), panes: [Sample.iCloudNotes(), Sample.oneDriveDocuments()],
            extras: Sample.Extras(clouds: true))),
        ("cloud-onedrive", Scene(
            size: CGSize(width: 948, height: 560), panes: [Sample.oneDriveTop()], extras: Sample.Extras(clouds: true))),
        // The folder with each of its marks, at list size.
        ("folder-marks", Scene(size: CGSize(width: 474, height: 300), panes: [Sample.knownFolders()])),
        // Folders open in place (spec §16), as the mock-ups have them. Two
        // panes: three levels open at the left, grove-keys still being read
        // under them, a selection across levels; nothing open at the right.
        ("tree", Scene(size: full, panes: [
            Sample.tree(
                Sample.project,
                Sample.projectTree(explorer: Sample.explorerApp(sources: true, core: false), keys: []),
                selected: ["docs", "grove-explorer/app/Package.swift"], pointer: "grove-wallpapers"),
            Sample.downloadsTree(),
        ])),
        // ⌘F "read" with five folders open: the matches, their folders kept as quiet context.
        ("tree-filter", Scene(
            size: CGSize(width: 1100, height: 560),
            panes: [Sample.tree(
                Sample.project,
                Sample.projectTree(explorer: Sample.explorerApp(sources: true, core: true), keys: Sample.keysContents))],
            extras: Sample.Extras(filter: "read"))),
        // Return on a row at level 2: the field where its indented name was.
        ("tree-rename", Scene(
            size: CGSize(width: 948, height: 640),
            panes: [Sample.tree(
                Sample.project, Sample.projectTree(explorer: Sample.explorerApp(sources: false, core: false), keys: nil),
                selected: ["grove-explorer/app/Package.swift"])],
            extras: Sample.Extras(rename: "grove-explorer/app/Package.swift"))),
        // A drag over a folder at level 2: the whole row marked.
        ("tree-drop", Scene(
            size: CGSize(width: 948, height: 640),
            panes: [Sample.tree(
                Sample.project, Sample.projectTree(explorer: Sample.explorerApp(sources: false, core: false), keys: nil))],
            extras: Sample.Extras(dropRow: "grove-explorer/app/Sources", dropSide: .left))),
        // The half-width tile with two panes: level 4 in a 440 pt pane, names cut in the middle.
        ("tree-narrow", Scene(size: half, panes: [
            Sample.tree(
                Sample.project,
                Sample.projectTree(explorer: Sample.explorerApp(sources: true, core: true), keys: nil),
                selected: ["grove-explorer/app/Sources/GroveExplorerCore/FolderReader.swift"]),
            Sample.downloadsTree(),
        ])),
        // Sorted by size, largest first: each folder's contents among themselves.
        ("tree-size-sort", Scene(
            size: CGSize(width: 948, height: 640),
            panes: [Sample.tree(
                Sample.project, Sample.projectTree(explorer: Sample.explorerApp(sources: false, core: false), keys: nil),
                sort: GroveExplorerCore.SortOrder(column: .size, ascending: false))])),
        // Symbolic links: where each points after its name, a broken one
        // in orange; wide, then the half-width tile's narrow pane (the
        // long target cut in its middle, then gone), and renaming a link.
        ("links", Scene(
            size: CGSize(width: 1100, height: 420), panes: [Sample.homeLinks(selected: [".ssh"], pointer: ".zshenv")],
            showHidden: true)),
        ("links-narrow", Scene(size: half, panes: [Sample.homeLinks(selected: [".ssh"]), Sample.homeLinks()],
            showHidden: true)),
        // Shared folders: SHARED's three rows, media connected (and open,
        // its row lit), backup not connected, photos connecting; then
        // Connect to Server with the sentence a wrong share name gets.
        ("shared", Scene(size: CGSize(width: 948, height: 560), panes: [Sample.media()],
            extras: Sample.Extras(shares: true))),
        ("connect-sheet", Scene(size: CGSize(width: 948, height: 560), panes: [Sample.media()],
            extras: Sample.Extras(shares: true, connectSheet: (
                "smb://grove-lab/films", Sample.noShare("smb://grove-lab/films"))))),
        ("links-rename", Scene(
            size: CGSize(width: 948, height: 420), panes: [Sample.homeLinks(selected: [".ssh"])], showHidden: true,
            extras: Sample.Extras(rename: ".ssh"))),
    ]

    static var stateNames: String { scenes.map(\.name).joined(separator: ", ") }

    static func run(_ arguments: [String]) -> Never {
        guard arguments.count == 2 || arguments.count == 3 else {
            fail("usage: GroveExplorer --render <state> <out.png> [scheme]\nstates: \(stateNames)")
        }
        let colors = theme(arguments.count == 3 ? arguments[2] : "dark-medium")
        let (hosting, size, _) = window(showing: arguments[0], colors: colors)
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

    /// The window of the state named `state`, on its sample data, laid out
    /// in a window far off every screen; the app's delegate and scene never
    /// start (activation policy `.prohibited`). For a render, which never
    /// orders the window in, and for the accessibility audit, whose second
    /// half does (there, fully clear, for the length of its check:
    /// `AccessibilityLive`).
    static func window(showing state: String, colors: ThemeColors) -> (view: NSView, size: CGSize, model: AppModel) {
        guard let scene = scenes.first(where: { $0.name == state })?.scene else {
            fail("no state named \(state); there are: \(stateNames)")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        GroveIcons.load()
        if let problem = GroveIcons.problem { fail(problem) }

        let model = Sample.model(panes: scene.panes, showHidden: scene.showHidden, colors: colors, extras: scene.extras)
        let size = scene.size
        let view = WindowView(model: model).content
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) { WindowButtonsStandIn() }
            .overlay(alignment: .top) {
                if let sheet = scene.extras.connectSheet {
                    SheetStandIn { ConnectSheet(model: model, text: sheet.text, problem: sheet.problem) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GroveRadius.window))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.window).strokeBorder(colors.line, lineWidth: 1))
            .environment(\.theme, colors)
        return (offscreen(view, size: size, colors: colors), size, model)
    }

    /// `view` laid out and drawn in a window nobody sees.
    static func offscreen(_ view: some View, size: CGSize, colors: ThemeColors) -> NSView {
        let hosting = NSHostingView(rootView: view)
        // Far off every screen, and not ordered in here (only the audit's
        // second half orders it in, where it is, clear).
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

/// Where macOS puts a sheet: down from under the window's header, in the
/// middle, on a window's corners and shadow (the system draws that frame
/// on a real window; this stands in for it in a render).
private struct SheetStandIn<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: GroveRadius.window))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.window).strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: theme.cardShadow, radius: 30, y: 15)
            .padding(.top, GroveSpace.s24 + GroveSpace.s16)
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
