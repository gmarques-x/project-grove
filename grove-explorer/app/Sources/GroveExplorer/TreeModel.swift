import AppKit
import GroveExplorerCore

/// What a pane does for the folders open in place in the tab it shows
/// (spec §16): each one's read, its watcher, the looks into folders that
/// give them their chevrons. All of it is for one tab on one folder
/// (`key`): when the pane shows another, it is let go of whole.
struct PaneTree {
    /// The tab's id and the folder's path this is for.
    var key: String?
    /// One read of each open folder at a time (`ReadGate`), by its path.
    var reads: [String: OpenRead] = [:]

    /// The read of one open folder: a later one answers instead (`number`).
    struct OpenRead {
        var gate = ReadGate()
        var number = 0
    }

    /// When each folder was opened in the app (or renamed into), by
    /// `AppModel.readCount`: a read of its parent begun before then can't
    /// say it went.
    var openedAt: [String: Int] = [:]

    /// Reads landing one after the other (⌥→ opens many folders at once)
    /// make the rows again once for the lot: one arrange now, the next
    /// when `arrangeHeld` is over, if one is `arrangeOwed` by then.
    var arrangeHeld = false
    var arrangeOwed = false

    /// One watcher per open folder that shows, up to
    /// `WatchPlan.openFolderLimit`, by its path.
    var watchers: [String: FolderWatcher] = [:]
    /// The open folders past that limit: read again when the tab's own
    /// folder changes or their rows come into view, and those of them in
    /// view at the last look.
    var beyond: Set<String> = []
    var beyondInView: Set<String> = []
    /// Folders past the limit being read again: if one changed, the status
    /// bar says it wasn't watched.
    var refreshing: Set<String> = []

    /// Every watcher stops: the pane shows another tab or folder, or the
    /// disk is being ejected.
    func stopWatching() {
        for watcher in watchers.values { watcher.stop() }
    }
}

extension URL {
    /// The URL's path, standardized: what two spellings of one folder share.
    var pathKey: String { standardizedFileURL.path }
}

extension AppModel {
    // MARK: The open folders of a pane's tab

    /// The tab's open folders that show (or will, once a parent still
    /// being read lands): those read and watched (`Tree.reachable`).
    func reachableOpenFolders(in side: Side) -> Set<URL> {
        guard let tab = browser.tab(side), let listing = listing(for: side) else { return [] }
        return Tree.reachable(open: tab.open, root: tab.folder, children: listing.knownListings)
    }

    /// The pane no longer shows the tab and folder its open folders were
    /// read for: their reads' answers are dropped and nothing of them is
    /// looked at again.
    func forgetOpenFolders(_ side: Side) {
        trees[side]?.stopWatching()
        trees[side] = nil
    }

    /// Brings the open folders' reads in line with the tab: each open
    /// folder that shows is read (once), and the listings of those that no
    /// longer show (closed, or in a folder that was closed) are let go of.
    func keepOpenFolders(_ side: Side) {
        guard live, let tab = browser.tab(side), let listing = listing(for: side) else { return }
        let key = tab.id.uuidString + tab.folder.pathKey
        if trees[side]?.key != key { trees[side] = PaneTree(key: key) }
        let reachable = Tree.reachable(open: tab.open, root: tab.folder, children: listing.knownListings)
        let paths = Set(reachable.map(\.pathKey))
        // A listing nobody shows is not watched: it would only go stale.
        let listed = Set(listing.children.keys.map(\.pathKey))
        if !listed.isSubset(of: paths) {
            listings[side]?.children = listing.children.filter { paths.contains($0.key.pathKey) }
            listings[side]?.treeVersion += 1
        }
        let open = Set(tab.open.map(\.pathKey))
        if var tree = trees[side] {
            tree.reads = tree.reads.filter { paths.contains($0.key) }
            tree.openedAt = tree.openedAt.filter { open.contains($0.key) }
            trees[side] = tree
        }
        for folder in reachable where !listed.contains(folder.pathKey) && trees[side]?.reads[folder.pathKey] == nil {
            loadOpenFolder(folder, in: side)
        }
        watchOpenFolders(reachable, in: side)
    }

    // MARK: Watching them

    /// One watcher per open folder that shows, the 64 nearest the top of
    /// the list (`WatchPlan.openFolders`); none on a disk being ejected.
    func watchOpenFolders(_ reachable: Set<URL>, in side: Side) {
        guard live, let tree = trees[side], let key = tree.key, let listing = listing(for: side) else { return }
        let plan = WatchPlan.openFolders(reachable.filter { !isBeingEjected($0) }, rows: listing.items)
        let wanted = Dictionary(plan.watched.map { ($0.pathKey, $0) }, uniquingKeysWith: { first, _ in first })
        var watchers = tree.watchers
        for (path, watcher) in watchers where wanted[path] == nil {
            watcher.stop()
            watchers[path] = nil
        }
        for (path, folder) in wanted where watchers[path] == nil {
            // The call comes on the watcher's queue: over to the main actor.
            watchers[path] = FolderWatcher(folder: folder) { [weak self] in
                Task { @MainActor in self?.openFolderChanged(folder, key: key, in: side) }
            }
        }
        trees[side]?.watchers = watchers
        trees[side]?.beyond = Set(plan.beyond.map(\.pathKey))
    }

    /// An open folder's watcher says it changed: it is read again (not
    /// while a read of it is in flight: that one's landing reads again,
    /// once), and its total and those of the open folders it is in are
    /// worked out again (they are rows of the list).
    private func openFolderChanged(_ folder: URL, key: String, in side: Side) {
        guard trees[side]?.key == key, trees[side]?.watchers[folder.pathKey] != nil else { return }
        let path = folder.pathKey
        var gate = trees[side]?.reads[path]?.gate ?? ReadGate()
        let readNow = gate.changed(folder)
        if trees[side]?.reads[path] != nil { trees[side]?.reads[path]?.gate = gate }
        if readNow { loadOpenFolder(folder, in: side) }
        sizeQueue.changed(folder)
        let stale = AfterOperation.staleTotals(among: Array(sizes.keys), touched: [folder])
        if !stale.isEmpty {
            var kept = sizes
            for url in stale { kept[url] = nil }
            sizes = kept
            wantSizes()
        }
    }

    /// The tab's own folder changed (it was read again): the open folders
    /// past the watchers' limit are read again too, as nothing tells when
    /// they change.
    func refreshUnwatchedOpenFolders(in side: Side) {
        guard let tree = trees[side], !tree.beyond.isEmpty else { return }
        refresh(tree.beyond, in: side)
    }

    /// Rows came into view: an open folder past the watchers' limit whose
    /// row (or a row inside it) is among them, and wasn't at the last look,
    /// is read again.
    func openFoldersInView(_ visible: [URL], in side: Side) {
        guard let tree = trees[side], !tree.beyond.isEmpty || !tree.beyondInView.isEmpty else { return }
        var inView: Set<String> = []
        for url in visible {
            let path = url.pathKey
            if tree.beyond.contains(path) { inView.insert(path) }
            let parent = (path as NSString).deletingLastPathComponent
            if tree.beyond.contains(parent) { inView.insert(parent) }
        }
        trees[side]?.beyondInView = inView
        let new = inView.subtracting(tree.beyondInView)
        if !new.isEmpty { refresh(new, in: side) }
    }

    private func refresh(_ paths: Set<String>, in side: Side) {
        for folder in reachableOpenFolders(in: side) where paths.contains(folder.pathKey) {
            trees[side]?.refreshing.insert(folder.pathKey)
            loadOpenFolder(folder, in: side)
        }
    }

    /// Reads an open folder of the pane's tab, off the main thread. What
    /// comes back goes into the pane's listing only while the folder is
    /// still open and showing there, in that tab, on that folder
    /// (`PaneRows.isCurrent`); until then the folder shows its loading line
    /// and nothing beneath.
    func loadOpenFolder(_ folder: URL, in side: Side) {
        guard live, let tab = browser.tab(side), trees[side] != nil else { return }
        let path = folder.pathKey
        readCount += 1
        let begunAt = readCount
        var read = trees[side]?.reads[path] ?? PaneTree.OpenRead()
        read.number += 1
        read.gate.begin(folder)
        trees[side]?.reads[path] = read
        let number = read.number
        let asked = PaneRows.ChildRead(tab: tab.id, tabFolder: tab.folder, folder: folder)
        Task {
            let read = await Task.detached { FolderListing.entries(of: folder) }.value
            // A later read of it answers instead; or the pane let it go.
            guard trees[side]?.reads[path]?.number == number else { return }
            guard PaneRows.isCurrent(
                asked, tab: browser.tab(side), listed: listings[side]?.folder, open: reachableOpenFolders(in: side))
            else {
                trees[side]?.reads[path] = nil
                return
            }
            openFolderLanded(folder, read, begunAt: begunAt, in: side)
            // It changed while it was read: once more, now.
            if trees[side]?.reads[path]?.gate.landed(folder) == true { loadOpenFolder(folder, in: side) }
        }
    }

    /// An open folder's read landed, and is the pane's.
    private func openFolderLanded(_ folder: URL, _ read: FolderListing.Read, begunAt: Int, in side: Side) {
        guard let listing = listings[side] else { return }
        let name = folder.lastPathComponent
        if let problem = read.problem {
            // Not "being read" for ever: it closes, without a chevron, and
            // the status bar says why (a folder that went says nothing:
            // it simply isn't there).
            closeOpenFolders([folder], in: side, inside: read.gone, peek: false, now: false)
            if !read.gone { say("\(name) can't be opened: \(problem)", in: side) }
            return
        }
        let shows = browser.showHidden ? read.all : read.all.filter { !$0.isHidden }
        if shows.isEmpty {
            // Empty when opened: it closes again and loses its chevron.
            closeOpenFolders([folder], in: side, inside: false, peek: false, now: false)
            return
        }
        let wasRefresh = trees[side]?.refreshing.remove(folder.pathKey) != nil
        guard listing.childEntries(of: folder) != read.all else { return }
        // Past the watchers' limit and changed meanwhile: what showed of it
        // was out of date, and the user is told why.
        if wasRefresh, listing.childEntries(of: folder) != nil {
            say(
                "\(name) had changed: only the first \(WatchPlan.openFolderLimit) open folders are watched", in: side)
        }
        // One key per folder, however the open set spells it.
        var children = listing.children.filter { $0.key.pathKey != folder.pathKey }
        children[folder] = read.all
        listings[side]?.children = children
        listings[side]?.treeVersion += 1
        openFolderWasRead(folder, entries: read.all, begunAt: begunAt, in: side)
        arrangeTree(side)
        // What is open inside it shows now, and is read in turn.
        keepOpenFolders(side)
        arrived(in: side)
    }

    /// A fresh read of `folder` (the tab's own, or one open in it) found
    /// `entries`: the open folders in it that are no longer there close,
    /// with whatever was open inside them (`Tree.vanished`). Not one
    /// opened (or renamed into) after the read began: the read can't have
    /// seen it.
    func openFolderWasRead(_ folder: URL, entries: [Entry], begunAt: Int, in side: Side) {
        guard let tab = browser.tab(side), !tab.open.isEmpty else { return }
        let opened = trees[side]?.openedAt ?? [:]
        let asked = tab.open.filter { (opened[$0.pathKey] ?? 0) <= begunAt }
        let gone = Tree.vanished(in: folder, listing: entries, open: asked)
        guard !gone.isEmpty else { return }
        closeOpenFolders(gone, in: side, inside: true, peek: nil, now: false)
    }

    /// The rows made again after an open folder's read landed: at once,
    /// unless they were a moment ago; then once more when that moment is
    /// over, for every read that landed meanwhile.
    func arrangeTree(_ side: Side) {
        guard trees[side] != nil else { return arrange(side) }
        if trees[side]?.arrangeHeld == true {
            trees[side]?.arrangeOwed = true
            return
        }
        arrange(side)
        trees[side]?.arrangeHeld = true
        let key = trees[side]?.key
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            // Another tab or folder since: its own arranges are its own.
            guard trees[side]?.key == key else { return }
            trees[side]?.arrangeHeld = false
            if trees[side]?.arrangeOwed == true {
                trees[side]?.arrangeOwed = false
                arrangeTree(side)
            }
        }
    }

    // MARK: Changing what is open

    /// The tab showing on `side` has `open` open from now on; `opened` are
    /// those the app just opened (or renamed into). The rows are made
    /// again, and the folders that show now are read.
    func setOpenFolders(_ open: Set<URL>, opened: [URL] = [], in side: Side) {
        guard let tab = browser.tab(side), open != tab.open else { return }
        readCount += 1
        for folder in opened { trees[side]?.openedAt[folder.pathKey] = readCount }
        change { $0.setOpen(open, in: side) }
        arrange(side)
        keepOpenFolders(side)
    }

    /// Closes `folders` in the pane's tab: they leave the open set (with
    /// what is open inside them too when `inside`), their listings go, and
    /// so does what was selected inside them. `peek`: what is now known of
    /// each one's chevron (false: none), nil to keep what was. `now`: the
    /// user closed them, and sees the rows go at once; otherwise a read
    /// found them gone, among others perhaps (`arrangeTree`).
    func closeOpenFolders(_ folders: Set<URL>, in side: Side, inside: Bool, peek: Bool?, now: Bool) {
        guard let tab = browser.tab(side) else { return }
        let paths = folders.map(\.pathKey)
        func isClosed(_ url: URL) -> Bool {
            let path = url.pathKey
            return paths.contains { path == $0 || (inside && path.hasPrefix($0 + "/")) }
        }
        func isUnder(_ url: URL) -> Bool {
            let path = url.pathKey
            return paths.contains { path.hasPrefix($0 + "/") }
        }
        if var listing = listings[side], listing.folder.pathKey == tab.folder.pathKey {
            listing.children = listing.children.filter { !isClosed($0.key) && !isUnder($0.key) }
            if let peek {
                let closing = Set(paths)
                listing.peeks = listing.peeks.filter { !closing.contains($0.key.pathKey) }
                for folder in folders { listing.peeks[folder] = peek }
            }
            listing.treeVersion += 1
            listings[side] = listing
        }
        // Nothing inside a closed folder is a row: nothing there stays selected.
        if let chosen = selections[tab.id], chosen.contains(where: isUnder) {
            selections[tab.id] = chosen.filter { !isUnder($0) }
        }
        let open = tab.open.filter { !isClosed($0) }
        if open != tab.open {
            change { $0.setOpen(open, in: side) }
        }
        if now { arrange(side) } else { arrangeTree(side) }
        keepOpenFolders(side)
    }
}
