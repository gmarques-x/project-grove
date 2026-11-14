import Foundation
import GroveThemesCore

// The bar's tray (spec 2026-11-14-bar-tray-design): other apps' menu-bar
// items, listed in a panel, with a count on the bar. The rules live here;
// reading the tree and pressing items is Grove Keys' (`StatusItemLocator`).

/// One status item, as read from MenuBarAgent's tree.
public struct TrayItem: Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var pid: pid_t
    public var identifier: String?
    public var title: String?
    public var description: String?
    public var help: String?
    /// The item's left edge on screen: the order.
    public var x: Double

    public init(bundleID: String, appName: String, pid: pid_t, identifier: String? = nil, title: String? = nil,
                description: String? = nil, help: String? = nil, x: Double) {
        self.bundleID = bundleID
        self.appName = appName
        self.pid = pid
        self.identifier = identifier
        self.title = title
        self.description = description
        self.help = help
        self.x = x
    }

    /// SketchyBar is a command-line tool: no bundle id to go by, so its
    /// process name.
    public var isSketchyBar: Bool {
        appName.lowercased() == "sketchybar" || bundleID.lowercased().contains("sketchybar")
    }
}

public enum TrayItems {
    /// Hidden by default: Grove's own apps and AeroSpace.
    public static let defaultHidden: Set<String> = ["com.projectgrove.keys", "com.projectgrove.themes", "bobko.aerospace"]

    /// Every item except those of MenuBarAgent itself, any `com.apple.`
    /// app and SketchyBar, left to right.
    public static func shown(_ items: [TrayItem]) -> [TrayItem] {
        items.filter {
            $0.bundleID != StatusItems.agentBundleID && !$0.bundleID.hasPrefix("com.apple.") && !$0.isSketchyBar
        }.sorted { $0.x < $1.x }
    }

    private static func present(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// `<bundleID>#<AXIdentifier>` when the identifier is non-empty and
    /// differs from the item's title and description (a status text as the
    /// identifier changes with it); else `<bundleID>#<index>` among that
    /// app's items, left to right.
    public static func key(_ item: TrayItem, among: [TrayItem]) -> String {
        var mine = among.filter { $0.bundleID == item.bundleID }
        if !mine.contains(where: { same($0, item) }) { mine.append(item) }
        mine.sort { $0.x < $1.x }
        if let id = present(item.identifier), id != present(item.title), id != present(item.description),
           mine.count(where: { present($0.identifier) == id }) == 1 {
            return "\(item.bundleID)#\(id)"
        }
        let index = mine.firstIndex { same($0, item) }!
        return "\(item.bundleID)#\(index)"
    }

    /// The same item: by pid, place, identifier and title.
    private static func same(_ a: TrayItem, _ b: TrayItem) -> Bool {
        a.pid == b.pid && a.x == b.x && a.identifier == b.identifier && a.title == b.title
    }

    /// Hides one item: its key joins the set.
    public static func hide(_ item: TrayItem, hidden: Set<String>, among: [TrayItem]) -> Set<String> {
        hidden.union([key(item, among: among)])
    }

    /// Shows one item. When its whole app is hidden by the bare bundle id,
    /// the id goes and the app's other items are hidden by their keys.
    public static func unhide(_ item: TrayItem, hidden: Set<String>, among: [TrayItem]) -> Set<String> {
        var result = hidden
        if result.remove(item.bundleID) != nil {
            for other in among where other.bundleID == item.bundleID && !same(other, item) {
                result.insert(key(other, among: among))
            }
        }
        result.remove(key(item, among: among))
        return result
    }

    /// The row's text: title, then description, then help; the first that
    /// is there and isn't the app's name.
    public static func text(_ item: TrayItem) -> String? {
        let name = item.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [item.title, item.description, item.help].lazy.compactMap(present).first { $0.lowercased() != name }
    }

    /// Visible and hidden: an item is hidden by its key, or by its bare
    /// bundle id (the defaults are whole apps). Keys are worked out among
    /// all the items.
    public static func split(_ items: [TrayItem], hidden: Set<String>) -> (visible: [TrayItem], hidden: [TrayItem]) {
        var visible: [TrayItem] = []
        var away: [TrayItem] = []
        for item in items {
            if hidden.contains(item.bundleID) || hidden.contains(key(item, among: items)) { away.append(item) } else { visible.append(item) }
        }
        return (visible, away)
    }

    /// The bar's number: the visible items.
    public static func count(visible: [TrayItem]) -> Int { visible.count }

    /// A press opened something: among the ids of the app's windows and
    /// menus after it, one that wasn't there before (a press's answer isn't
    /// proof; something new is).
    public static func opened(before: [Int], after: [Int]) -> Bool {
        let old = Set(before)
        return after.contains { !old.contains($0) }
    }
}

/// Pressing a tray item, the Opened rule (spec 2026-11-14-bar-tray-design):
/// the app's element is pressed; "opened" is a new menu or window of the
/// item's pid within a second; else the MenuBarAgent wrapper is pressed
/// once, the same test; else the app is brought forward. What the presser
/// (Grove Keys' `TrayPresser`) does is injected, so the order is tested here.
public enum TrayPress {
    public enum Outcome: Equatable, Sendable {
        /// The element's press opened a menu or window.
        case opened
        /// The wrapper's did.
        case wrapperOpened
        /// Nothing opened (or no Accessibility): the app goes to the front.
        case broughtForward
        /// Its app isn't running any more: nothing pressed.
        case gone
    }

    /// - Parameters:
    ///   - wrapper: the item has a MenuBarAgent group around it.
    ///   - trusted: Grove Keys has Accessibility; without it nothing is
    ///     pressed or read.
    ///   - isRunning: the item's app is still running; asked first, before
    ///     any Accessibility call.
    ///   - snapshot: the ids of the pid's windows and menus now.
    ///   - press: presses the element (false) or the wrapper (true).
    ///   - within: polls a probe until it is true or the second is up.
    public static func run(wrapper: Bool, trusted: Bool, isRunning: () -> Bool, snapshot: () -> [Int],
                           press: (_ wrapper: Bool) -> Void, within: (() -> Bool) -> Bool) -> Outcome {
        guard isRunning() else { return .gone }
        guard trusted else { return .broughtForward }
        return withoutActuallyEscaping(snapshot) { snapshot in
            pressing(wrapper: wrapper, snapshot: snapshot, press: press, within: within)
        }
    }

    private static func pressing(wrapper: Bool, snapshot: @escaping () -> [Int], press: (_ wrapper: Bool) -> Void,
                                 within: (() -> Bool) -> Bool) -> Outcome {
        let before = snapshot()
        press(false)
        if within({ TrayItems.opened(before: before, after: snapshot()) }) { return .opened }
        guard wrapper else { return .broughtForward }
        // Something that opened just after the wait counts: pressing the
        // wrapper now would only close it.
        if TrayItems.opened(before: before, after: snapshot()) { return .opened }
        let again = snapshot()
        press(true)
        if within({ TrayItems.opened(before: again, after: snapshot()) }) { return .wrapperOpened }
        return .broughtForward
    }
}

/// `$GROVE_STATE/tray-hidden`: one key per line. Grove Keys writes it.
public enum TrayHiddenFile {
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("tray-hidden")
    }

    /// Missing (or unreadable): the defaults.
    public static func read(_ url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return TrayItems.defaultHidden }
        return Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// Sorted, one per line.
    public static func write(_ keys: Set<String>, to url: URL) throws {
        let text = keys.sorted().map { $0 + "\n" }.joined()
        try writeAtomically(Data(text.utf8), to: url)
    }
}

/// The bar's tray: `$GROVE_STATE/tray`, one line, the count. The bar's
/// `tray` item reads it; no file shows the symbol without a count.
public enum TrayBarFile {
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("tray")
    }

    /// Writes the count unless the file holds it; nil removes the file.
    /// True when the file changed, so the bar is told only then.
    @discardableResult
    public static func update(_ count: Int?, at url: URL) throws -> Bool {
        guard let count else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                return false
            }
            return true
        }
        let line = "\(count)\n"
        guard (try? String(contentsOf: url, encoding: .utf8)) != line else { return false }
        try writeAtomically(Data(line.utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
}
