import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// What a pane shows of its tab's folder.
struct Listing {
    /// The folder these entries are of. For a moment after a navigation it
    /// is still the one before: the list shows the old rows until the new
    /// ones are read.
    var folder: URL
    /// As read, in no order, hidden items included.
    var all: [Entry] = []
    /// Sorted, and without the hidden items unless they are shown.
    var shown: [Entry] = []
    /// Why the folder couldn't be read; nil when it could.
    var problem: FolderReadError?
    /// Free room on the folder's volume, in bytes.
    var free: Int64?
    /// Changes whenever `shown` does: what the table reloads by.
    var revision = 0
}

/// "Now", and how dates are written: the user's in the app, fixed in a render.
struct ListClock: Sendable {
    var now: @Sendable () -> Date = { Date() }
    var calendar = Calendar.current
    var locale = Locale.current
}

/// The window's state and what keeps it current: the browser (panes, tabs,
/// folders, sort), each pane's listing, the selection, the folder sizes, the
/// config and the theme. Thin: what can be pure is in GroveExplorerCore.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var browser: Browser
    /// Folder and package totals known so far, by `Entry.url`.
    @Published private(set) var sizes: [URL: Int64] = [:]
    /// The current scheme's colours; they follow a scheme switch.
    @Published private(set) var colors = ThemeColors.fallback
    @Published private var listings: [Side: Listing] = [:]
    /// Each tab's selection, by the tab's id.
    @Published private var selections: [UUID: Set<URL>] = [:]

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

    private let calculator = SizeCalculator()
    /// Folders and packages whose total is wanted, the next one first.
    private var sizeQueue: [URL] = []
    private var sizesInFlight: Set<URL> = []
    /// Asked and answered with nothing (the walk was cancelled, or the folder
    /// can't be read): asked again after the next change.
    private var sizesUnanswered: Set<URL> = []
    private var sizeRetry: Task<Void, Never>?
    private static let sizesAtOnce = 4

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
            let shown = Self.arranged(all, sort: tab.sort, showHidden: browser.showHidden, sizes: sizes)
            model.listings[side] = Listing(folder: tab.folder, all: all, shown: shown, free: free, revision: 1)
            model.selections[tab.id] = selected[side] ?? []
        }
        return model
    }

    private init(browser: Browser, config: ExplorerConfig, clock: ListClock, live: Bool) {
        self.browser = browser
        self.config = config
        self.clock = clock
        self.live = live
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
    func status(for side: Side) -> String {
        let shown = entries(for: side)
        let chosen = selection(for: side)
        var bytes: Int64? = 0
        for entry in shown where chosen.contains(entry.url) {
            guard let total = bytes, let size = entry.size ?? sizes[entry.url] else {
                bytes = nil
                break
            }
            bytes = total + size
        }
        return GroveExplorerCore.StatusText.items(
            total: shown.count, selected: chosen.count, selectedBytes: bytes, filteredFrom: nil)
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
        load(side)
    }

    /// Reads the pane's folder and sorts it, off the main thread; the pane
    /// keeps what it shows until then. The folder is watched from here on.
    private func load(_ side: Side) {
        guard let tab = browser.tab(side) else { return }
        let folder = tab.folder, sort = tab.sort, showHidden = browser.showHidden, sizes = sizes
        let number = (loads[side] ?? 0) + 1
        loads[side] = number
        watch(folder, for: side)
        Task {
            let read = await Task.detached { Self.read(folder, sort: sort, showHidden: showHidden, sizes: sizes) }.value
            // A later read of this pane answers instead.
            guard loads[side] == number else { return }
            // An older sort of what was there before has nothing to say now.
            sorts[side] = (sorts[side] ?? 0) + 1
            revision += 1
            listings[side] = Listing(
                folder: folder, all: read.all, shown: read.shown, problem: read.problem, free: read.free,
                revision: revision)
            let present = Set(read.all.map(\.url))
            selections[tab.id] = (selections[tab.id] ?? []).intersection(present)
            IconCache.shared.forgetPaths()
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
            show(Self.arranged(all, sort: sort, showHidden: showHidden, sizes: sizes), in: side)
            return
        }
        let number = (sorts[side] ?? 0) + 1
        sorts[side] = number
        Task {
            let shown = await Task.detached {
                Self.arranged(all, sort: sort, showHidden: showHidden, sizes: sizes)
            }.value
            guard sorts[side] == number else { return }
            show(shown, in: side)
        }
    }

    private func show(_ shown: [Entry], in side: Side) {
        guard shown != listings[side]?.shown else { return }
        revision += 1
        listings[side]?.shown = shown
        listings[side]?.revision = revision
    }

    private struct Read: Sendable {
        var all: [Entry] = []
        var shown: [Entry] = []
        var problem: FolderReadError?
        var free: Int64?
    }

    private nonisolated static func read(
        _ folder: URL, sort: GroveExplorerCore.SortOrder, showHidden: Bool, sizes: [URL: Int64]
    ) -> Read {
        var read = Read()
        do {
            read.all = try FolderReader().read(folder)
        } catch {
            read.problem = error
        }
        read.shown = arranged(read.all, sort: sort, showHidden: showHidden, sizes: sizes)
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        read.free = values?.volumeAvailableCapacityForImportantUsage
        return read
    }

    private nonisolated static func arranged(
        _ all: [Entry], sort: GroveExplorerCore.SortOrder, showHidden: Bool, sizes: [URL: Int64]
    ) -> [Entry] {
        Sorting.sorted(showHidden ? all : all.filter { !$0.isHidden }, by: sort, folderSizes: sizes)
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
        // The sizes of the folders this one is in are no longer right. A
        // walk the calculator cancels for it answers nil: those are asked
        // again once the folder has been quiet for a second, or a busy
        // folder would never show a size.
        Task { await calculator.invalidate(folder) }
        sizeRetry?.cancel()
        sizeRetry = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            sizesUnanswered = []
            wantSizes()
        }
    }

    // MARK: Sizes

    /// Queues every folder and package the panes show whose total isn't
    /// known, in the order shown (so the top of the list first), and forgets
    /// the totals of what is no longer shown.
    private func wantSizes() {
        guard live else { return }
        let measured = sides.flatMap { entries(for: $0) }.filter(\.isMeasured).map(\.url)
        let shown = Set(measured)
        if sizes.keys.contains(where: { !shown.contains($0) }) { sizes = sizes.filter { shown.contains($0.key) } }
        sizeQueue = measured.filter { sizes[$0] == nil && !sizesInFlight.contains($0) && !sizesUnanswered.contains($0) }
        pumpSizes()
    }

    /// The rows in view: their totals come before the others'.
    func wantSizesFirst(for visible: [URL]) {
        let first = Set(visible)
        let (front, rest) = (sizeQueue.filter(first.contains), sizeQueue.filter { !first.contains($0) })
        guard !front.isEmpty else { return }
        sizeQueue = front + rest
        pumpSizes()
    }

    /// A few at a time; the calculator walks two of them at once.
    private func pumpSizes() {
        while sizesInFlight.count < Self.sizesAtOnce, !sizeQueue.isEmpty {
            let url = sizeQueue.removeFirst()
            sizesInFlight.insert(url)
            Task {
                let size = await calculator.size(of: url)
                sizesInFlight.remove(url)
                if let size {
                    sizes[url] = size
                    for side in sides where browser.tab(side)?.sort.column == .size { arrange(side) }
                } else {
                    sizesUnanswered.insert(url)
                }
                pumpSizes()
            }
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
    var isMeasured: Bool {
        switch kind {
        case .folder, .package: true
        case .file, .symlink, .alias, .volume: false
        }
    }
}
