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
    @Published var listings: [Side: Listing] = [:]
    /// Each tab's selection, by the tab's id.
    @Published var selections: [UUID: Set<URL>] = [:] {
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
    /// The place a drag of files is over (`DragDrop.swift`). A list marks
    /// its own row itself; the window is drawn again only for the marks
    /// SwiftUI draws (a pane's line, a sidebar row, a tab).
    var dropMark: DropMark? {
        willSet {
            guard newValue != dropMark else { return }
            if case .row? = newValue, dropMark == nil { return }
            if case .row? = dropMark, newValue.map({ if case .row = $0 { true } else { false } }) ?? true { return }
            objectWillChange.send()
        }
    }
    let drags = DragState()
    /// What a key needs of the views to open a menu (`KeyboardReach.swift`).
    let reach = KeyboardReach()
    /// The ⌘F filters (`FilterBar.swift`).
    @Published var filter = FilterState()

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
    var partsCache: [String: [PathBar.Part]] = [:]
    var revision = 0
    var loads: [Side: Int] = [:]
    /// One read of a pane's folder at a time (`ReadGate`).
    var reads: [Side: ReadGate] = [:]
    var sorts: [Side: Int] = [:]
    var watchers: [Side: (path: String, watcher: FolderWatcher)] = [:]
    /// The folders open in place in each pane's tab: their reads, watchers
    /// and peeks (`TreeModel.swift`).
    var trees: [Side: PaneTree] = [:]
    /// Counts the reads begun, of the panes' folders and of their open
    /// folders: a read begun before a folder was opened can't say it went.
    var readCount = 0
    let sizeQueue = SizeQueue()
    /// The file operations: the runner, the undo stack, what the views show of them.
    let work = FileWork()
    /// A sort by size waiting for more totals to arrive, per pane.
    var sizeSorts: [Side: Task<Void, Never>] = [:]
    /// The status bar's words, kept while nothing they are made of changed.
    var statuses: [Side: (tab: UUID?, revision: Int, selection: Int, sizes: Int, text: String)] = [:]

    /// What the window's red button calls (`Quitting.swift`).
    var closeButton: CloseButton?

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

    init(browser: Browser, config: ExplorerConfig, clock: ListClock, live: Bool) {
        self.browser = browser
        self.config = config
        self.clock = clock
        self.live = live
        sizeQueue.onSize = { [weak self] url, size in self?.measured(url, size) }
        sizeQueue.onAskAgain = { [weak self] in self?.wantSizes() }
        // The Size of a folder no total is coming for turns to "--".
        sizeQueue.onGivenUp = { [weak self] _ in
            self?.objectWillChange.send()
            self?.sizesVersion += 1
        }
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
        filtersFollow(was, next)
        // A tab that shows another folder now has nothing selected: what
        // was selected is in the folder it left, and no command is to act
        // on that from here (`PaneRows`).
        for tab in PaneRows.tabsThatMoved(from: was, to: next) where selections[tab] != nil {
            selections[tab] = nil
        }
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
                    reads[side] = nil
                    watchers[side]?.watcher.stop()
                    watchers[side] = nil
                    forgetOpenFolders(side)
                }
                continue
            }
            let path = tab.folder.standardizedFileURL.path
            let key = tab.id.uuidString + path
            guard shownKeys[side] != key else { continue }
            shownKeys[side] = key
            changed.append(side)
            // The reads, watchers and peeks of the folders open in the tab
            // the pane showed are that tab's: none of their answers is
            // taken from here on.
            forgetOpenFolders(side)
            // Rows of this folder that a pane already has (this pane's
            // other tab's, or the other pane's) are shown at once, as
            // `RowsState.reuse` says: as they are only when they are what
            // this tab asks for; never another tab's filter's pick without
            // its field, and never rows that are not there yet. Of several
            // listings, the one that needs least.
            let wanted = arrangement(for: tab)
            let known = before
                .filter { $0.value.isRead && $0.value.folder.standardizedFileURL.path == path }
                .map { (side: $0.key, listing: $0.value, reuse: $0.value.state.reuse(for: wanted, entries: $0.value.all.count)) }
                .min { ($0.reuse, $0.side == side ? 0 : 1) < ($1.reuse, $1.side == side ? 0 : 1) }
            // A sort still on its way was for the tab the pane showed:
            // given up. (Also the very one this tab waits for: it is begun
            // again below, which is simpler than telling the two apart.)
            sorts[side] = (sorts[side] ?? 0) + 1
            guard let known else {
                // No pane has this folder's rows: the pane is blank until
                // they are read. It never shows the rows of the folder it
                // left under the new folder's path bar, so what the user
                // sees and what a command acts on are one thing.
                revision += 1
                listings[side] = Listing(
                    folder: tab.folder, state: .awaiting(wanted), revision: revision, isRead: false)
                continue
            }
            revision += 1
            var listing = known.listing
            listing.revision = revision
            listing.state = known.listing.state.after(known.reuse, for: wanted)
            switch known.reuse {
            case .asItIs, .oldOrder, .keepWaiting:
                break
            case .arrangeNow:
                listing.take(FolderListing.arranged(listing.all, tree: .init(of: listing), by: wanted, sizes: sizes))
            case .blank:
                listing.take(FolderListing.Arranged())
            }
            listings[side] = listing
            keepVisibleSelection(in: side)
            // The tab's own rows are arranged off the main thread; the
            // state says meanwhile that they are not here yet.
            switch known.reuse {
            case .oldOrder, .blank, .keepWaiting: arrange(side)
            case .asItIs, .arrangeNow: break
            }
        }
        guard !changed.isEmpty else { return }
        // The walks on their way for a folder just left give their slots
        // back; those for what a pane still shows go on.
        sizeQueue.keep(Set(wantedSizes()))
        for side in changed {
            load(side)
            // The folders open in the tab are read beside its own.
            keepOpenFolders(side)
        }
    }

    // MARK: What the views read

    /// The sides that have a pane, left first.
    var sides: [Side] { browser.panes.count == 2 ? [.left, .right] : [.left] }

    /// The pane's rows' entries, in the list's order, at every depth (the
    /// tree's rows, `Tree.items`): sorted, without the hidden items unless
    /// they are shown, and nothing of an open folder whose read hasn't
    /// landed. None while the pane's listing is not of its tab's folder.
    func entries(for side: Side) -> [Entry] { listing(for: side)?.shownEntries ?? [] }

    /// What the pane lists of the folder its tab is on; nil while it has
    /// nothing of that folder (`PaneRows.areCurrent`). The one way to a
    /// pane's rows for every view and every command: rows of a folder the
    /// tab has left are never returned, so nothing is drawn of them and
    /// no command (⌘⌫, F5, ⌘A, Quick Look…) can act on them.
    func listing(for side: Side) -> Listing? {
        guard let listing = listings[side],
            PaneRows.areCurrent(listed: listing.folder, tabFolder: browser.tab(side)?.folder)
        else { return nil }
        return listing
    }

    func selection(for side: Side) -> Set<URL> {
        browser.tab(side).flatMap { selections[$0.id] } ?? []
    }

    // MARK: What the views ask for

    /// The pane's selection is now `urls`: those of them that are rows of
    /// its list (no command acts on a row the user can't see: one a filter
    /// hides, one inside a closed folder or one still being read), and
    /// nothing while the pane has not read its tab's folder.
    func select(_ urls: Set<URL>, in side: Side) {
        var urls = urls
        if let listing = listing(for: side), listing.isRead {
            urls = urls.filter { listing.rows[$0] != nil }
        } else {
            // Not read yet: a click that still found a row of the folder
            // before selects nothing here.
            urls = []
        }
        guard let tab = browser.tab(side), selections[tab.id] ?? [] != urls else { return }
        selections[tab.id] = urls
    }

    /// What the tab's rows are to be arranged by: its folder and sort, its
    /// own filter, the window's hidden-items switch and the folders it has
    /// open in place.
    func arrangement(for tab: GroveExplorerCore.Tab) -> Arrangement {
        Arrangement(
            folder: tab.folder, sort: tab.sort, filter: filter.tabs[tab.id]?.text ?? "", showHidden: browser.showHidden,
            open: tab.open, closedUnderFilter: filter.tabs[tab.id]?.closed ?? [])
    }

    /// The rows changed: what is no row now (a filter hides it, its folder
    /// closed or went, it went itself) is selected no more. Not while the
    /// pane awaits its rows: it has none to tell by.
    func keepVisibleSelection(in side: Side) {
        guard let tab = browser.tab(side), let listing = listing(for: side), !listing.state.isAwaitingRows,
            let chosen = selections[tab.id], !chosen.isEmpty
        else { return }
        let kept = chosen.filter { listing.rows[$0] != nil }
        if kept != chosen { selections[tab.id] = kept }
    }

    /// A click in the pane's list: the pane has the keys, and the click
    /// takes the keyboard back from the sidebar. (Not part of `activate`:
    /// the list also activates its pane when it is handed the keyboard,
    /// which ⌥⌘← does on its way to the sidebar.)
    func clicked(_ side: Side) {
        if sidebarCursor != nil { sidebarCursor = nil }
        activate(side)
    }

    /// The pane that has the keys is `side` from now on.
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

}

extension Entry {
    /// Whether its size is a total the calculator works out (a package's
    /// comes from it like a folder's).
    var isMeasured: Bool { SizeWanted.isMeasured(self) }
}
