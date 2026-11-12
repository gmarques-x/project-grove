import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The window's state and what keeps it current: the browser (panes, tabs,
/// folders, sort), each pane's listing, the selection, the folder sizes, the
/// config and the theme. Thin: what can be pure is in GroveExplorerCore.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var browser: Browser {
        didSet { if browser != oldValue { sessionChanged() } }
    }
    /// Folder and package totals known so far, by `Entry.url`.
    @Published var sizes: [URL: Int64] = [:] {
        didSet { sizesVersion += 1 }
    }
    /// The current scheme's colours; they follow a scheme switch.
    @Published var colors = ThemeColors.fallback
    @Published private var listings: [Side: Listing] = [:]
    /// Each tab's selection, by the tab's id.
    @Published private var selections: [UUID: Set<URL>] = [:] {
        didSet { selectionVersion += 1 }
    }
    /// Change with `sizes` and with the selections: what the list and the
    /// status bar compare instead of the collections themselves.
    private(set) var sizesVersion = 0
    private(set) var selectionVersion = 0

    @Published var config: ExplorerConfig
    let clock: ListClock
    let home = FileManager.default.homeDirectoryForCurrentUser

    // The window's own layout, kept in the session.
    /// ⌘⌥S: the sidebar is put away.
    @Published var sidebarHidden = false {
        didSet { if sidebarHidden != oldValue { sessionChanged() } }
    }
    /// The left pane's share of the two panes' width.
    @Published var split = 0.5 {
        didSet { if split != oldValue { sessionChanged() } }
    }

    // The path field, the sidebar and what the status bars say for a while.
    /// ⌘L: the pane whose path bar is a text field, and what it says.
    @Published var pathField: PathFieldState?
    /// The sidebar row the keyboard is on (⌥⌘←); nil while the keys are the list's.
    @Published var sidebarCursor: Int?
    /// The mounted volumes, and the ones being ejected or that couldn't be.
    @Published var volumes: [Volume] = []
    @Published var ejecting: Set<String> = []
    @Published var ejectFailures: [String: String] = [:]
    /// Whether iCloud Drive's folder exists.
    @Published var hasCloud = false
    /// What a pane's status bar says for a few seconds ("x is no longer there").
    @Published var notices: [Side: String] = [:]
    /// A problem the whole window is about, beside the config's own: the
    /// favourites couldn't be saved.
    @Published var writeProblem: String?
    /// Goes up when the active pane's list should take the keyboard (again).
    @Published var listFocus = 1

    /// Renders only: the row, the tab and the sidebar row drawn as under
    /// the pointer, and icons for volumes that aren't there.
    var pointerStandIn: [Side: URL] = [:]
    var tabPointerStandIn: [Side: Int] = [:]
    var ejectPointerStandIn: String?
    var volumeIconStandIn: [String: NSImage] = [:]

    /// False in a render: nothing is read, watched, measured or saved.
    let live: Bool
    var store: SessionStore?
    var mounts: MountObserver?
    /// Counts the reads of the mounted volumes: the latest one answers.
    var volumeReads = 0
    var typeJump = TypeJump()
    var noticeTimers: [Side: Task<Void, Never>] = [:]
    /// A name to select once the pane has read its folder (a link to a
    /// file, a file's path typed in the path field).
    var selectWhenRead: [Side: String] = [:]
    /// A row the pane's list should scroll to; the list takes it.
    private var reveals: [Side: URL] = [:]
    /// The tab and folder each pane's rows were last asked for.
    private var shownKeys: [Side: String] = [:]
    /// The path bar's parts, kept per folder: the volume's name is asked of the system.
    private var partsCache: [String: [PathBar.Part]] = [:]
    private var revision = 0
    private var loads: [Side: Int] = [:]
    private var sorts: [Side: Int] = [:]
    var watchers: [Side: (path: String, watcher: FolderWatcher)] = [:]
    let sizeQueue = SizeQueue()
    /// A sort by size waiting for more totals to arrive, per pane.
    var sizeSorts: [Side: Task<Void, Never>] = [:]
    /// The status bar's words, kept while nothing they are made of changed.
    private var statuses: [Side: (tab: UUID?, revision: Int, selection: Int, sizes: Int, text: String)] = [:]

    var themeWatcher: FolderWatcher?
    var themeState: Data?

    /// The app's model: the config from `~/.config/grove-explorer`, a window on its `start`.
    static func standard() -> AppModel {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home.appendingPathComponent(".config/grove-explorer", isDirectory: true)
        func text(_ name: String) -> String? {
            try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        }
        let config = ExplorerConfig.load(
            tracked: text("explorer.toml"), local: text("explorer.local.toml"), home: home,
            exists: { FileManager.default.fileExists(atPath: $0.path) })
        // The window as it was left; the config's start only without a session.
        let store = SessionStore(file: SessionStore.standardFile())
        let saved = store.load()
        let browser = saved?.browser
            ?? Browser(start: config.start, twoPanes: config.twoPanes, showHidden: config.showHidden)
        // A folder that went since falls back to its nearest parent (spec
        // §9): looked for in `start`, off the main thread, so the window
        // opens at once whatever disk a tab was on.
        let model = AppModel(browser: browser, config: config, clock: ListClock(), live: true)
        model.split = SidebarLayout.clamped(split: saved?.split ?? 0.5)
        model.sidebarHidden = saved?.sidebarHidden ?? false
        model.store = store
        return model
    }

    /// A model that shows what it is given and reads nothing: for a render.
    static func fixed(
        browser: Browser, config: ExplorerConfig, clock: ListClock, colors: ThemeColors,
        entries: [Side: [Entry]], sizes: [URL: Int64], free: Int64, selected: [Side: Set<URL>],
        problems: [Side: (sentence: String, needsPermission: Bool)] = [:]
    ) -> AppModel {
        let model = AppModel(browser: browser, config: config, clock: clock, live: false)
        model.colors = colors
        model.sizes = sizes
        for (side, all) in entries {
            guard let tab = browser.tab(side) else { continue }
            let arranged = FolderListing.arranged(all, sort: tab.sort, showHidden: browser.showHidden, sizes: sizes)
            model.listings[side] = Listing(
                folder: tab.folder, all: all, shown: arranged.shown, rows: arranged.rows,
                problem: problems[side]?.sentence, needsPermission: problems[side]?.needsPermission ?? false,
                free: free, revision: 1)
            model.selections[tab.id] = selected[side] ?? []
        }
        model.revision = 1
        return model
    }

    private init(browser: Browser, config: ExplorerConfig, clock: ListClock, live: Bool) {
        self.browser = browser
        self.config = config
        self.clock = clock
        self.live = live
        sizeQueue.onSize = { [weak self] url, size in self?.measured(url, size) }
        sizeQueue.onAskAgain = { [weak self] in self?.wantSizes() }
    }

    /// Reads the folders, and starts following them and the theme.
    func start() {
        guard live else { return }
        sync()
        followTheme()
        followVolumes()
        // The panes' own folders say so when they are read; this finds the
        // tabs not showing whose folders went since the session was saved.
        repairGoneFolders()
    }

    // MARK: Changing the browser

    /// Every change to the panes, tabs and folders goes through here: the
    /// panes then read what they newly show.
    func change(_ body: (inout Browser) -> Void) {
        var next = browser
        body(&next)
        guard next != browser else { return }
        let was = browser
        browser = next
        // Another folder, tab or pane has the keys now: letters typed for
        // the last one are not a name's start here, and a path field open
        // over it would say a folder that is no longer the one below it.
        if was.active != next.active || was.activeTab.id != next.activeTab.id
            || was.activeTab.folder != next.activeTab.folder
        {
            typeJump.reset()
            if pathField != nil {
                pathField = nil
                listFocus += 1
            }
        }
        sync()
    }

    /// Brings the listings in line with the browser: a pane whose tab or
    /// folder changed reads its folder; a pane that went gives up its rows.
    private func sync() {
        let tabs = Set(browser.panes.flatMap(\.tabs).map(\.id))
        if selections.keys.contains(where: { !tabs.contains($0) }) {
            selections = selections.filter { tabs.contains($0.key) }
        }
        guard live else { return }
        let before = listings
        var changed: [Side] = []
        for side in [Side.left, .right] {
            guard let tab = browser.tab(side) else {
                if shownKeys[side] != nil {
                    shownKeys[side] = nil
                    listings[side] = nil
                    loads[side] = (loads[side] ?? 0) + 1
                    watchers[side]?.watcher.stop()
                    watchers[side] = nil
                }
                continue
            }
            let path = tab.folder.standardizedFileURL.path
            let key = tab.id.uuidString + path
            guard shownKeys[side] != key else { continue }
            shownKeys[side] = key
            changed.append(side)
            // Rows of this folder that a pane already has are shown at once
            // (the other pane's, or this pane's other tab's), in this tab's order.
            if let known = before.values.first(where: { $0.folder.standardizedFileURL.path == path }) {
                revision += 1
                var listing = known
                listing.revision = revision
                listings[side] = listing
                arrange(side)
            }
        }
        guard !changed.isEmpty else { return }
        // The walks on their way for a folder just left give their slots
        // back; those for what a pane still shows go on.
        sizeQueue.keep(Set(wantedSizes()))
        for side in changed { load(side) }
    }

    // MARK: What the views read

    /// The sides that have a pane, left first.
    var sides: [Side] { browser.panes.count == 2 ? [.left, .right] : [.left] }

    /// The pane's rows: sorted, and without the hidden items unless they are shown.
    func entries(for side: Side) -> [Entry] { listings[side]?.shown ?? [] }

    func listing(for side: Side) -> Listing? { listings[side] }

    func selection(for side: Side) -> Set<URL> {
        browser.tab(side).flatMap { selections[$0.id] } ?? []
    }

    /// The left of the pane's status bar: "212 items", "3 of 212 selected · 48.2 MB".
    /// Worked out from the selection (never by walking the folder), and
    /// only when the rows, the selection or the sizes changed.
    func status(for side: Side) -> String {
        guard let listing = listings[side] else { return "" }
        if listing.problem != nil { return listing.needsPermission ? "No access" : "" }
        // The tab too: another tab of the pane has another selection.
        let tab = browser.tab(side)?.id
        if let kept = statuses[side], kept.tab == tab, kept.revision == listing.revision,
            kept.selection == selectionVersion, kept.sizes == sizesVersion
        {
            return kept.text
        }
        var count = 0
        var bytes: Int64? = 0
        for url in selection(for: side) {
            guard let row = listing.rows[url] else { continue }
            count += 1
            let entry = listing.shown[row]
            if let total = bytes, let size = entry.size ?? sizes[url] { bytes = total + size } else { bytes = nil }
        }
        let text = GroveExplorerCore.StatusText.items(
            total: listing.shown.count, selected: count, selectedBytes: bytes, filteredFrom: nil)
        statuses[side] = (tab, listing.revision, selectionVersion, sizesVersion, text)
        return text
    }

    /// The Size column's words: a file's size; a folder's or a package's
    /// total, "···" until it is known; "--" for what has none.
    func sizeText(_ entry: Entry) -> String {
        if let size = entry.size ?? sizes[entry.url] { return Formatting.size(size) }
        switch entry.kind {
        case .folder, .package: return "···"
        case .file, .symlink, .alias, .volume: return "--"
        }
    }

    func dateText(_ entry: Entry, short: Bool) -> String {
        guard let modified = entry.modified else { return "--" }
        return Formatting.date(modified, now: clock.now(), calendar: clock.calendar, locale: clock.locale, short: short)
    }

    // MARK: What the views ask for

    /// The pane's selection is now `urls`.
    func select(_ urls: Set<URL>, in side: Side) {
        guard let tab = browser.tab(side), selections[tab.id] ?? [] != urls else { return }
        selections[tab.id] = urls
    }

    /// The pane that has the keys.
    /// A click in the pane's list: the pane has the keys, and the click
    /// takes the keyboard back from the sidebar. (Not part of `activate`:
    /// the list also activates its pane when it is handed the keyboard,
    /// which ⌥⌘← does on its way to the sidebar.)
    func clicked(_ side: Side) {
        if sidebarCursor != nil { sidebarCursor = nil }
        activate(side)
    }

    func activate(_ side: Side) {
        guard browser.active != side, sides.contains(side) else { return }
        browser.active = side
        typeJump.reset()
    }

    /// Sorts the pane by `column`; by the column it is sorted by, the other way round.
    func sort(by column: SortColumn, in side: Side) {
        clicked(side)
        browser.setSort(column)
        arrange(side)
    }

    /// The list of `side` should scroll to `url`.
    func reveal(_ url: URL, in side: Side) { reveals[side] = url }

    /// The row the pane's list is to scroll to, once: the list asks after each update.
    func takeReveal(for side: Side) -> URL? { reveals.removeValue(forKey: side) }

    /// The path bar's parts for the pane's folder.
    func pathParts(for side: Side) -> [PathBar.Part] {
        guard let folder = browser.tab(side)?.folder else { return [] }
        if let known = partsCache[folder.path] { return known }
        let parts = PathBar.parts(of: folder, home: home, volumes: volumes.map(\.url))
        partsCache[folder.path] = parts
        return parts
    }

    /// The volumes changed: a path may start at another one now.
    func forgetPathParts() { partsCache = [:] }

    // MARK: Reading

    /// Reads the pane's folder and sorts it, off the main thread; the pane
    /// keeps what it shows until then. The folder is watched from here on.
    func load(_ side: Side) {
        guard let tab = browser.tab(side) else { return }
        let folder = tab.folder, sort = tab.sort, showHidden = browser.showHidden
        let sizes = sizes, sizesWere = sizesVersion
        let number = (loads[side] ?? 0) + 1
        loads[side] = number
        watch(folder, for: side)
        Task {
            let read = await Task.detached { FolderListing.read(folder, sort: sort, showHidden: showHidden, sizes: sizes) }.value
            // A later read of this pane answers instead.
            guard loads[side] == number else { return }
            // The folder went while it was shown, or back/forward landed on
            // one that is gone: its tabs move to the nearest folder that is
            // there (spec §13), and this pane reads that one instead.
            // Until the check returns the pane says the folder is gone.
            if read.gone { repairGoneFolders() }
            if let old = listings[side], old.folder.standardizedFileURL.path == folder.standardizedFileURL.path,
                old.all == read.all, old.problem == read.problem
            {
                // A watcher's tick that changed nothing the list shows: the
                // rows, the icons and the table stay as they are.
                if old.free != read.free { listings[side]?.free = read.free }
            } else {
                // An older sort of what was there before has nothing to say now.
                sorts[side] = (sorts[side] ?? 0) + 1
                revision += 1
                listings[side] = Listing(
                    folder: folder, all: read.all, shown: read.arranged.shown, rows: read.arranged.rows,
                    problem: read.problem, needsPermission: read.needsPermission, free: read.free, revision: revision)
                let present = Set(read.all.map(\.url))
                let chosen = selections[tab.id] ?? []
                if !chosen.isSubset(of: present) { selections[tab.id] = chosen.intersection(present) }
                IconCache.shared.forgetPaths()
            }
            if let name = selectWhenRead.removeValue(forKey: side),
                let entry = read.all.first(where: { $0.name == name })
            {
                selections[tab.id] = [entry.url]
                reveal(entry.url, in: side)
            }
            // The header was clicked, hidden items were switched or a total
            // arrived while this read was on its way: what it sorted by is
            // no longer what the pane asks for.
            if let now = browser.tab(side), now.sort != sort || browser.showHidden != showHidden
                || (now.sort.column == .size && sizesVersion != sizesWere)
            {
                arrange(side)
            }
            wantSizes()
        }
    }

    /// Sorts what the pane already has again (another column, a size that
    /// arrived), off the main thread: the list shows the old order until
    /// the new one is ready.
    func arrange(_ side: Side) {
        guard let tab = browser.tab(side), let listing = listings[side] else { return }
        let all = listing.all, sort = tab.sort, showHidden = browser.showHidden, sizes = sizes
        guard live else {
            show(FolderListing.arranged(all, sort: sort, showHidden: showHidden, sizes: sizes), in: side)
            return
        }
        let number = (sorts[side] ?? 0) + 1
        sorts[side] = number
        Task {
            let arranged = await Task.detached {
                FolderListing.arranged(all, sort: sort, showHidden: showHidden, sizes: sizes)
            }.value
            guard sorts[side] == number else { return }
            show(arranged, in: side)
        }
    }

    private func show(_ arranged: FolderListing.Arranged, in side: Side) {
        guard arranged.shown != listings[side]?.shown else { return }
        revision += 1
        listings[side]?.shown = arranged.shown
        listings[side]?.rows = arranged.rows
        listings[side]?.revision = revision
    }

    // MARK: Watching

    func watch(_ folder: URL, for side: Side) {
        let path = folder.standardizedFileURL.path
        guard watchers[side]?.path != path else { return }
        // A disk being ejected is let go of: the pane watches nothing (not
        // its last folder either) until `eject` watches again if the disk stays.
        guard !isBeingEjected(folder) else {
            watchers[side]?.watcher.stop()
            watchers[side] = nil
            return
        }
        watchers[side]?.watcher.stop()
        // The call comes on the watcher's queue: over to the main actor.
        let watcher = FolderWatcher(folder: folder) { [weak self] in
            Task { @MainActor in self?.changed(folder, in: side) }
        }
        watchers[side] = (path, watcher)
    }

    private func changed(_ folder: URL, in side: Side) {
        guard let tab = browser.tab(side), tab.folder.standardizedFileURL.path == folder.standardizedFileURL.path
        else { return }
        load(side)
        sizeQueue.changed(folder)
    }
}

extension Entry {
    /// Whether its size is a total the calculator works out (a package's
    /// comes from it like a folder's).
    var isMeasured: Bool { SizeWanted.isMeasured(self) }
}
