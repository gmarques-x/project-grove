import Foundation

/// What a pane's rows were arranged by: the folder they are of, the sort,
/// the ⌘F filter's text and whether hidden items show. A listing is shown
/// for a tab only when it was arranged by that tab's own.
public struct Arrangement: Equatable, Sendable {
    public var folder: URL
    public var sort: SortOrder
    /// The filter field's text as typed.
    public var filter: String
    public var showHidden: Bool

    public init(folder: URL, sort: SortOrder, filter: String, showHidden: Bool) {
        self.folder = folder
        self.sort = sort
        self.filter = filter
        self.showHidden = showHidden
    }

    /// The filter's words; none for a field that is empty or all spaces.
    private var words: [Substring] { filter.split(whereSeparator: \.isWhitespace) }

    /// Whether the filter leaves anything out: it has a word.
    public var isFiltered: Bool { !words.isEmpty }

    /// Whether rows arranged by this may be shown as they are for a tab
    /// that asks for `wanted`: the same folder (however its path is
    /// spelled), sort, hidden flag and filter words. Anything else is
    /// arranged again first: another tab's filter would hide files, and
    /// its field isn't there to say so.
    public func serves(_ wanted: Arrangement) -> Bool {
        folder.standardizedFileURL.path == wanted.folder.standardizedFileURL.path
            && sort == wanted.sort && showHidden == wanted.showHidden && words == wanted.words
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

    /// A folder of up to this many entries is arranged again at once, on
    /// the main thread, when a tab comes to show it; a larger one off it,
    /// so the window never waits for a sort.
    public static let arrangeNowLimit = 10_000

    /// What a pane does with rows it already has of a folder when a tab
    /// comes to show that folder.
    public enum Reuse: Equatable, Sendable {
        /// They were arranged as the tab asks: shown as they are.
        case asItIs
        /// Few enough to arrange by the tab's own before they are shown.
        case arrangeNow
        /// Many, and only the sort differs: the same rows are shown in
        /// the order they have until the tab's order is ready.
        case oldOrder
        /// Many, and the filter or the hidden items differ: no rows are
        /// shown until the tab's own are ready (another tab's pick would
        /// hide files, or show hidden ones).
        case blank
    }

    /// See `Reuse`. `self` is what the rows were arranged by, `wanted` what
    /// the tab asks for, `entries` how many items the folder has.
    public func reuse(for wanted: Arrangement, entries: Int) -> Reuse {
        if serves(wanted) { return .asItIs }
        if entries <= Self.arrangeNowLimit { return .arrangeNow }
        return showHidden == wanted.showHidden && words == wanted.words ? .oldOrder : .blank
    }
}
