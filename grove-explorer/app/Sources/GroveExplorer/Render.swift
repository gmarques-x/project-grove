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
    }

    private static let scenes: [(name: String, scene: Scene)] = [
        // The mock-ups' three: the full screen with one pane and with two,
        // and the half-width tile.
        ("one-pane", Scene(size: CGSize(width: 1904, height: 1180), panes: [Sample.grove(selected: ["grove-keys"])])),
        ("two-panes", Scene(size: CGSize(width: 1904, height: 1180), panes: [
            Sample.grove(selected: ["grove-keys"], pointer: "grove-wallpapers"),
            Sample.downloads(selected: ["Screenshot 2026-11-11 at 17.30.02.png", "Screenshot 2026-11-12 at 09.12.44.png"]),
        ])),
        ("half-width", Scene(size: CGSize(width: 948, height: 1180), panes: [Sample.grove(selected: ["grove-keys"])])),
        // The list's three fills side by side, and hidden items selected and
        // not: the active pane at the left, the other at the right.
        ("list-states", Scene(size: CGSize(width: 948, height: 480), panes: [
            Sample.grove(selected: [".github", "artifacts", ".gitignore"], pointer: "docs"),
            Sample.grove(selected: [".git", "grove-keys", "grove-themes"], pointer: "assets"),
        ], showHidden: true)),
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

        let model = Sample.model(panes: scene.panes, showHidden: scene.showHidden, colors: colors)
        let size = scene.size
        let view = WindowView(model: model).content
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) { WindowButtonsStandIn() }
            .clipShape(RoundedRectangle(cornerRadius: GroveRadius.window))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.window).strokeBorder(colors.line, lineWidth: 1))
            .environment(\.theme, colors)
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

    /// A scheme's colours: from a theme file when `scheme` is a path, else
    /// from `grove-themes list --json`.
    private static func theme(_ scheme: String) -> ThemeColors {
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

/// The mock-ups' folders, as entries: nothing here is read from the disk.
@MainActor
enum Sample {
    struct Pane {
        var folder: URL
        var entries: [Entry]
        var sizes: [URL: Int64]
        var selected: Set<String>
        var pointer: String?
    }

    /// 12 Nov 2026, 09:45, in a calendar and a locale of its own, so a
    /// render says the same on any Mac at any time.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let now = date(2026, 11, 12, 9, 45)
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func model(panes: [Pane], showHidden: Bool, colors: ThemeColors) -> AppModel {
        var browser = Browser(start: panes[0].folder, twoPanes: panes.count == 2, showHidden: showHidden)
        if panes.count == 2 { browser.panes[1].tabs[0].folder = panes[1].folder }
        let sides: [Side] = [.left, .right]
        var entries: [Side: [Entry]] = [:], selected: [Side: Set<URL>] = [:], sizes: [URL: Int64] = [:]
        var pointer: [Side: URL] = [:]
        for (side, pane) in zip(sides, panes) {
            entries[side] = pane.entries
            selected[side] = Set(pane.entries.filter { pane.selected.contains($0.name) }.map(\.url))
            sizes.merge(pane.sizes) { $1 }
            pointer[side] = pane.entries.first { $0.name == pane.pointer }?.url
        }
        // The built-in defaults: no file is read.
        let config = ExplorerConfig.load(tracked: nil, local: nil, home: home, exists: { _ in true })
        let now = now
        let clock = ListClock(now: { now }, calendar: calendar, locale: Locale(identifier: "en_GB"))
        let model = AppModel.fixed(
            browser: browser, config: config, clock: clock, colors: colors, entries: entries, sizes: sizes,
            free: 212_400_000_000, selected: selected)
        model.pointerStandIn = pointer
        return model
    }

    private static let kinds: [String: String] = [
        "md": "Markdown", "toml": "TOML", "csv": "CSV", "zip": "ZIP Archive", "dmg": "Disk Image", "svg": "SVG Image",
        "pdf": "PDF Document", "json": "JSON", "png": "PNG Image", "sh": "Shell Script", "mp4": "MPEG-4 Movie",
        "swift": "Swift Source",
    ]

    /// A pane on `folder`: folders are (name, total size or nil while it is
    /// being measured, date), files (name, size, date).
    private static func pane(
        _ folder: URL, folders: [(String, Int64?, Date)], files: [(String, Int64, Date)], selected: Set<String>,
        pointer: String?
    ) -> Pane {
        var entries: [Entry] = [], sizes: [URL: Int64] = [:]
        for (name, size, modified) in folders {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            entries.append(Entry(url: url, name: name, kind: .folder, size: nil, modified: modified,
                                 isHidden: name.hasPrefix("."), typeDescription: "Folder"))
            sizes[url] = size
        }
        for (name, size, modified) in files {
            let ext = name.hasPrefix(".") ? "" : URL(fileURLWithPath: name).pathExtension.lowercased()
            entries.append(Entry(url: folder.appendingPathComponent(name), name: name, kind: .file, size: size,
                                 modified: modified, isHidden: name.hasPrefix("."),
                                 typeDescription: kinds[ext] ?? "Document"))
        }
        return Pane(folder: folder, entries: entries, sizes: sizes, selected: selected, pointer: pointer)
    }

    /// project-grove, with its hidden items (shown only when the scene says so).
    static func grove(selected: Set<String>, pointer: String? = nil) -> Pane {
        pane(home.appendingPathComponent("Developer/project-grove", isDirectory: true), folders: [
            (".git", 48_900_000, date(2026, 11, 12, 9, 41)),
            (".github", 12_000, date(2026, 11, 2, 10, 15)),
            ("artifacts", 1_840_000_000, date(2026, 11, 12, 9, 12)),
            ("assets", 12_600_000, date(2026, 11, 9, 2, 4)),
            ("docs", 348_000, date(2026, 11, 11, 18, 2)),
            ("grove-dotfiles", 9_100_000, date(2026, 11, 12, 8, 47)),
            ("grove-keys", 214_300_000, date(2026, 11, 12, 9, 41)),
            ("grove-themes", nil, date(2026, 11, 11, 23, 15)),
            ("grove-wallpapers", 86_200_000, date(2026, 11, 3, 21, 40)),
        ], files: [
            (".gitignore", 312, date(2026, 10, 28, 14, 22)),
            ("CHANGELOG.md", 6_000, date(2026, 11, 11, 18, 2)),
            ("LICENSE", 1_000, date(2026, 10, 28, 14, 22)),
            ("README.md", 4_000, date(2026, 11, 12, 9, 41)),
        ], selected: selected, pointer: pointer)
    }

    static func downloads(selected: Set<String>, pointer: String? = nil) -> Pane {
        pane(home.appendingPathComponent("Downloads", isDirectory: true), folders: [
            ("fonts", 18_200_000, date(2026, 11, 2, 10, 15)),
            ("invoices-2026", 4_700_000, date(2026, 10, 30, 16, 48)),
        ], files: [
            ("config.toml", 2_000, date(2026, 11, 5, 11, 20)),
            ("data-export.csv", 418_000, date(2026, 11, 6, 9, 3)),
            ("everforest-master.zip", 3_900_000, date(2026, 11, 1, 22, 10)),
            ("Ghostty.dmg", 41_600_000, date(2026, 11, 11, 20, 31)),
            ("icon-set.svg", 28_000, date(2026, 11, 4, 13, 37)),
            ("JetBrainsMono-2.304.zip", 5_600_000, date(2026, 10, 31, 8, 12)),
            ("keyboard-shortcuts.pdf", 1_200_000, date(2026, 11, 9, 2, 4)),
            ("notes.md", 3_000, date(2026, 11, 12, 9, 41)),
            ("package.json", 1_000, date(2026, 11, 7, 15, 55)),
            ("Screenshot 2026-11-11 at 17.30.02.png", 2_400_000, date(2026, 11, 11, 17, 30)),
            ("Screenshot 2026-11-12 at 09.12.44.png", 1_800_000, date(2026, 11, 12, 9, 12)),
            ("setup.sh", 4_000, date(2026, 11, 8, 19, 26)),
            ("talk-recording.mp4", 128_400_000, date(2026, 10, 27, 21, 2)),
            ("theme.swift", 9_000, date(2026, 11, 10, 12, 44)),
            ("wallpaper-forest.png", 6_300_000, date(2026, 11, 3, 21, 40)),
        ], selected: selected, pointer: pointer)
    }

    /// The folders that carry a mark, each at the path that gives it one, and a plain one.
    static func knownFolders() -> Pane {
        let places: [(String, URL)] = [
            ("Applications", URL(fileURLWithPath: "/Applications", isDirectory: true)),
            ("Desktop", home.appendingPathComponent("Desktop", isDirectory: true)),
            ("Developer", home.appendingPathComponent("Developer", isDirectory: true)),
            ("Documents", home.appendingPathComponent("Documents", isDirectory: true)),
            ("Downloads", home.appendingPathComponent("Downloads", isDirectory: true)),
            ("Home", home),
            ("Other", home.appendingPathComponent("Other", isDirectory: true)),
        ]
        let entries = places.map { name, url in
            Entry(url: url, name: name, kind: .folder, size: nil, modified: date(2026, 11, 12, 9, 41), isHidden: false,
                  typeDescription: "Folder")
        }
        return Pane(folder: home, entries: entries, sizes: [:], selected: ["Desktop"], pointer: nil)
    }
}
