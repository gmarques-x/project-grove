import GroveThemesCore
import Testing
@testable import GroveKeysCore

// The list's own rules are tested with them, in grove-themes
// (`MenuListRulesTests`); this is what a Grove menu row makes of them.
@Suite struct MenuListRowKindTests {
    /// The Global Menu opens the native menu, not one of these panels: it is
    /// still a link (→ opens it too), drawn without the arrow.
    @Test func globalMenuRowHasNoChevron() throws {
        let menu = try GroveMenu.strict(main: try fixture("menu.toml"))
        let row = try #require(menu.row(id: "global-menu"))
        #expect(MenuListRowKind(row) == .link)
        #expect(!MenuListRowKind(row).showsChevron)
        let appearance = try #require(menu.row(id: "appearance"))
        #expect(MenuListRowKind(appearance) == .submenu)
        #expect(MenuListRowKind(GroveMenuRow(id: "x", title: "A note")) == .note)
        #expect(MenuListRowKind(GroveMenuRow(id: "y", title: "Run", action: .run("true"))) == .action)
    }
}
