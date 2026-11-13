import AppKit
import GroveThemesCore
import Testing
@testable import GroveUI

/// The Grove menu's model: what the keys do with disabled rows, which
/// levels keep an icon column, the rows' own ticks.
@MainActor @Suite struct GroveMenuListModelTests {
    static let rows: [GroveMenuListRow] = [
        GroveMenuListRow(id: "open", title: "Open"),
        GroveMenuListRow(id: "rename", title: "Rename", enabled: false),
        GroveMenuListRow(id: "note", title: "Nothing here", kind: .note),
        GroveMenuListRow(id: "with", title: "Open With", kind: .submenu([
            GroveMenuListRow(id: "with.a", title: "Mail", icon: .image(NSImage(size: NSSize(width: 16, height: 16)))),
            GroveMenuListRow(id: "with.b", title: "Música", checked: true),
        ])),
        GroveMenuListRow(id: "remove", title: "Remove", enabled: false),
    ]

    @Test func theKeysPassDisabledRowsAndNotesBy() {
        let model = GroveMenuListModel(width: 200, icons: false)
        model.show(Self.rows)
        #expect(model.key(.down))
        #expect(model.levels[0].highlighted == 0)
        #expect(model.key(.down))
        #expect(model.levels[0].highlighted == 3)
        // Down again wraps past the disabled last row to the first.
        #expect(model.key(.down))
        #expect(model.levels[0].highlighted == 0)
        // Type-to-jump skips "Rename" and "Remove": nothing starts with r.
        #expect(!model.key(.character("r")))
        #expect(model.levels[0].highlighted == 0)
    }

    @Test func aDisabledRowCanNotBeChosen() {
        let model = GroveMenuListModel(width: 200, icons: false)
        var chosen: [String] = []
        model.onChoose = { chosen.append($0.id) }
        model.show(Self.rows)
        model.press(0, 1)
        model.press(0, 4)
        #expect(chosen.isEmpty)
        #expect(model.levels[0].highlighted == nil)
        model.press(0, 0)
        #expect(chosen == ["open"])
    }

    @Test func aLevelKeepsAnIconColumnWhenARowHasAnIcon() {
        let model = GroveMenuListModel(width: 200, icons: false)
        model.show(Self.rows)
        #expect(!model.levels[0].icons)
        model.open(path: ["with"])
        #expect(model.levels.count == 2)
        #expect(model.levels[1].icons)
        // The menu's own level when told to, icons or not.
        let told = GroveMenuListModel(width: 200, icons: true)
        told.show(Self.rows)
        #expect(told.levels[0].icons)
    }

    @Test func rowsCheckedAtAnyLevelAreTicked() {
        let model = GroveMenuListModel(width: 200, icons: false)
        model.show(Self.rows)
        #expect(model.checked == ["with.b"])
    }

    @Test func aSubmenuGoesBesideItsRow() {
        let model = GroveMenuListModel(width: 200, icons: false)
        model.show(Self.rows)
        #expect(model.submenus.isEmpty)
        #expect(model.key(.down) && model.key(.down) && model.key(.right))
        let submenus = model.submenus
        #expect(submenus.count == 1)
        #expect(submenus.first?.depth == 1)
        #expect(submenus.first?.row == model.levels[0].layout.rows[3])
        #expect(model.levels[1].highlighted == 0)
        #expect(model.key(.left))
        #expect(model.submenus.isEmpty)
    }
}
