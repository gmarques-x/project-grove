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
}
