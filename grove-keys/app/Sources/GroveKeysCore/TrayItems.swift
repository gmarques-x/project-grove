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
    /// The item's left edge on screen: the order. Nil when it can't be
    /// read (the item goes last).
    public var x: Double?

    public init(bundleID: String, appName: String, pid: pid_t, identifier: String? = nil, title: String? = nil,
                description: String? = nil, help: String? = nil, x: Double?) {
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

    /// An item with an owner to go by: its app was still running when the
    /// bar was read (a bundle id, or a tool's name, and a name).
    public static func listable(_ item: TrayItem) -> Bool {
        present(item.bundleID) != nil && present(item.appName) != nil
    }

    /// The left-to-right order of places, as indices into `xs`: places
    /// without an x last, and equal places in the order given (the tree's).
    /// A permutation, so a caller can line other lists up by it.
    public static func order(_ xs: [Double?]) -> [Int] {
        xs.indices.sorted { a, b in
            switch (xs[a], xs[b]) {
            case let (ax?, bx?): return ax != bx ? ax < bx : a < b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a < b
            }
        }
    }

    /// The items left to right (`order`).
    public static func ordered(_ items: [TrayItem]) -> [TrayItem] {
        order(items.map(\.x)).map { items[$0] }
    }

    /// Every item except those of MenuBarAgent itself, any `com.apple.`
    /// app, SketchyBar, and any whose owner is gone, left to right.
    public static func shown(_ items: [TrayItem]) -> [TrayItem] {
        ordered(items.filter {
            listable($0) && $0.bundleID != StatusItems.agentBundleID && !$0.bundleID.hasPrefix("com.apple.")
                && !$0.isSketchyBar
        })
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
        // Where the item is among them (added when it isn't), then its
        // place in their order: always found, as `order` is a permutation.
        let at = mine.firstIndex { same($0, item) } ?? {
            mine.append(item)
            return mine.count - 1
        }()
        if let id = present(item.identifier), id != present(item.title), id != present(item.description),
           mine.count(where: { present($0.identifier) == id }) == 1 {
            return "\(item.bundleID)#\(id)"
        }
        let index = order(mine.map(\.x)).firstIndex(of: at) ?? 0
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

    /// The longest row text, "…" included.
    public static let rowTextLimit = 32

    /// The row's text as the dropdown shows it: title, then description,
    /// then help, with the app's name taken off its start when a line break
    /// or a separator (":", "-", "·"…) follows it ("Example Sync\nSync issue"
    /// is "Sync issue"; "Example Sync is paused" stays), then on one line
    /// (runs of spaces, tabs and newlines as one space); the first that
    /// leaves something. Longer than `rowTextLimit`, cut with "…".
    public static func rowText(_ item: TrayItem) -> String? {
        let name = oneLine(item.appName)
        for candidate in [item.title, item.description, item.help] {
            guard let candidate else { continue }
            let text = oneLine(withoutName(candidate, name))
            if !text.isEmpty { return cut(text) }
        }
        return nil
    }

    /// Runs of whitespace (newlines too) as one space, none at the ends.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// `text` without `name` at its start when nothing, a line break or a
    /// separator follows it, and without what separates them; else `text`.
    private static func withoutName(_ text: String, _ name: String) -> String {
        let text = text.drop { $0.isWhitespace || $0.isNewline }
        guard !name.isEmpty, let range = text.range(of: name, options: [.caseInsensitive, .anchored]) else {
            return String(text)
        }
        let rest = text[range.upperBound...]
        let separators: Set<Character> = [":", "-", "–", "—", "·", "|", ",", "•"]
        let spaced = rest.drop { $0 == " " || $0 == "\t" }
        guard let next = spaced.first else { return "" }
        guard next.isNewline || separators.contains(next) else { return String(text) }
        return String(rest.drop { $0.isWhitespace || $0.isNewline || separators.contains($0) })
    }

    private static func cut(_ text: String) -> String {
        guard text.count > rowTextLimit else { return text }
        let kept = text.prefix(rowTextLimit - 1)
        return String(kept[..<(kept.lastIndex { !$0.isWhitespace }.map { kept.index(after: $0) } ?? kept.startIndex)]) + "…"
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

    /// The same over a snapshot: element ids and window numbers each
    /// against their own kind, so one can't hide the other.
    public static func opened(before: TrayPress.Snapshot, after: TrayPress.Snapshot) -> Bool {
        opened(before: before.elements, after: after.elements) || opened(before: before.windows, after: after.windows)
    }
}

/// Pressing a tray item, the Opened rule (spec 2026-11-14-bar-tray-design):
/// the app's element is pressed; "opened" is a new menu or window of the
/// item's pid within a second; else the MenuBarAgent wrapper is pressed
/// once, the same test; else the app is brought forward. What the presser
/// (Grove Keys' `TrayPresser`) does is injected, so the order is tested here.
public enum TrayPress {
    /// What the item's app has open: ids of its Accessibility windows and
    /// menus (`elements`), and its window server window numbers (`windows`).
    public struct Snapshot: Equatable, Sendable {
        public var elements: [Int]
        public var windows: [Int]

        public init(elements: [Int], windows: [Int]) {
            self.elements = elements
            self.windows = windows
        }
    }

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
    ///   - snapshot: what the pid has open now.
    ///   - press: presses the element (false) or the wrapper (true).
    ///   - within: polls a probe until it is true or the second is up.
    public static func run(wrapper: Bool, trusted: Bool, isRunning: () -> Bool, snapshot: () -> TrayPress.Snapshot,
                           press: (_ wrapper: Bool) -> Void, within: (() -> Bool) -> Bool) -> Outcome {
        guard isRunning() else { return .gone }
        guard trusted else { return .broughtForward }
        return withoutActuallyEscaping(snapshot) { snapshot in
            pressing(wrapper: wrapper, snapshot: snapshot, press: press, within: within)
        }
    }

    private static func pressing(wrapper: Bool, snapshot: @escaping () -> TrayPress.Snapshot, press: (_ wrapper: Bool) -> Void,
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
