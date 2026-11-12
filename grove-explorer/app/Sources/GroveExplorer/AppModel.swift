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
    @Published private(set) var browser: Browser
    /// Folder and package totals known so far, by `Entry.url`.
    @Published private(set) var sizes: [URL: Int64] = [:] {
        didSet { sizesVersion += 1 }
    }
    /// The current scheme's colours; they follow a scheme switch.
    @Published private(set) var colors = ThemeColors.fallback
    @Published private var listings: [Side: Listing] = [:]
    /// Each tab's selection, by the tab's id.
    @Published private var selections: [UUID: Set<URL>] = [:] {
        didSet { selectionVersion += 1 }
    }
    /// Change with `sizes` and with the selections: what the list and the
    /// status bar compare instead of the collections themselves.
    private(set) var sizesVersion = 0
    private(set) var selectionVersion = 0

    let config: ExplorerConfig
    let clock: ListClock
    /// A render only: the row drawn as under the pointer, per pane.
    var pointerStandIn: [Side: URL] = [:]

    /// False in a render: nothing is read, watched or measured.
    private let live: Bool
    private var revision = 0
    private var loads: [Side: Int] = [:]
    private var sorts: [Side: Int] = [:]
    private var watchers: [Side: (path: String, watcher: FolderWatcher)] = [:]
    private let sizeQueue = SizeQueue()
    /// A sort by size waiting for more totals to arrive, per pane.
    private var sizeSorts: [Side: Task<Void, Never>] = [:]
    /// The status bar's words, kept while nothing they are made of changed.
    private var statuses: [Side: (tab: UUID?, revision: Int, selection: Int, sizes: Int, text: String)] = [:]

    private var themeWatcher: FolderWatcher?
    private var themeState: Data?

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
        let browser = Browser(start: config.start, twoPanes: config.twoPanes, showHidden: config.showHidden)
        return AppModel(browser: browser, config: config, clock: ListClock(), live: true)
    }

    /// A model that shows what it is given and reads nothing: for a render.
    static func fixed(
        browser: Browser, config: ExplorerConfig, clock: ListClock, colors: ThemeColors,
        entries: [Side: [Entry]], sizes: [URL: Int64], free: Int64, selected: [Side: Set<URL>]
    ) -> AppModel {
        let model = AppModel(browser: browser, config: config, clock: clock, live: false)
        model.colors = colors
        model.sizes = sizes
        for (side, all) in entries {
            guard let tab = browser.tab(side) else { continue }
            let arranged = FolderListing.arranged(all, sort: tab.sort, showHidden: browser.showHidden, sizes: sizes)
            model.listings[side] = Listing(
                folder: tab.folder, all: all, shown: arranged.shown, rows: arranged.rows, free: free, revision: 1)
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
        for side in sides { load(side) }
        followTheme()
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

    /// Opens an entry of the active pane: a folder (a disk, a link to a
    /// folder) in this tab; a file in its app; a package as what it is.
    func open(_ entry: Entry) {
        switch entry.kind {
        case .folder, .volume, .symlink(toFolder: true):
            browser.go(to: entry.url)
            folderChanged(browser.active)
        case .file, .package, .alias, .symlink(toFolder: false):
            guard live else { return }
            NSWorkspace.shared.open(entry.url)
        }
    }

    /// The pane's selection is now `urls`.
    func select(_ urls: Set<URL>, in side: Side) {
        guard let tab = browser.tab(side), selections[tab.id] ?? [] != urls else { return }
        selections[tab.id] = urls
    }

    /// The pane that has the keys.
    func activate(_ side: Side) {
        guard browser.active != side, sides.contains(side) else { return }
        browser.active = side
    }

    /// Sorts the pane by `column`; by the column it is sorted by, the other way round.
    func sort(by column: SortColumn, in side: Side) {
        activate(side)
        browser.setSort(column)
        arrange(side)
    }

    func goBack() {
        if browser.goBack() { folderChanged(browser.active) }
    }

    func goForward() {
        if browser.goForward() { folderChanged(browser.active) }
    }

    // MARK: Reading

    private func folderChanged(_ side: Side) {
        guard live else { return }
        // The walks on their way for the folder just left give their slots
        // back; those for what the other pane shows go on.
        sizeQueue.keep(Set(wantedSizes()))
        load(side)
    }

    /// Reads the pane's folder and sorts it, off the main thread; the pane
    /// keeps what it shows until then. The folder is watched from here on.
    private func load(_ side: Side) {
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
                    problem: read.problem, free: read.free, revision: revision)
                let present = Set(read.all.map(\.url))
                let chosen = selections[tab.id] ?? []
                if !chosen.isSubset(of: present) { selections[tab.id] = chosen.intersection(present) }
                IconCache.shared.forgetPaths()
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
    private func arrange(_ side: Side) {
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

    private func watch(_ folder: URL, for side: Side) {
        let path = folder.standardizedFileURL.path
        guard watchers[side]?.path != path else { return }
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

    // MARK: Sizes

    /// Asks for the total of every folder and package the panes show whose
    /// total isn't known, in the order shown (so the top of the list first),
    /// and forgets the totals of what is no longer shown.
    private func wantSizes() {
        guard live else { return }
        // Totals are kept for every row on screen, the rows of a folder a
        // pane is just leaving included (they show until the new read lands).
        let shown = Set(sides.flatMap { entries(for: $0) }.map(\.url))
        if sizes.keys.contains(where: { !shown.contains($0) }) { sizes = sizes.filter { shown.contains($0.key) } }
        sizeQueue.want(wantedSizes().filter { sizes[$0] == nil })
    }

    /// The folders and packages whose totals are wanted: the rows of each
    /// pane that shows the folder its tab is on. A pane between two folders
    /// (navigated, the new one not yet read) wants none of its old rows.
    private func wantedSizes() -> [URL] {
        SizeWanted.urls(in: sides.compactMap { side in
            browser.tab(side).map {
                SizeWanted.Pane(tabFolder: $0.folder, listedFolder: listings[side]?.folder, shown: entries(for: side))
            }
        })
    }

    /// The rows in view: their totals come before the others'.
    func wantSizesFirst(for visible: [URL]) {
        sizeQueue.first(visible)
    }

    private func measured(_ url: URL, _ size: Int64) {
        sizes[url] = size
        for side in sides where browser.tab(side)?.sort.column == .size { arrangeSoon(side) }
    }

    /// Sorted by size, totals arrive one after the other: one sort once
    /// they have paused, not one for each.
    private func arrangeSoon(_ side: Side) {
        sizeSorts[side]?.cancel()
        sizeSorts[side] = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            arrange(side)
        }
    }

    // MARK: Theme

    /// The scheme's colours now, and again whenever grove-themes' state file
    /// changes (its folder is what can be watched).
    private func followTheme() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let state = StatePath.url(environment: environment, home: home)
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/bin/grove-themes")
        let themes = GroveThemesClient(runner: ProcessRunner(path: cli))
        let refresh: @MainActor (AppModel) -> Void = { model in
            // Other files change in that folder too: only the scheme's own counts.
            let now = try? Data(contentsOf: state)
            guard model.themeWatcher == nil || now != model.themeState else { return }
            model.themeState = now
            Task {
                guard let list = try? await themes.list() else { return }
                model.colors = list.palettes[list.current].flatMap(ThemeColors.init(palette:)) ?? .fallback
            }
        }
        refresh(self)
        themeWatcher = FolderWatcher(folder: state.deletingLastPathComponent()) { [weak self] in
            Task { @MainActor in
                if let self { refresh(self) }
            }
        }
    }
}

extension Entry {
    /// Whether its size is a total the calculator works out (a package's
    /// comes from it like a folder's).
    var isMeasured: Bool { SizeWanted.isMeasured(self) }
}
