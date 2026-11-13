import AppKit
import GroveExplorerCore
import GroveThemesCore

/// ⌘L's field in a pane's path bar.
struct PathFieldState: Equatable {
    let side: Side
    /// What the field says when it opens: the pane's folder.
    let text: String
    /// Return was pressed on a path that isn't there: the field is red.
    var missing = false
}

/// What is on the disk at a URL: the model's looks at it, in one place.
enum Disk {
    static func kind(_ url: URL) -> PathBar.ItemKind? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return nil }
        return isFolder.boolValue ? .folder : .file
    }

    static func isFolder(_ url: URL) -> Bool { kind(url) == .folder }

    /// The cloud providers' folders in `~/Library/CloudStorage`, as the
    /// sidebar lists them; nil while that folder isn't there. Only the
    /// names are read, not what is in a provider's folder: one not yet
    /// readable still has its row.
    static func cloudProviders(home: URL) -> [FolderName.CloudPlace]? {
        let storage = home.appendingPathComponent(FolderName.cloudStorage, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: storage.path) else { return nil }
        let folders = names.filter { isFolder(storage.appendingPathComponent($0, isDirectory: true)) }
        return FolderName.providers(in: folders, home: home)
    }

    /// For each of `folders` and, where it is gone, each folder above it up
    /// to the first that is there: whether it exists, by path. What
    /// `Browser.repair` asks, answered in one go off the main thread.
    static func existence(of folders: [URL]) -> [String: Bool] {
        var known: [String: Bool] = [:]
        for folder in folders {
            var folder = folder
            for _ in folder.pathComponents {
                if known[folder.path] == nil { known[folder.path] = isFolder(folder) }
                if known[folder.path] == true { break }
                folder = folder.deletingLastPathComponent()
            }
        }
        return known
    }

    /// The names of the folders in `folder`, for the path field's Tab.
    static func folders(in folder: URL) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent).sorted()
    }
}

/// Where the commands lead: folders, tabs, panes, the path field. Each is a
/// change to the browser; the panes follow it (`AppModel.change`).
extension AppModel {
    // MARK: Folders

    /// Shows `folder` in the active pane's tab.
    func go(to folder: URL) {
        change { $0.go(to: folder) }
    }

    func goBack() { change { $0.goBack() } }
    func goForward() { change { $0.goForward() } }
    func goUp() { change { $0.goUp() } }

    var canGoUp: Bool {
        var copy = browser
        return copy.goUp()
    }

    /// Opens an entry of the active pane: a folder (a disk, a link to a
    /// folder) in this tab, or in a new one; a file in its app; a package
    /// as what it is.
    func open(_ entry: Entry, inNewTab: Bool = false) {
        switch entry.kind {
        case .folder, .volume, .symlink(toFolder: true):
            if inNewTab { change { $0.newTab(folder: entry.url) } } else { go(to: entry.url) }
        case .file, .package, .alias, .symlink(toFolder: false):
            guard live else { return }
            NSWorkspace.shared.open(entry.url)
        }
    }

    /// ⌘O, ⌘↓: opens what is selected in the active pane, in the list's
    /// order. One folder opens in this tab; of several, each in a tab of its own.
    func openSelection() {
        let entries = selectedRows(in: browser.active)
        let folders = entries.filter(\.opensAsFolder)
        for entry in entries where !entry.opensAsFolder { open(entry) }
        for folder in folders { open(folder, inNewTab: folders.count > 1) }
    }

    /// ⌘A: every row that shows; under a filter the matches, not the
    /// folders kept as context (`Tree.selectAll`).
    func selectAll() {
        let side = browser.active
        select(Set(Tree.selectAll(in: listing(for: side)?.items ?? [])), in: side)
    }

    func toggleHidden() {
        change { $0.showHidden.toggle() }
        // A folder of hidden items only has something to show now, or no longer.
        forgetAllPeeks()
        for side in sides { arrange(side) }
    }

    // MARK: Tabs and panes

    func newTab() { change { $0.newTab() } }
    func closeTab() { change { $0.closeTab() } }
    func nextTab() { change { $0.nextTab() } }
    func previousTab() { change { $0.previousTab() } }

    /// Shows the tab at `index` of the active pane (⌘1…⌘9), or of `side` (a click on it).
    func showTab(_ index: Int, in side: Side? = nil) {
        change {
            if let side, $0.panes.indices.contains(side.rawValue) { $0.active = side }
            $0.selectTab(index)
        }
        focusList()
    }

    /// A tab's own close button.
    func closeTab(_ index: Int, in side: Side) {
        change { $0.closeTab(index, in: side) }
    }

    /// The "+" of a pane's tab strip: a tab on the folder showing there.
    func newTab(in side: Side) {
        change {
            if $0.panes.indices.contains(side.rawValue) { $0.active = side }
            $0.newTab()
        }
        focusList()
    }

    /// ⌘\ and the header's switch.
    func togglePanes() {
        // Two panes to one: the active pane stays, as the left.
        let kept = browser.active, closes = sides.count == 2
        change { $0.togglePanes() }
        if closes { statusFollows(closed: kept.other, kept: kept) }
        closePathField()
        focusList()
    }

    func showPanes(_ count: Int) {
        if browser.panes.count != count { togglePanes() }
    }

    /// Tab: the keys go to the other pane, which opens when there is one.
    func switchPane() {
        change { $0.switchPane() }
        closePathField()
        focusList()
    }

    /// The active pane's list should have the keyboard.
    func focusList() {
        sidebarCursor = nil
        listFocus += 1
    }

    // MARK: Typing a name

    /// Letters typed in a list: the first name that starts with them is
    /// selected; a second's pause starts again (spec §6).
    func typed(_ characters: String, in side: Side) {
        let prefix = typeJump.typed(characters, at: Date())
        let entries = entries(for: side)
        guard let index = Filter.jumpIndex(in: entries, typed: prefix) else { return }
        select([entries[index].url], in: side)
        reveal(entries[index].url, in: side)
    }

    /// Whether letters are being typed right now: a space then belongs to the name.
    var isTypingAName: Bool { typeJump.isUnderWay(at: Date()) }

    // MARK: The path field

    /// ⌘L, ⌘⇧G: the active pane's path bar becomes a field on its folder.
    func beginPathField() {
        sidebarCursor = nil
        pathField = PathFieldState(side: browser.active, text: PathBar.text(for: browser.activeTab.folder, home: home))
    }

    /// Escape, or the field lost the keyboard.
    func cancelPathField() {
        guard pathField != nil else { return }
        pathField = nil
        focusList()
    }

    private func closePathField() {
        if pathField != nil { pathField = nil }
    }

    /// The field's text changed: it is no longer the path that wasn't there.
    func pathFieldEdited() {
        if pathField?.missing == true { pathField?.missing = false }
    }

    /// Return: goes to the folder typed, or to a file's folder with the file
    /// selected. A path that isn't there marks the field red and stays.
    func commitPathField(_ typed: String) {
        guard let field = pathField, let tab = browser.tab(field.side) else { return }
        let url = PathBar.resolve(typed, relativeTo: tab.folder, home: home)
        // One stat on the main thread, for a path the user just typed. Left
        // so for now: on an unreachable network volume it waits for the answer.
        switch PathBar.destination(of: url, kind: Disk.kind) {
        case .missing:
            pathField?.missing = true
        case .folder(let folder):
            pathField = nil
            show(folder, selecting: nil, in: field.side, newTab: false)
            focusList()
        case .item(let file, in: let folder):
            pathField = nil
            show(folder, selecting: file.lastPathComponent, in: field.side, newTab: false)
            focusList()
        }
    }

    /// Tab in the field: `then` gets what `typed` completes to (nil when
    /// nothing). The folder is listed off the main thread; the caller
    /// drops an answer that comes after the text changed.
    func completePath(_ typed: String, then: @escaping @MainActor (String?) -> Void) {
        guard let field = pathField, let tab = browser.tab(field.side) else { return }
        let folder = tab.folder, home = home
        Task {
            let completed = await Task.detached {
                PathBar.completed(typed, relativeTo: folder, home: home, folders: { Disk.folders(in: $0) })
            }.value
            then(completed)
        }
    }

    /// Shows `folder` in the pane, and selects `name` there once it is read.
    private func show(_ folder: URL, selecting name: String?, in side: Side, newTab: Bool) {
        change {
            if $0.panes.indices.contains(side.rawValue) { $0.active = side }
            if newTab { $0.newTab(folder: folder) } else { $0.go(to: folder) }
        }
        guard let name else { return }
        // Already showing that folder: nothing will be read, so select now.
        if let listing = listing(for: side), listing.folder.standardizedFileURL.path == folder.standardizedFileURL.path,
            let entry = listing.all.first(where: { $0.name == name })
        {
            select([entry.url], in: side)
            reveal(entry.url, in: side)
        } else {
            selectWhenRead[side] = name
        }
    }

    // MARK: Links

    /// `groveexplorer://open?path=…`: the folder in a new tab of the active
    /// pane; a file's folder, with the file selected. A path that isn't
    /// there is said in the status bar.
    func open(link: URL) {
        guard case .open(let target)? = ExplorerURL(link) else { return }
        // One stat on the main thread, as in `commitPathField`: left so for now.
        switch PathBar.destination(of: target, kind: Disk.kind) {
        case .folder(let folder): show(folder, selecting: nil, in: browser.active, newTab: true)
        case .item(let file, in: let folder): show(folder, selecting: file.lastPathComponent, in: browser.active, newTab: true)
        case .missing: say("\(FolderName.title(of: target, home: home)) is not there", in: browser.active)
        }
        focusList()
    }

    // MARK: Folders that went

    /// Moves every tab whose folder is gone to its nearest folder that is
    /// there (an ejected disk's to Home), and says so in the panes it
    /// changed. The disk is asked off the main thread (a tab may be on a
    /// volume that doesn't answer): the tabs move when the answer is back,
    /// and a tab that has moved on meanwhile is left alone.
    func repairGoneFolders() {
        guard live else { return }
        let folders = browser.panes.flatMap(\.tabs).map(\.folder)
        Task {
            let known = await Task.detached { Disk.existence(of: folders) }.value
            let before = browser
            // A folder not asked about (a tab that navigated since) counts as there.
            change { $0.repair(exists: { known[$0.path] ?? true }, home: home) }
            guard browser != before else { return }
            for side in sides {
                guard let old = before.tab(side), let new = browser.tab(side), old.id == new.id,
                    old.folder != new.folder
                else { continue }
                say("\(FolderName.title(of: old.folder, home: home)) is no longer there: showing \(new.title)", in: side)
            }
        }
    }

    /// The pane whose status bar says what was meant for `side`'s: its
    /// own, or the left's when that pane has closed since (⌘\ during a
    /// copy to it): what an operation has to say is always said somewhere.
    func teller(for side: Side) -> Side { sides.contains(side) ? side : .left }

    /// A sentence in the pane's status bar, for a few seconds.
    func say(_ sentence: String, in side: Side) {
        let side = teller(for: side)
        notices[side] = sentence
        noticeTimers[side]?.cancel()
        noticeTimers[side] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.notices[side] = nil
        }
    }

    /// The "needs permission" state's button (spec §6): Privacy & Security › Files and Folders.
    func openPrivacySettings() {
        guard live, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: The session

    var session: Session {
        Session(browser: browser, sidebarWidth: sidebarWidth, split: split, sidebarHidden: sidebarHidden)
    }

    /// Something the session keeps changed: saved once it has been still for a second.
    func sessionChanged() {
        guard live else { return }
        store?.saveSoon { [weak self] in self?.session }
    }

    /// At quit.
    func saveSession() {
        guard live else { return }
        store?.save(session)
    }
}

private extension Entry {
    /// Opens in a tab rather than in an app.
    var opensAsFolder: Bool {
        switch kind {
        case .folder, .volume, .symlink(toFolder: true): true
        case .file, .package, .alias, .symlink(toFolder: false): false
        }
    }
}
