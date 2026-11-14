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
        /// Folders open in place (spec §16): each open folder's entries
        /// (one open and missing here is still being read), which folders
        /// are open, which have something in them (a chevron), and the sort.
        var children: [URL: [Entry]] = [:]
        var open: Set<URL> = []
        var peeks: [URL: Bool] = [:]
        var sort = GroveExplorerCore.SortOrder.byName

        /// The entry at `path` below the folder ("grove-explorer/app/Package.swift"),
        /// at any depth; a name for the folder's own items.
        func entry(_ path: String) -> Entry? {
            let wanted = folder.appendingPathComponent(path).path
            return entries.first { $0.url.path == wanted }
                ?? children.values.lazy.flatMap { $0 }.first { $0.url.path == wanted }
        }
    }

    /// What a scene shows beside its panes.
    struct Extras {
        /// The active pane's path bar is the field, saying this.
        var pathField: String?
        /// The active pane's path bar's copy button: under the pointer; just copied.
        var copyPointer = false
        var pathCopied = false
        var pathMissing = false
        var active = Side.left
        /// Backup's eject button: under the pointer, working, or refused.
        var ejectPointer = false
        var ejecting = false
        var ejectFailure: String?
        /// What the status bar of `statusSide` says of an operation.
        var status: PaneStatus?
        var statusSide = Side.left
        /// What that pane's status bar says for a few seconds meanwhile.
        var notice: String?
        /// The list of failed items is open over that pane.
        var failuresShown = false
        /// The conflict prompt is up.
        var prompt: ConflictPromptState?
        /// The left pane's row of this name (a path below its folder) is the rename field; saying
        /// `renameText` instead when given, and red with `renameReason`.
        var rename: String?
        var renameText: String?
        var renameReason: String?
        /// The row of this name (a path below the folder) in `dropSide`'s pane is where a drag would drop.
        var dropRow: String?
        var dropSide = Side.right
        /// The left pane's filter field is open, has the keyboard and says this.
        var filter: String?
        /// The sidebar lists OneDrive's two accounts under their header.
        var clouds = false
        /// Locations has the three saved shares after the disks: media
        /// connected, backup not, photos connecting (`Sample.shares`); then
        /// scratch, a network volume that isn't saved.
        var shares = false
        /// The full sidebar's chosen width (the default when nil).
        var sidebarWidth: Double?
        /// The left pane's share of the two panes.
        var split = 0.5
        /// The Connect to Server sheet is up, saying this, with this sentence under the field.
        var connectSheet: (text: String, problem: String?)?
        /// The menu ⌃Return opens is drawn open (`MenuStandIn`): the active
        /// pane's selection's, Open With offering these apps (and open,
        /// `openWithOpen`); or, with `sidebarMenu`, the menu of the sidebar
        /// row of that title, the keyboard on it.
        var listMenu: (standard: URL?, all: [URL])?
        var openWithOpen = true
        var sidebarMenu: String?
    }

    /// What Open With offers for a Markdown file in a render: the default
    /// first, the others after its line, by name.
    static let markdownApps: (standard: URL?, all: [URL]) = {
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app", isDirectory: true)
        return (textEdit, [
            URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true),
            textEdit,
            URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true),
        ])
    }()

    /// The saved shares of a render (the spec's grove-lab, no real address).
    static let shares = [
        SharedServer(url: URL(string: "smb://grove-lab/media")!),
        SharedServer(url: URL(string: "smb://grove-lab/backup")!),
        SharedServer(url: URL(string: "smb://grove-lab/photos")!),
    ]
    /// media, mounted (by the address macOS keeps, with the user it logged in as).
    static let mediaVolume = Volume(
        url: URL(fileURLWithPath: "/Volumes/media", isDirectory: true), name: "media", ejectable: true,
        remountURL: URL(string: "smb://you@grove-lab/media"), isNetwork: true)
    /// scratch, mounted by Finder and not saved: the last of Locations, with "Keep in Sidebar".
    static let scratchVolume = Volume(
        url: URL(fileURLWithPath: "/Volumes/scratch", isDirectory: true), name: "scratch", ejectable: true,
        remountURL: URL(string: "smb://you@grove-lab/scratch"), isNetwork: true)

    /// The sentence a mount of `address` gets when the server has no such share (as NetFS answers, ENOENT).
    static func noShare(_ address: String) -> String? {
        guard let url = URL(string: address),
            case .failed(let sentence) = SharedServers.outcome(status: ENOENT, mountPoint: nil, server: url)
        else { return nil }
        return sentence
    }

    /// Inside the connected share: its row lit.
    static func media() -> Pane {
        pane(mediaVolume.url, folders: [
            ("films", 412_000_000_000, date(2026, 11, 8, 21, 14)),
            ("music", 96_400_000_000, date(2026, 11, 10, 18, 2)),
            ("series", 1_210_000_000_000, date(2026, 11, 12, 7, 30)),
        ], files: [
            ("README.md", 2_000, date(2026, 10, 2, 11, 5)),
        ], selected: [], pointer: nil)
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
        var trees: [Side: FolderListing.Tree] = [:]
        for (side, pane) in zip(sides, panes) {
            // The tab showing has been somewhere: back is lit, forward is not.
            browser.panes[side.rawValue].tabs[0] = Tab(folder: pane.folder, sort: pane.sort, back: [home])
            browser.panes[side.rawValue].tabs[0].setOpen(pane.open)
            browser.panes[side.rawValue].tabs += pane.otherTabs.map { Tab(folder: $0) }
            entries[side] = pane.entries
            selected[side] = Set(pane.selected.compactMap { pane.entry($0)?.url })
            sizes.merge(pane.sizes) { $1 }
            pointer[side] = pane.pointer.flatMap { pane.entry($0)?.url }
            if let problem = pane.problem { problems[side] = (problem, pane.needsPermission) }
            trees[side] = FolderListing.Tree(children: pane.children, peeks: pane.peeks)
        }
        browser.active = extras.active
        // The built-in defaults: no file is read.
        let config = ExplorerConfig.load(tracked: nil, local: nil, home: home, exists: { _ in true })
        let now = now
        let clock = ListClock(now: { now }, calendar: calendar, locale: Locale(identifier: "en_GB"))
        let model = AppModel.fixed(
            browser: browser, config: config, clock: clock, colors: colors, entries: entries, sizes: sizes,
            free: 212_400_000_000, selected: selected, problems: problems,
            filters: extras.filter.map { [.left: $0] } ?? [:], tree: trees)
        if extras.filter != nil { model.filter.focused = .left }
        model.pointerStandIn = pointer
        for (side, pane) in zip(sides, panes) { model.tabPointerStandIn[side] = pane.pointerTab }

        // The sidebar: iCloud Drive, the startup disk and an external one,
        // with macOS's icons for them (nothing is mounted or read).
        let disk = Volume(url: URL(fileURLWithPath: "/", isDirectory: true), name: "Macintosh HD", ejectable: false)
        model.hasCloud = true
        if extras.clouds {
            model.cloudProviders = FolderName.providers(in: ["OneDrive-Personal", "OneDrive-Contoso"], home: home)
        }
        model.volumes = [disk, backup]
        if extras.shares {
            model.config.servers = shares
            // As macOS lists them: Locations puts the shares after the disks.
            model.volumes = [disk, mediaVolume, scratchVolume, backup]
            model.connectingShares = [shares[2].id]
        }
        model.volumeIconStandIn = [
            disk.id: NSWorkspace.shared.icon(forFile: "/"),
            backup.id: NSWorkspace.shared.icon(for: UTType("com.apple.storage-external") ?? .volume),
            scratchVolume.id: NSWorkspace.shared.icon(for: .volume),
        ]
        if let width = extras.sidebarWidth { model.sidebarWidth = width }
        model.split = extras.split
        if extras.ejectPointer { model.ejectPointerStandIn = backup.id }
        if extras.ejecting { model.ejecting = [backup.id] }
        if let failure = extras.ejectFailure { model.ejectFailures = [backup.id: failure] }
        if extras.copyPointer { model.copyPointerStandIn = extras.active }
        if extras.pathCopied { model.pathCopied = (extras.active, UUID()) }
        if let text = extras.pathField {
            model.pathField = PathFieldState(side: extras.active, text: text, missing: extras.pathMissing)
        }
        if let status = extras.status { model.work.statuses[extras.statusSide] = status }
        if let notice = extras.notice { model.notices[extras.statusSide] = notice }
        if extras.failuresShown { model.work.failuresShown = extras.statusSide }
        model.work.prompt = extras.prompt
        if let name = extras.rename, let entry = panes[0].entry(name) {
            model.work.rename = RenameState(
                id: UUID(), side: .left, url: entry.url, name: entry.name, isFolder: entry.kind == .folder,
                reason: extras.renameReason, standIn: extras.renameText)
        }
        if let name = extras.dropRow, let pane = zip(sides, panes).first(where: { $0.0 == extras.dropSide })?.1,
            let entry = pane.entry(name)
        {
            model.dropMark = .row(extras.dropSide, entry.url)
        }
        model.openWithStandIn = extras.listMenu
        if let title = extras.sidebarMenu {
            guard let row = model.places.firstIndex(where: { $0.title == title }) else { fail("no sidebar row \(title)") }
            model.sidebarCursor = row
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

    static let iCloudDrive = home.appendingPathComponent(FolderName.iCloudDrive, isDirectory: true)
    static let oneDrive = home.appendingPathComponent(FolderName.cloudStorage + "/OneDrive-Personal", isDirectory: true)

    /// iCloud Drive's Notes, with a tab on iCloud Drive itself.
    static func iCloudNotes() -> Pane {
        pane(iCloudDrive.appendingPathComponent("Notes", isDirectory: true), folders: [
            ("2025", 3_400_000, date(2026, 1, 4, 10, 12)),
            ("recipes", 820_000, date(2026, 10, 18, 19, 40)),
        ], files: [
            ("groceries.md", 1_000, date(2026, 11, 12, 8, 3)),
            ("ideas.md", 6_000, date(2026, 11, 10, 22, 15)),
            ("reading-list.md", 2_000, date(2026, 11, 7, 13, 30)),
        ], selected: ["ideas.md"], pointer: nil, otherTabs: [iCloudDrive])
    }

    /// OneDrive's Documents.
    static func oneDriveDocuments() -> Pane {
        pane(oneDrive.appendingPathComponent("Documents", isDirectory: true), folders: [
            ("Taxes", 12_800_000, date(2026, 4, 21, 9, 2)),
        ], files: [
            ("budget-2026.xlsx", 48_000, date(2026, 11, 9, 18, 44)),
            ("cv.pdf", 210_000, date(2026, 10, 2, 11, 5)),
        ], selected: [], pointer: nil)
    }

    /// OneDrive's own folder, with a tab on its Documents.
    static func oneDriveTop() -> Pane {
        pane(oneDrive, folders: [
            ("Desktop", 1_200_000, date(2026, 11, 13, 13, 22)),
            ("Documents", 13_058_000, date(2026, 11, 9, 18, 44)),
            ("Pictures", 640_000_000, date(2026, 11, 1, 16, 10)),
        ], files: [], selected: [], pointer: nil, otherTabs: [oneDrive.appendingPathComponent("Documents", isDirectory: true)])
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

// MARK: Folders open in place

extension Sample {
    /// A folder or a file of a sample tree (spec §16's mock-ups).
    struct Node {
        var name: String
        var kind = Entry.Kind.file
        /// A file's size, or a folder's total (nil while it is measured).
        var size: Int64?
        var date: Date
        /// Open in place, showing these; nil: closed (or a file).
        var children: [Node]?
        /// Open, its contents still being read.
        var loading = false
        /// A symbolic link's target (`kind` is then a link's).
        var link: Entry.Link?

        static func file(_ name: String, _ size: Int64, _ date: Date) -> Node {
            Node(name: name, size: size, date: date)
        }

        static func folder(_ name: String, _ size: Int64?, _ date: Date, _ children: [Node]? = nil) -> Node {
            Node(name: name, kind: .folder, size: size, date: date, children: children)
        }

        /// A link that says `target`; `toFolder` and `broken` as following it would find.
        static func link(_ name: String, _ target: String, toFolder: Bool = false, broken: Bool = false, _ date: Date) -> Node {
            Node(
                name: name, kind: .symlink(toFolder: toFolder && !broken), size: Int64(target.utf8.count), date: date,
                link: Entry.Link(target: target, isBroken: broken))
        }

        static func loading(_ name: String, _ size: Int64?, _ date: Date) -> Node {
            Node(name: name, kind: .folder, size: size, date: date, children: [], loading: true)
        }
    }

    /// A pane on `folder` showing `nodes`: every folder has something in
    /// it (a chevron), each open one is open, and its contents are listed
    /// unless it is still being read. `selected` and `pointer` are paths below `folder`.
    static func tree(
        _ folder: URL, _ nodes: [Node], selected: Set<String> = [], pointer: String? = nil,
        sort: GroveExplorerCore.SortOrder = .byName
    ) -> Pane {
        var pane = Pane(folder: folder, entries: [], sizes: [:], selected: selected, pointer: pointer, otherTabs: [
            home.appendingPathComponent("Developer/project-grove/grove-dotfiles", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
        ])
        pane.sort = sort
        func entries(_ nodes: [Node], in folder: URL) -> [Entry] {
            nodes.map { node in
                let isFolder = node.kind == .folder
                let url = folder.appendingPathComponent(node.name, isDirectory: isFolder)
                let ext = node.name.hasPrefix(".") ? "" : url.pathExtension.lowercased()
                if isFolder {
                    pane.sizes[url] = node.size
                    pane.peeks[url] = true
                    if let children = node.children {
                        pane.open.insert(url)
                        if !node.loading { pane.children[url] = entries(children, in: url) }
                    }
                }
                let type = if let link = node.link { LinkText.kind(isBroken: link.isBroken) }
                    else if isFolder { "Folder" } else { kinds[ext] ?? "Document" }
                return Entry(
                    url: url, name: node.name, kind: node.kind, size: isFolder ? nil : node.size, modified: node.date,
                    isHidden: node.name.hasPrefix("."), typeDescription: type, link: node.link)
            }
        }
        pane.entries = entries(nodes, in: folder)
        return pane
    }

    static let project = home.appendingPathComponent("Developer/project-grove", isDirectory: true)

    /// The mock-ups' project-grove. `explorer` is grove-explorer's contents
    /// (nil: closed), `keys` grove-keys' (nil: closed; empty: being read).
    static func projectTree(explorer: [Node]?, keys: [Node]?) -> [Node] {
        [
            .folder(".git", 48_900_000, date(2026, 11, 12, 9, 41)),
            .folder("artifacts", 1_840_000_000, date(2026, 11, 12, 9, 12)),
            .folder("assets", 12_600_000, date(2026, 11, 9, 2, 4)),
            .folder("docs", 348_000, date(2026, 11, 11, 18, 2)),
            .folder("grove-dotfiles", 9_100_000, date(2026, 11, 12, 8, 47)),
            .folder("grove-explorer", 2_100_000, date(2026, 11, 12, 9, 30), explorer),
            keys.map { $0.isEmpty
                ? .loading("grove-keys", 214_300_000, date(2026, 11, 12, 9, 41))
                : .folder("grove-keys", 214_300_000, date(2026, 11, 12, 9, 41), $0) }
                ?? .folder("grove-keys", 214_300_000, date(2026, 11, 12, 9, 41)),
            .folder("grove-themes", nil, date(2026, 11, 11, 23, 15)),
            .folder("grove-wallpapers", 86_200_000, date(2026, 11, 3, 21, 40)),
            .file(".gitignore", 312, date(2026, 10, 28, 14, 22)),
            .file("CHANGELOG.md", 6_000, date(2026, 11, 11, 18, 2)),
            .file("LICENSE", 1_000, date(2026, 10, 28, 14, 22)),
            .file("README.md", 4_000, date(2026, 11, 12, 9, 41)),
        ]
    }

    /// grove-explorer/app, with Sources' contents (nil: closed) and
    /// GroveExplorerCore's (nil: closed).
    static func explorerApp(sources: Bool, core: Bool) -> [Node] {
        let coreFiles: [Node] = [
            .file("Arrangement.swift", 4_000, date(2026, 11, 11, 13, 5)),
            .file("Browser.swift", 9_000, date(2026, 11, 11, 11, 40)),
            .file("ConflictAsking.swift", 3_000, date(2026, 11, 11, 10, 2)),
            .file("Entry.swift", 2_000, date(2026, 11, 11, 10, 5)),
            .file("Filter.swift", 3_000, date(2026, 11, 11, 12, 18)),
            .file("FolderReader.swift", 6_000, date(2026, 11, 11, 12, 44)),
            .file("GroveExplorerInfo.swift", 1_000, date(2026, 11, 11, 10, 5)),
            .file("OperationRunner.swift", 11_000, date(2026, 11, 11, 22, 31)),
            .file("ReadGate.swift", 2_000, date(2026, 11, 11, 19, 26)),
            .file("ReadProblem.swift", 3_000, date(2026, 11, 11, 14, 9)),
            .file("Sorting.swift", 5_000, date(2026, 11, 11, 10, 58)),
        ]
        return [
            .folder("app", 2_100_000, date(2026, 11, 12, 9, 30), [
                .folder("Sources", 1_400_000, date(2026, 11, 12, 9, 30), sources ? [
                    .folder("GroveExplorer", 1_100_000, date(2026, 11, 12, 9, 30)),
                    .folder("GroveExplorerCore", 312_000, date(2026, 11, 11, 22, 31), core ? coreFiles : nil),
                ] : nil),
                .folder("Tests", 652_000, date(2026, 11, 11, 22, 40)),
                .file("make-resources.sh", 718, date(2026, 11, 11, 13, 5)),
                .file("Package.swift", 2_000, date(2026, 11, 11, 13, 5)),
            ]),
            .folder("deps", 64, date(2026, 11, 11, 10, 5)),
        ]
    }

    /// grove-keys open: its app, deps and README.
    static let keysContents: [Node] = [
        .folder("app", 213_900_000, date(2026, 11, 12, 9, 41)),
        .folder("deps", 64, date(2026, 11, 11, 10, 5)),
        .file("README.md", 3_000, date(2026, 11, 10, 16, 20)),
    ]

    /// The home folder's links (the dotfiles'): one far into home whose
    /// target is long, relative ones, a broken one; and an open folder with
    /// a link inside it.
    static func homeLinks(selected: Set<String> = [], pointer: String? = nil) -> Pane {
        let homePath = home.path
        let at = date(2026, 11, 12, 9, 41)
        return tree(home, [
            .folder(".config", 4_200, at, [
                .link("ghostty", "../Developer/project-grove/grove-dotfiles/config/ghostty", toFolder: true, at),
                .file("starship.toml", 2_000, date(2026, 11, 10, 16, 20)),
            ]),
            .link(".gitconfig", "Developer/old-dotfiles/gitconfig", broken: true, date(2026, 9, 2, 10, 15)),
            .link(".ssh", homePath + "/Library/CloudStorage/OneDrive-Personal/dot-ssh", toFolder: true, at),
            .link(".zshenv", "Developer/project-grove/grove-dotfiles/config/zsh/.zshenv", at),
            .link("bin", "/opt/homebrew/bin", toFolder: true, date(2026, 10, 30, 16, 48)),
            .folder("Developer", 2_400_000_000, date(2026, 11, 12, 9, 30)),
            .folder("Documents", 1_200_000_000, date(2026, 11, 11, 18, 2)),
            .file("notes.md", 3_000, date(2026, 11, 12, 9, 41)),
        ], selected: selected, pointer: pointer)
    }

    /// Downloads as a tree pane: nothing opened, its folders with chevrons.
    static func downloadsTree() -> Pane {
        var pane = downloads(selected: [])
        for entry in pane.entries where entry.kind == .folder { pane.peeks[entry.url] = true }
        return pane
    }
}

extension AppModel {
    /// A model that shows what it is given and reads nothing: for a render.
    static func fixed(
        browser: Browser, config: ExplorerConfig, clock: ListClock, colors: ThemeColors,
        entries: [Side: [Entry]], sizes: [URL: Int64], free: Int64, selected: [Side: Set<URL>],
        problems: [Side: (sentence: String, needsPermission: Bool)] = [:], filters: [Side: String] = [:],
        tree: [Side: FolderListing.Tree] = [:]
    ) -> AppModel {
        let model = AppModel(browser: browser, config: config, clock: clock, live: false)
        model.colors = colors
        model.sizes = sizes
        for (side, all) in entries {
            guard let tab = browser.tab(side) else { continue }
            if let text = filters[side] { model.filter.tabs[tab.id] = ListFilter(text: text) }
            let wanted = model.arrangement(for: tab)
            // The folders open in the tab (the browser's) and their listings, as given.
            let opened = tree[side] ?? FolderListing.Tree()
            var listing = Listing(
                folder: tab.folder, all: all, children: opened.children, peeks: opened.peeks,
                problem: problems[side]?.sentence, needsPermission: problems[side]?.needsPermission ?? false,
                free: free, state: .arranged(by: wanted), revision: 1)
            listing.take(FolderListing.arranged(all, tree: opened, by: wanted, sizes: sizes))
            model.listings[side] = listing
            model.selections[tab.id] = selected[side] ?? []
        }
        model.revision = 1
        return model
    }
}
