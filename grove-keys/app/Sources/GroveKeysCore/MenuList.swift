import GroveThemesCore

// The Grove menu's rows as `GroveMenuList` draws them. The list's rules
// (the keys' moves, the hover timing, the rows' rectangles, a submenu's
// place) are GroveThemesCore's (`MenuListRules.swift`); only what knows a
// Grove menu row is here.

extension MenuListRowKind {
    /// A Grove menu row's kind: the Global Menu builtin is a link.
    public init(_ row: GroveMenuRow) {
        if row.isNote {
            self = .note
        } else if !row.children.isEmpty {
            self = .submenu
        } else {
            self = row.action == .builtin(.globalMenu) ? .link : .action
        }
    }
}
