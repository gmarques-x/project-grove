/// Which row of a key panel is selected, and how ↑/↓, a click and a new
/// list move it. Pure: the panel's owner keeps one and shows `selected`.
///
/// The selection is a place in the list (so two rows with one id can't trap
/// it), read back as that row's id.
public struct KeyPanelSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    /// The rows' ids, in the order ↑/↓ walk them.
    public private(set) var ids: [ID] = []
    /// The selected row's place in `ids`; nil only when there are no rows.
    public private(set) var index: Int?

    public init() {}

    /// The selected row's id.
    public var selected: ID? { index.map { ids[$0] } }

    /// A new list. The first row is selected, unless `keepingSelection` and
    /// the selected row is still listed: then it stays selected where it now
    /// is (a list brought up to date under the same query).
    public mutating func show(_ ids: [ID], keepingSelection: Bool = false) {
        let kept = keepingSelection ? selected.flatMap(ids.firstIndex(of:)) : nil
        self.ids = ids
        index = kept ?? (ids.isEmpty ? nil : 0)
    }

    /// ↑ (−1) and ↓ (1): stops at the first and the last row.
    public mutating func move(_ step: Int) {
        guard !ids.isEmpty else { return }
        index = min(max((index ?? 0) + step, 0), ids.count - 1)
    }

    /// A click on a row. A row that isn't listed changes nothing.
    public mutating func select(_ id: ID) {
        if let at = ids.firstIndex(of: id) { index = at }
    }
}
