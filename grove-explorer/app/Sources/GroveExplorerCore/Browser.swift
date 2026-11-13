import Foundation

/// One tab: a folder, how it is sorted, where it has been, and which
/// folders it has open in place.
public struct Tab: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    /// As it was navigated to: a link stays a link, `/var/x` stays `/var/x`.
    public var folder: URL
    public var sort: SortOrder
    /// The folders before this one, the latest last.
    public var back: [URL]
    /// The folders gone back from, the next one last.
    public var forward: [URL]
    /// What is open in place in each folder the tab has shown with
    /// something open, the one touched longest ago first; at most
    /// `Browser.openFoldersLimit` folders, none with nothing open. One
    /// value, in order, so what is remembered and which is oldest can't
    /// disagree. Changed through `setOpen`.
    private var remembered: [Remembered]

    /// The folders open in one folder of the tab's.
    private struct Remembered: Equatable, Codable, Sendable {
        /// As the tab showed it.
        var folder: URL
        var open: Set<URL>
    }

    private enum CodingKeys: String, CodingKey {
        case id, folder, sort, back, forward
        case remembered = "openFolders"
    }

    public init(
        id: UUID = UUID(), folder: URL, sort: SortOrder = .byName,
        back: [URL] = [], forward: [URL] = []
    ) {
        self.id = id
        self.folder = folder
        self.sort = sort
        self.back = back
        self.forward = forward
        remembered = []
    }

    /// A session file written before folders opened in place has no
    /// `openFolders`: nothing is open.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folder = try container.decode(URL.self, forKey: .folder)
        sort = try container.decode(SortOrder.self, forKey: .sort)
        back = try container.decode([URL].self, forKey: .back)
        forward = try container.decode([URL].self, forKey: .forward)
        remembered = try container.decodeIfPresent([Remembered].self, forKey: .remembered) ?? []
    }

    /// The folders open in place, keyed by the tab folder they are open in
    /// (as the tab showed it). Spec §16: kept per folder visited, bounded.
    public var openFolders: [URL: Set<URL>] {
        Dictionary(remembered.map { ($0.folder, $0.open) }, uniquingKeysWith: { _, latest in latest })
    }

    /// The folders open in place in the folder the tab shows now, however
    /// that folder is spelled.
    public var open: Set<URL> {
        remembered.last { $0.folder.isSameFolder(as: folder) }?.open ?? []
    }

    /// Records `open` as what is open in the folder the tab shows now: it
    /// becomes the folder touched latest, and the one touched longest ago
    /// goes past `Browser.openFoldersLimit`. Nothing open is nothing to
    /// remember.
    public mutating func setOpen(_ open: Set<URL>) {
        remembered.removeAll { $0.folder.isSameFolder(as: folder) }
        guard !open.isEmpty else { return }
        remembered.append(Remembered(folder: folder, open: open))
        if remembered.count > Browser.openFoldersLimit {
            remembered.removeFirst(remembered.count - Browser.openFoldersLimit)
        }
    }

    /// Leaves out the open folders, and the folders they were open in,
    /// that `exists` says are gone.
    mutating func dropGoneOpenFolders(exists: (URL) -> Bool) {
        remembered = remembered.compactMap { entry in
            guard exists(entry.folder) else { return nil }
            let open = entry.open.filter(exists)
            return open.isEmpty ? nil : Remembered(folder: entry.folder, open: open)
        }
    }

    /// The folder's name; "Home" for the user's home folder.
    public var title: String {
        folder.isSameFolder(as: FileManager.default.homeDirectoryForCurrentUser)
            ? "Home" : folder.lastPathComponent
    }
}

/// One pane: its tabs, and which one shows. There is always at least one tab.
public struct Pane: Equatable, Codable, Sendable {
    public var tabs: [Tab]
    public var current: Int

    public init(tabs: [Tab], current: Int) {
        self.tabs = tabs
        self.current = current
    }
}

public enum Side: Int, Codable, Sendable {
    case left, right

    public var other: Side { self == .left ? .right : .left }
}

private extension Array where Element == URL {
    /// Adds a folder to a history, which keeps the latest
    /// `Browser.historyLimit`: the histories are saved with the session, and
    /// a tab used for weeks would otherwise carry every folder it ever showed.
    mutating func push(_ folder: URL) {
        append(folder)
        if count > Browser.historyLimit { removeFirst(count - Browser.historyLimit) }
    }
}

/// The window's state: one pane or two, their tabs, and which pane is active.
/// Every change is made to the active pane's current tab unless it says
/// otherwise. Nothing here reads the disk.
public struct Browser: Equatable, Codable, Sendable {
    /// One or two; with one, it is the left.
    public var panes: [Pane]
    public var active: Side
    public var showHidden: Bool

    /// How many folders a tab's `back` and `forward` each keep.
    public static let historyLimit = 100

    /// Of how many folders a tab remembers what was open in place (spec
    /// §16: "per folder visited, bounded"), as the histories are bounded.
    public static let openFoldersLimit = 20

    public init(start: URL, twoPanes: Bool, showHidden: Bool) {
        panes = (twoPanes ? [Side.left, .right] : [.left]).map { _ in
            Pane(tabs: [Tab(folder: start)], current: 0)
        }
        active = .left
        self.showHidden = showHidden
    }

    public var activeTab: Tab { pane.tabs[pane.current] }

    /// The tab showing on that side; nil when there is no pane there.
    public func tab(_ side: Side) -> Tab? {
        guard panes.indices.contains(side.rawValue) else { return nil }
        let pane = panes[side.rawValue]
        return pane.tabs[pane.current]
    }

    // MARK: Folders

    /// Shows `folder` in the active tab: the one it leaves goes on the
    /// history, and there is no longer anything to go forward to. Going to
    /// the folder already shown changes nothing.
    public mutating func go(to folder: URL) {
        guard !folder.isSameFolder(as: activeTab.folder) else { return }
        var tab = activeTab
        tab.back.push(tab.folder)
        tab.forward = []
        tab.folder = folder
        pane.tabs[pane.current] = tab
    }

    /// False when there is nothing to go back to.
    @discardableResult
    public mutating func goBack() -> Bool {
        var tab = activeTab
        guard let folder = tab.back.popLast() else { return false }
        tab.forward.push(tab.folder)
        tab.folder = folder
        pane.tabs[pane.current] = tab
        return true
    }

    /// False when there is nothing to go forward to.
    @discardableResult
    public mutating func goForward() -> Bool {
        var tab = activeTab
        guard let folder = tab.forward.popLast() else { return false }
        tab.back.push(tab.folder)
        tab.folder = folder
        pane.tabs[pane.current] = tab
        return true
    }

    /// To the folder that holds this one, as `go(to:)` does. False at a
    /// volume's root, where there is nothing above to show.
    @discardableResult
    public mutating func goUp() -> Bool {
        let folder = activeTab.folder
        guard !folder.isVolumeRoot else { return false }
        go(to: folder.deletingLastPathComponent())
        return true
    }

    // MARK: Tabs

    /// A tab after the current one, which becomes the current one: on
    /// `folder`, or on the folder showing when none is given. It takes the
    /// current tab's sort and starts without history.
    public mutating func newTab(folder: URL? = nil) {
        let tab = Tab(folder: folder ?? activeTab.folder, sort: activeTab.sort)
        pane.tabs.insert(tab, at: pane.current + 1)
        pane.current += 1
    }

    /// Closes the current tab; the one after it shows, or the one before
    /// when it was the last in the row. False when it is the pane's only tab,
    /// which doesn't close.
    @discardableResult
    public mutating func closeTab() -> Bool {
        guard pane.tabs.count > 1 else { return false }
        pane.tabs.remove(at: pane.current)
        pane.current = min(pane.current, pane.tabs.count - 1)
        return true
    }

    /// Closes the tab at `index` of the pane on `side`, whichever pane is
    /// active and whichever tab shows there (a tab's own close button). The
    /// tab showing stays the one showing, unless it is the one closed: then
    /// as `closeTab()`. False for a pane's only tab, and for a tab or a pane
    /// that isn't there.
    @discardableResult
    public mutating func closeTab(_ index: Int, in side: Side) -> Bool {
        guard panes.indices.contains(side.rawValue) else { return false }
        var pane = panes[side.rawValue]
        guard pane.tabs.count > 1, pane.tabs.indices.contains(index) else { return false }
        pane.tabs.remove(at: index)
        if index < pane.current { pane.current -= 1 }
        pane.current = min(pane.current, pane.tabs.count - 1)
        panes[side.rawValue] = pane
        return true
    }

    /// Shows the tab at `index`, counted from 0; nothing when there is none.
    public mutating func selectTab(_ index: Int) {
        guard pane.tabs.indices.contains(index) else { return }
        pane.current = index
    }

    /// The tab to the right; from the last, round to the first.
    public mutating func nextTab() {
        pane.current = (pane.current + 1) % pane.tabs.count
    }

    /// The tab to the left; from the first, round to the last.
    public mutating func previousTab() {
        pane.current = (pane.current + pane.tabs.count - 1) % pane.tabs.count
    }

    // MARK: Panes

    /// One pane to two: the new one opens at the right with one tab on the
    /// active tab's folder, and the left stays active. Two to one: the active
    /// pane stays, with its tabs.
    public mutating func togglePanes() {
        if panes.count == 1 {
            let tab = Tab(folder: activeTab.folder, sort: activeTab.sort)
            panes.append(Pane(tabs: [tab], current: 0))
        } else {
            panes = [pane]
            active = .left
        }
    }

    /// Makes the other pane the active one, opening it when there is one.
    public mutating func switchPane() {
        if panes.count == 1 { togglePanes() }
        active = active.other
    }

    // MARK: Sort

    /// Sorts the active tab by `column`, ascending; by the column it is
    /// already sorted by, the other way round.
    public mutating func setSort(_ column: SortColumn) {
        let sort = activeTab.sort
        pane.tabs[pane.current].sort = SortOrder(
            column: column, ascending: sort.column == column ? !sort.ascending : true)
    }

    // MARK: Folders open in place

    /// Records `open` as what the tab showing on `side` has open in its
    /// folder (`Tab.setOpen`), whichever pane is active. Nothing when there
    /// is no pane there.
    public mutating func setOpen(_ open: Set<URL>, in side: Side) {
        guard panes.indices.contains(side.rawValue) else { return }
        let current = panes[side.rawValue].current
        panes[side.rawValue].tabs[current].setOpen(open)
    }

    // MARK: Repair

    /// Moves every tab whose folder is gone to its nearest parent that
    /// exists. A tab on a volume that is gone (ejected) moves to `home`
    /// rather than to `/Volumes`, and so does one with nothing left above it.
    /// The histories are left as they are; the open folders that are gone,
    /// and what was open in a folder that is gone, are forgotten.
    public mutating func repair(exists: (URL) -> Bool, home: URL) {
        for pane in panes.indices {
            for tab in panes[pane].tabs.indices {
                panes[pane].tabs[tab].dropGoneOpenFolders(exists: exists)
                let folder = panes[pane].tabs[tab].folder
                guard !exists(folder) else { continue }
                panes[pane].tabs[tab].folder = Self.nearest(to: folder, exists: exists) ?? home
            }
        }
    }

    /// The closest folder above `folder` that exists and is on its volume.
    private static func nearest(to folder: URL, exists: (URL) -> Bool) -> URL? {
        var folder = folder
        // A path has no more parents than it has parts.
        for _ in folder.pathComponents {
            guard !folder.isVolumeRoot else { return nil }
            folder = folder.deletingLastPathComponent()
            if exists(folder) { return folder }
        }
        return nil
    }

    /// The active pane.
    private var pane: Pane {
        get { panes[active.rawValue] }
        set { panes[active.rawValue] = newValue }
    }
}

extension URL {
    /// Whether both are the same folder by path, however each was written
    /// (a trailing slash, `..`). Folders are kept as they were navigated to
    /// and only compared this way.
    func isSameFolder(as other: URL) -> Bool {
        standardizedPath == other.standardizedPath
    }

    /// The path `isSameFolder` compares: the same for a folder however it
    /// was written, so it can key a dictionary where the URL can't.
    var standardizedPath: String { standardizedFileURL.path }

    /// `/`, or a disk's folder in `/Volumes`: told from the path alone.
    var isVolumeRoot: Bool {
        let parts = standardizedFileURL.pathComponents
        return parts.count <= 1 || (parts.count == 3 && parts[1] == "Volumes")
    }
}
