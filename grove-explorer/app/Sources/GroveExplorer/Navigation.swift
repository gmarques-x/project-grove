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
        let side = browser.active
        let chosen = selection(for: side)
        let entries = entries(for: side).filter { chosen.contains($0.url) }
        let folders = entries.filter(\.opensAsFolder)
        for entry in entries where !entry.opensAsFolder { open(entry) }
        for folder in folders { open(folder, inNewTab: folders.count > 1) }
    }

    func selectAll() {
        let side = browser.active
        select(Set(entries(for: side).map(\.url)), in: side)
    }

    func toggleHidden() {
        change { $0.showHidden.toggle() }
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
        change { $0.togglePanes() }
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

    /// Tab in the field: what it completes `typed` to; nil when nothing.
    func completePath(_ typed: String) -> String? {
        guard let field = pathField, let tab = browser.tab(field.side) else { return nil }
        return PathBar.completed(typed, relativeTo: tab.folder, home: home, folders: Disk.folders)
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
        switch PathBar.destination(of: target, kind: Disk.kind) {
        case .folder(let folder): show(folder, selecting: nil, in: browser.active, newTab: true)
        case .item(let file, in: let folder): show(folder, selecting: file.lastPathComponent, in: browser.active, newTab: true)
        case .missing: say("\(target.lastPathComponent) is not there", in: browser.active)
        }
        focusList()
    }

    // MARK: Folders that went

    /// Moves every tab whose folder is gone to its nearest folder that is
    /// there (an ejected disk's to Home), and says so in the panes it
    /// changed. True when a tab moved.
    @discardableResult
    func repairGoneFolders() -> Bool {
        let before = browser
        change { $0.repair(exists: Disk.isFolder, home: home) }
        guard browser != before else { return false }
        for side in sides {
            guard let old = before.tab(side), let new = browser.tab(side), old.id == new.id, old.folder != new.folder
            else { continue }
            say("\(old.folder.lastPathComponent) is no longer there: showing \(new.title)", in: side)
        }
        return true
    }

    /// A sentence in the pane's status bar, for a few seconds.
    func say(_ sentence: String, in side: Side) {
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
        Session(browser: browser, sidebarWidth: SidebarLayout.Mode.full.width, split: split, sidebarHidden: sidebarHidden)
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
