import Foundation
import GroveThemesCore

// What the tray's dropdown shows and how its keys move (spec
// 2026-11-14-bar-tray-design): the visible rows, a "Hidden (n)" disclosure
// with the hidden rows under it, the row menu's choices. Grove Keys'
// `TrayPanel` draws it.

/// One row of the dropdown: an item, its text, whether it is hidden.
public struct TrayRow: Identifiable, Equatable, Sendable {
    /// The item's key (`TrayItems.key`); in the theoretical case of two
    /// items with one key, the second's has "~2" added, so rows stay apart.
    public let id: String
    public let item: TrayItem
    /// Where the item is in the listing's `items` (its element to press).
    public let index: Int
    /// `TrayItems.rowText`: quiet, at the right.
    public let text: String?
    public let hidden: Bool
}

/// One listing as the dropdown shows it. Hide and Show work out keys among
/// this same listing's items (`TrayItems.hide/unhide`'s `among`).
public struct TrayList: Equatable, Sendable {
    public let items: [TrayItem]
    public let hiddenKeys: Set<String>
    public let visible: [TrayRow]
    public let hidden: [TrayRow]

    /// `items` as `TrayWatcher` lists them (shown, left to right).
    public init(items: [TrayItem], hidden: Set<String>) {
        self.items = items
        hiddenKeys = hidden
        var used: [String: Int] = [:]
        var visible: [TrayRow] = []
        var away: [TrayRow] = []
        for (index, item) in items.enumerated() {
            let key = TrayItems.key(item, among: items)
            let isHidden = hidden.contains(item.bundleID) || hidden.contains(key)
            used[key, default: 0] += 1
            let id = used[key] == 1 ? key : "\(key)~\(used[key] ?? 1)"
            let row = TrayRow(id: id, item: item, index: index, text: TrayItems.rowText(item), hidden: isHidden)
            if isHidden { away.append(row) } else { visible.append(row) }
        }
        self.visible = visible
        self.hidden = away
    }

    /// "No other menu-bar items": only when nothing is listed at all, hidden
    /// items included (all hidden, the Hidden disclosure says it).
    public var showsNoItems: Bool { visible.isEmpty && hidden.isEmpty }

    /// Every item hidden: the disclosure opens at first, so the panel isn't
    /// a lone fold.
    public var opensHiddenAtFirst: Bool { visible.isEmpty && !hidden.isEmpty }

    public func row(_ id: String) -> TrayRow? {
        visible.first { $0.id == id } ?? hidden.first { $0.id == id }
    }

    /// The new hidden set after Hide (a visible row) or Show (a hidden
    /// one); nil when there is no such row.
    public func toggled(_ id: String) -> Set<String>? {
        guard let row = row(id) else { return nil }
        return row.hidden ? TrayItems.unhide(row.item, hidden: hiddenKeys, among: items)
            : TrayItems.hide(row.item, hidden: hiddenKeys, among: items)
    }

    // MARK: Keys

    /// What ↑ and ↓ stop on: a row, or the "Hidden (n)" line.
    public enum Entry: Hashable, Sendable {
        case row(String)
        case disclosure
    }

    /// The visible rows, the disclosure when anything is hidden, and the
    /// hidden rows while it is open.
    public func entries(expanded: Bool) -> [Entry] {
        var entries = visible.map { Entry.row($0.id) }
        if !hidden.isEmpty {
            entries.append(.disclosure)
            if expanded { entries += hidden.map { .row($0.id) } }
        }
        return entries
    }

    /// ↑ (-1) or ↓ (1), wrapping (`MenuListMove.step`).
    public func moved(from current: Entry?, by step: Int, expanded: Bool) -> Entry? {
        let entries = entries(expanded: expanded)
        let at = current.flatMap { entries.firstIndex(of: $0) }
        return MenuListMove.step(from: at, by: step, selectable: entries.map { _ in true }).map { entries[$0] }
    }

    /// A letter: the next row whose app's name starts with it, wrapping
    /// (`MenuListMove.jump`); the disclosure isn't a name.
    public func jumped(to letter: String, from current: Entry?, expanded: Bool) -> Entry? {
        let entries = entries(expanded: expanded)
        let titles = entries.map { entry -> String in
            guard case .row(let id) = entry else { return "" }
            return row(id)?.item.appName ?? ""
        }
        let at = current.flatMap { entries.firstIndex(of: $0) }
        return MenuListMove.jump(to: letter, from: at, titles: titles, selectable: entries.map { _ in true })
            .map { entries[$0] }
    }

    /// The lit entry after a new listing: kept while it is still there.
    public func kept(_ entry: Entry?, expanded: Bool) -> Entry? {
        guard let entry, entries(expanded: expanded).contains(entry) else { return nil }
        return entry
    }

    // MARK: The row menu

    /// A right-click on a row: Open, Hide from tray or Show in tray, a
    /// line, Bring <App> forward.
    public enum Choice: String, Sendable, CaseIterable {
        case open, hide, show, bringForward

        public func title(app: String) -> String {
            switch self {
            case .open: "Open"
            case .hide: "Hide from tray"
            case .show: "Show in tray"
            case .bringForward: "Bring \(app) forward"
            }
        }

        /// A line above it.
        public var separated: Bool { self == .bringForward }
    }

    public static func menu(app: String, hidden: Bool) -> [Choice] {
        [.open, hidden ? .show : .hide, .bringForward]
    }

    /// The dropdown's words.
    public static let menuBarSettings = "Menu Bar Settings…"
    public static let noItems = "No other menu-bar items"
    public static let needsAccess = "Grove Keys needs Accessibility permission"
    public static let privacySettings = "Privacy Settings…"
    /// System Settings ▸ Menu Bar, where items are really removed (plain
    /// System Settings when the link doesn't open).
    public static let menuBarSettingsURL = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"

    /// The disclosure's line.
    public static func hiddenTitle(_ count: Int) -> String { "Hidden (\(count))" }
}
