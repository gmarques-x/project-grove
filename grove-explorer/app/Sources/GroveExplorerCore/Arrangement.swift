import Foundation

/// What a pane's rows were arranged by: the folder they are of, the sort,
/// the ⌘F filter's text, whether hidden items show and which folders are
/// open in place. A listing is shown for a tab only when it was arranged by
/// that tab's own.
public struct Arrangement: Equatable, Sendable {
    public var folder: URL
    public var sort: SortOrder
    /// The filter field's text as typed.
    public var filter: String
    public var showHidden: Bool
    /// The folders open in place (spec §16), as the tab has them: rows
    /// arranged with one set open are other rows than with another.
    public var open: Set<URL>
    /// The context folders closed under the filter (`ListFilter.closed`),
    /// which stay as rows.
    public var closedUnderFilter: Set<URL>

    public init(
        folder: URL, sort: SortOrder, filter: String, showHidden: Bool, open: Set<URL>,
        closedUnderFilter: Set<URL> = []
    ) {
        self.folder = folder
        self.sort = sort
        self.filter = filter
        self.showHidden = showHidden
        self.open = open
        self.closedUnderFilter = closedUnderFilter
    }

    /// The filter's words; none for a field that is empty or all spaces.
    private var words: [Substring] { filter.split(whereSeparator: \.isWhitespace) }

    /// Whether the filter leaves anything out: it has a word.
    public var isFiltered: Bool { !words.isEmpty }

    /// The open folders by path, however each is spelled.
    private var openPaths: Set<String> { Set(open.map(\.standardizedPath)) }

    /// Whether rows arranged by this may be shown as they are for a tab
    /// that asks for `wanted`: the same folder (however its path is
    /// spelled), sort, hidden flag, filter words and open folders. Anything
    /// else is arranged again first: another tab's filter would hide files,
    /// and its field isn't there to say so; another tab's open folders
    /// would show rows this one doesn't have.
    public func serves(_ wanted: Arrangement) -> Bool {
        sort == wanted.sort && hasSameItems(as: wanted)
    }

    /// Whether rows that were being arranged off the main thread may be
    /// shown now that they arrive: only when they were arranged by what
    /// the pane's tab asks for at this moment (`wanted`; nil: the pane has
    /// no tab). An arrangement for the tab that was showing when it was
    /// asked for (its filter, its sort) is dropped once the pane shows
    /// another tab, of the same folder or not, or the tab asks for
    /// something else.
    public static func mayShow(arrived: Arrangement, for wanted: Arrangement?) -> Bool {
        guard let wanted else { return false }
        return arrived.serves(wanted)
    }

    /// Whether this and `other` show the same items (the same folder,
    /// filter words, hidden flag, open folders and folders closed under
    /// the filter), whatever their order.
    func hasSameItems(as other: Arrangement) -> Bool {
        folder.standardizedPath == other.folder.standardizedPath
            && showHidden == other.showHidden && words == other.words
            && (open.isEmpty && other.open.isEmpty || openPaths == other.openPaths)
            && Set(closedUnderFilter.map(\.standardizedPath)) == Set(other.closedUnderFilter.map(\.standardizedPath))
    }
}

/// What the rows a pane shows of a folder are, in one value: the rows and
/// what they were arranged by can't be told apart from each other.
public enum RowsState: Equatable, Sendable {
    /// The rows are this arrangement's.
    case arranged(by: Arrangement)
    /// The rows are `of`'s, shown until `awaiting`'s arrive: the same
    /// items in another order.
    case oldOrder(of: Arrangement, awaiting: Arrangement)
    /// No rows are shown until this arrangement's arrive: the pane is
    /// blank, and its folder is not thereby empty.
    case awaiting(Arrangement)

    /// A folder of up to this many entries is arranged again at once, on
    /// the main thread, when a tab comes to show it; a larger one off it,
    /// so the window never waits for a sort.
    public static let arrangeNowLimit = 10_000

    /// What a pane does with a listing it already has of a folder when a
    /// tab comes to show that folder. In the order of preference among
    /// several listings: the one that needs least.
    public enum Reuse: Int, Comparable, Sendable {
        /// The rows are what the tab asks for: shown as they are.
        case asItIs
        /// The folder is small enough to arrange by the tab's own before
        /// anything is shown.
        case arrangeNow
        /// A big folder whose rows are the right items in another order:
        /// shown so until the tab's order, arranged off the main thread, is ready.
        case oldOrder
        /// The rows the tab asks for are already awaited: nothing is
        /// shown differently. The pane begins the arrange again all the
        /// same, its own as much as another pane's.
        case keepWaiting
        /// A big folder whose rows are other items than the tab's (another
        /// filter, hidden items) or are not there yet: no rows are shown
        /// until the tab's own, arranged off the main thread, are ready.
        case blank

        public static func < (one: Reuse, other: Reuse) -> Bool { one.rawValue < other.rawValue }
    }

    /// See `Reuse`: `wanted` is what the tab asks for, `entries` how many
    /// items the folder has. Rows that are awaited are never reused as
    /// rows, whatever they await.
    public func reuse(for wanted: Arrangement, entries: Int) -> Reuse {
        /// The rows there are, if any, and what they are arranged by.
        let shown: Arrangement?
        switch self {
        case let .arranged(by):
            shown = by
        case let .oldOrder(of, awaiting):
            if of.serves(wanted) { return .asItIs }
            if awaiting.serves(wanted) { return .keepWaiting }
            shown = of
        case let .awaiting(awaited):
            if awaited.serves(wanted) { return .keepWaiting }
            shown = nil
        }
        if let shown, shown.serves(wanted) { return .asItIs }
        if entries <= Self.arrangeNowLimit { return .arrangeNow }
        if let shown, shown.hasSameItems(as: wanted) { return .oldOrder }
        return .blank
    }

    /// The state once `reuse` (what `reuse(for:entries:)` said for
    /// `wanted`) has been applied.
    public func after(_ reuse: Reuse, for wanted: Arrangement) -> RowsState {
        switch (reuse, self) {
        case (.arrangeNow, _): .arranged(by: wanted)
        case (.blank, _): .awaiting(wanted)
        case (.keepWaiting, _): self
        // Rows in an old order are, for the tab that has that order, simply its rows.
        case let (.asItIs, .oldOrder(of, _)): .arranged(by: of)
        case (.asItIs, _): self
        case let (.oldOrder, .arranged(by)): .oldOrder(of: by, awaiting: wanted)
        case let (.oldOrder, .oldOrder(of, _)): .oldOrder(of: of, awaiting: wanted)
        // No rows to keep in any order.
        case (.oldOrder, .awaiting): .awaiting(wanted)
        }
    }

    /// Rows arranged off the main thread by `arrived` come back: the state
    /// when they are shown, or nil when they are dropped because the
    /// pane's tab does not ask for them now (`Arrangement.mayShow`).
    public func arrival(of arrived: Arrangement, tabWants wanted: Arrangement?) -> RowsState? {
        Arrangement.mayShow(arrived: arrived, for: wanted) ? .arranged(by: arrived) : nil
    }

    /// Whether a read of the folder that found the same entries, arranged
    /// as `asked`, changes nothing the pane shows: only when its rows are
    /// there and arranged so. Rows in an old order, or awaited, take the
    /// read's.
    public func isUnchanged(byReadFor asked: Arrangement) -> Bool {
        if case let .arranged(by) = self { return by.serves(asked) }
        return false
    }

    /// The pane is blank for the moment: nothing is to be said of its
    /// folder (not "empty", not "0 items").
    public var isAwaitingRows: Bool {
        if case .awaiting = self { return true }
        return false
    }
}
