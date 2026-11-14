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

    @Test func thePointerAndAClickOverADisabledRowDoNothing() {
        let model = GroveMenuListModel(width: 200, icons: false)
        var chosen: [String] = []
        model.onChoose = { chosen.append($0.id) }
        model.show(Self.rows)
        let rename = model.levels[0].layout.rows[1]
        let middle = CGPoint(x: rename.midX, y: rename.midY)
        model.pointer(0, at: middle)
        #expect(model.levels[0].highlighted == nil)
        model.click(0, at: middle)
        #expect(model.levels[0].highlighted == nil)
        #expect(chosen.isEmpty)
        // Over "Open" it lights; moving onto "Rename" doesn't take the light.
        let open = model.levels[0].layout.rows[0]
        model.pointer(0, at: CGPoint(x: open.midX, y: open.midY))
        #expect(model.levels[0].highlighted == 0)
        model.pointer(0, at: middle)
        #expect(model.levels[0].highlighted == 0)
    }

    @Test func openingAPathStopsAtARowThatCanNotBeChosen() {
        let model = GroveMenuListModel(width: 200, icons: false)
        model.show(Self.rows)
        model.open(path: ["rename"])
        #expect(model.levels[0].highlighted == nil)
        // A disabled submenu row doesn't open.
        var rows = Self.rows
        rows[3].enabled = false
        model.show(rows)
        model.open(path: ["with", "with.a"])
        #expect(model.levels.count == 1)
        #expect(model.levels[0].highlighted == nil)
    }

    @Test func aFilledSubmenuAsksForItsRowsEachTimeItOpens() {
        var asked = 0
        let rows = [
            GroveMenuListRow(id: "with", title: "Open With", kind: .submenu([]), fill: {
                asked += 1
                return [GroveMenuListRow(id: "with.\(asked)", title: "App \(asked)", checked: asked == 1)]
            }),
            GroveMenuListRow(id: "none", title: "Nothing", kind: .submenu([]), fill: { [] }),
        ]
        let model = GroveMenuListModel(width: nil, icons: false)
        model.show(rows)
        #expect(asked == 0)
        model.open(path: ["with"])
        #expect(asked == 1)
        #expect(model.levels[1].rows.map(\.id) == ["with.1"])
        #expect(model.checked.contains("with.1"))
        #expect(model.key(.left))
        model.open(path: ["with"])
        #expect(asked == 2)
        #expect(model.levels[1].rows.map(\.id) == ["with.2"])
        // Filled with nothing: it doesn't open.
        #expect(model.key(.left))
        model.open(path: ["none"])
        #expect(model.levels.count == 1)
    }

    @Test func aRefilledSubmenuKeepsNoTicksFromTheLastFill() {
        var current = true
        let rows = [GroveMenuListRow(id: "with", title: "Open With", kind: .submenu([]), fill: {
            [GroveMenuListRow(id: "with.preview", title: "Preview", checked: current)]
        })]
        let model = GroveMenuListModel(width: nil, icons: false)
        model.show(rows)
        model.open(path: ["with"])
        #expect(model.checked == ["with.preview"])
        _ = model.key(.left)
        current = false
        model.open(path: ["with"])
        #expect(model.checked.isEmpty)
    }

    @Test func withoutAWidthTheMenuFitsItsTitles() {
        let model = GroveMenuListModel(width: nil, icons: false)
        model.show([GroveMenuListRow(id: "a", title: "A")])
        // (Double against Double: Swift Testing's mixed CGFloat/Double `==`
        // reports equal values as different.)
        #expect(model.levels[0].layout.width == Double(GroveMenuListMetrics.submenu))
        model.show([GroveMenuListRow(id: "a", title: String(repeating: "Long title ", count: 4))])
        #expect(model.levels[0].layout.width > Double(GroveMenuListMetrics.submenu))
        #expect(model.levels[0].layout.width <= Double(GroveMenuListMetrics.widest))
    }

    @Test func rowsCompareWithoutTheirFill() {
        let a = GroveMenuListRow(id: "a", title: "A", kind: .submenu([]), fill: { [] })
        let b = GroveMenuListRow(id: "a", title: "A", kind: .submenu([]))
        #expect(a == b)
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
