import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI
import UniformTypeIdentifiers

/// The mock-ups' folders, as entries: nothing here is read from the disk.
@MainActor
enum Sample {
    struct Pane {
        var folder: URL
        var entries: [Entry]
        var sizes: [URL: Int64]
        var selected: Set<String>
        var pointer: String?
        /// The pane's other tabs, after the one showing.
        var otherTabs: [URL] = []
        /// The tab drawn as under the pointer.
        var pointerTab: Int?
        /// Why the folder can't be read, and whether Privacy Settings helps.
        var problem: String?
        var needsPermission = false
    }

    /// What a scene shows beside its panes.
    struct Extras {
        /// The active pane's path bar is the field, saying this.
        var pathField: String?
        var pathMissing = false
        var active = Side.left
        /// Backup's eject button: under the pointer, working, or refused.
        var ejectPointer = false
        var ejecting = false
        var ejectFailure: String?
        /// What the status bar of `statusSide` says of an operation.
        var status: PaneStatus?
        var statusSide = Side.left
        /// The list of failed items is open over that pane.
        var failuresShown = false
        /// The conflict prompt is up.
        var prompt: ConflictPromptState?
        /// The left pane's row of this name is the rename field; saying
        /// `renameText` instead when given, and red with `renameReason`.
        var rename: String?
        var renameText: String?
        var renameReason: String?
        /// The right pane's row of this name is where a drag would drop.
        var dropRow: String?
        /// The left pane's filter field is open, has the keyboard and says this.
        var filter: String?
    }

    static let backup = Volume(url: URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true), name: "Backup", ejectable: true)

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

    static func model(panes: [Pane], showHidden: Bool, colors: ThemeColors, extras: Extras = Extras()) -> AppModel {
        var browser = Browser(start: panes[0].folder, twoPanes: panes.count == 2, showHidden: showHidden)
        let sides: [Side] = [.left, .right]
        var entries: [Side: [Entry]] = [:], selected: [Side: Set<URL>] = [:], sizes: [URL: Int64] = [:]
        var pointer: [Side: URL] = [:], problems: [Side: (String, Bool)] = [:]
        for (side, pane) in zip(sides, panes) {
            // The tab showing has been somewhere: back is lit, forward is not.
            browser.panes[side.rawValue].tabs[0] = Tab(folder: pane.folder, back: [home])
            browser.panes[side.rawValue].tabs += pane.otherTabs.map { Tab(folder: $0) }
            entries[side] = pane.entries
            selected[side] = Set(pane.entries.filter { pane.selected.contains($0.name) }.map(\.url))
            sizes.merge(pane.sizes) { $1 }
            pointer[side] = pane.entries.first { $0.name == pane.pointer }?.url
            if let problem = pane.problem { problems[side] = (problem, pane.needsPermission) }
        }
        browser.active = extras.active
        // The built-in defaults: no file is read.
        let config = ExplorerConfig.load(tracked: nil, local: nil, home: home, exists: { _ in true })
        let now = now
        let clock = ListClock(now: { now }, calendar: calendar, locale: Locale(identifier: "en_GB"))
        let model = AppModel.fixed(
            browser: browser, config: config, clock: clock, colors: colors, entries: entries, sizes: sizes,
            free: 212_400_000_000, selected: selected, problems: problems,
            filters: extras.filter.map { [.left: $0] } ?? [:])
        if extras.filter != nil { model.filter.focused = .left }
        model.pointerStandIn = pointer
        for (side, pane) in zip(sides, panes) { model.tabPointerStandIn[side] = pane.pointerTab }

        // The sidebar: iCloud Drive, the startup disk and an external one,
        // with macOS's icons for them (nothing is mounted or read).
        let disk = Volume(url: URL(fileURLWithPath: "/", isDirectory: true), name: "Macintosh HD", ejectable: false)
        model.hasCloud = true
        model.volumes = [disk, backup]
        model.volumeIconStandIn = [
            disk.id: NSWorkspace.shared.icon(forFile: "/"),
            backup.id: NSWorkspace.shared.icon(for: UTType("com.apple.storage-external") ?? .volume),
        ]
        if extras.ejectPointer { model.ejectPointerStandIn = backup.id }
        if extras.ejecting { model.ejecting = [backup.id] }
        if let failure = extras.ejectFailure { model.ejectFailures = [backup.id: failure] }
        if let text = extras.pathField {
            model.pathField = PathFieldState(side: extras.active, text: text, missing: extras.pathMissing)
        }
        if let status = extras.status { model.work.statuses[extras.statusSide] = status }
        if extras.failuresShown { model.work.failuresShown = extras.statusSide }
        model.work.prompt = extras.prompt
        if let name = extras.rename, let entry = entries[.left]?.first(where: { $0.name == name }) {
            model.work.rename = RenameState(
                id: UUID(), side: .left, url: entry.url, name: entry.name, isFolder: entry.kind == .folder,
                reason: extras.renameReason, standIn: extras.renameText)
        }
        if let name = extras.dropRow, let entry = entries[.right]?.first(where: { $0.name == name }) {
            model.dropMark = .row(.right, entry.url)
        }
        return model
    }

    private static let kinds: [String: String] = [
        "md": "Markdown", "toml": "TOML", "csv": "CSV", "zip": "ZIP Archive", "dmg": "Disk Image", "svg": "SVG Image",
        "pdf": "PDF Document", "json": "JSON", "png": "PNG Image", "sh": "Shell Script", "mp4": "MPEG-4 Movie",
        "swift": "Swift Source",
    ]

    /// A pane on `folder`: folders are (name, total size or nil while it is
    /// being measured, date), files (name, size, date).
    static func pane(
        _ folder: URL, folders: [(String, Int64?, Date)], files: [(String, Int64, Date)], selected: Set<String>,
        pointer: String?, otherTabs: [URL] = [], pointerTab: Int? = nil
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
        return Pane(
            folder: folder, entries: entries, sizes: sizes, selected: selected, pointer: pointer, otherTabs: otherTabs,
            pointerTab: pointerTab)
    }

    /// A folder with nothing in it, or one that can't be read.
    static func bare(_ folder: URL, problem: String? = nil, needsPermission: Bool = false) -> Pane {
        Pane(folder: folder, entries: [], sizes: [:], selected: [], pointer: nil, problem: problem,
             needsPermission: needsPermission)
    }

    /// project-grove, with its hidden items (shown only when the scene says
    /// so) and its two other tabs.
    static func grove(selected: Set<String>, pointer: String? = nil, pointerTab: Int? = nil) -> Pane {
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
        ], selected: selected, pointer: pointer, otherTabs: [
            home.appendingPathComponent("Developer/project-grove/grove-dotfiles", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
        ], pointerTab: pointerTab)
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
        ], selected: selected, pointer: pointer, otherTabs: [URL(fileURLWithPath: "/Applications", isDirectory: true)])
    }

    /// Downloads as the filter's mock-up has it: 212 items, four of them screenshots.
    static func manyDownloads() -> Pane {
        var pane = downloads(selected: [])
        let folder = pane.folder
        func file(_ name: String, _ size: Int64, _ modified: Date) -> Entry {
            Entry(url: folder.appendingPathComponent(name), name: name, kind: .file, size: size, modified: modified,
                  isHidden: false, typeDescription: name.hasSuffix(".png") ? "PNG Image" : "Plain Text")
        }
        pane.entries += [
            file("Screenshot 2026-11-08 at 14.05.51.png", 1_100_000, date(2026, 11, 8, 14, 5)),
            file("Screenshot 2026-11-10 at 22.48.19.png", 3_000_000, date(2026, 11, 10, 22, 48)),
        ]
        pane.entries += (pane.entries.count..<212).map { file("log-\($0).txt", 2_000, date(2026, 10, 1, 8, 0)) }
        return pane
    }

    /// Documents, where the mock-ups' copy meets a "notes.md" that is there.
    static func documents() -> Pane {
        pane(home.appendingPathComponent("Documents", isDirectory: true), folders: [
            ("archive", 1_200_000_000, date(2026, 10, 14, 11, 5)),
            ("letters", 2_400_000, date(2026, 11, 2, 10, 15)),
        ], files: [
            ("contract.pdf", 38_000, date(2026, 11, 6, 9, 3)),
            ("notes.md", 2_000, date(2026, 11, 9, 2, 4)),
            ("todo.md", 1_000, date(2026, 11, 11, 18, 2)),
        ], selected: [], pointer: nil)
    }

    /// The prompt about that "notes.md", with three more names after it.
    static func notesConflict() -> ConflictPromptState {
        ConflictPromptState(
            question: Conflict.Question(
                incoming: home.appendingPathComponent("Downloads/notes.md"),
                existing: home.appendingPathComponent("Documents/notes.md"), remaining: 3,
                incomingSize: 3_000, incomingDate: date(2026, 11, 12, 9, 41),
                existingSize: 2_000, existingDate: date(2026, 11, 9, 2, 4)),
            comingLabel: "Being copied")
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
