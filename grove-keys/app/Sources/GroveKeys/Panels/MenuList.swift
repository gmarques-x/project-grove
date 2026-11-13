import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// A menu in the bar panels' frame: rows in a panel, a submenu as a second
// panel beside it (`BarPanelSide`), one highlighted row per level shared by
// the pointer and the keys. The Grove menu is built from it
// (`GroveMenuPanel.swift`); so can any later menu: give `MenuListModel` its
// rows, draw `MenuListPanel(model:level: 0)` and pass on the keys.
//
// Hand-built on purpose: a native menu (`NSMenu`, `Menu`) can't take the
// panels' frame, outline, font or place (the owner's decision, spec
// 2026-11-12-bar-panels-design §2), and `KeyPanelList` has no levels. What
// is pure (the keys' moves, the hover timing, the rows' rectangles, a
// submenu's place) is `GroveKeysCore/MenuList.swift`, tested.

/// One row of a menu.
struct MenuListRow: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Choosing it does something.
        case action
        /// The same, for a row that opens something that is not one of
        /// these panels (the native Global Menu): → opens it too; drawn
        /// without the chevron (`MenuListRowKind.showsChevron`).
        case link
        /// It opens these rows in a panel beside this one.
        case submenu([MenuListRow])
        /// Text that can't be chosen (an error, a warning's line).
        case note
    }

    /// Unique in the whole menu: what `onChoose` and `checked` know a row by.
    var id: String
    var title: String
    /// Drawn before the title, in a column every row of the level keeps.
    var icon: GroveIcon.Name?
    /// A line above the row (not drawn above a level's first row).
    var separator = false
    var kind: Kind

    var isSelectable: Bool { kind != .note }

    var children: [MenuListRow]? {
        if case .submenu(let rows) = kind { return rows }
        return nil
    }

    /// The kind without its rows, for what Core decides about it.
    var coreKind: MenuListRowKind {
        switch kind {
        case .action: .action
        case .link: .link
        case .submenu: .submenu
        case .note: .note
        }
    }
}

/// The measures of a menu's panel. Rows have fixed heights, so where each
/// row is can be computed (`MenuListLayout`) rather than read back from the
/// drawn views.
@MainActor
enum MenuListMetrics {
    /// A row: a line of label text and the rows' 4 pt above and below.
    static let row = GroveSpace.s24
    /// A submenu's width, unless its titles need more (up to `widest`).
    static let submenu: CGFloat = 190
    /// A measured limit: what the longest of Grove Keys' own lines needs at
    /// label size ("Grove Keys needs Input Monitoring — Open Settings");
    /// longer notes wrap, longer titles are cut.
    static let widest: CGFloat = 408
    /// The room kept at a row's right for the tick or the chevron.
    static let mark = PanelMetrics.iconColumn

    static let layout = MenuListLayout.Metrics(
        edge: PanelMetrics.inset - GroveSpace.s4, side: PanelMetrics.inset - GroveSpace.s8,
        rule: 1 + 2 * GroveSpace.s4)

    private static let font = GroveFont.monoNS(GroveType.label)

    /// A title's width at label size.
    static func width(of title: String) -> CGFloat {
        ceil(NSAttributedString(string: title, attributes: [.font: font]).size().width)
    }

    /// A note's height when wrapped into `width`: whole lines, at least a row.
    static func noteHeight(_ text: String, width: CGFloat) -> CGFloat {
        let bounds = NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return max(row, ceil(bounds.height) + 2 * GroveSpace.s4)
    }
}

/// A menu's state: the levels shown (the menu itself, then each open
/// submenu), each with its highlighted row.
@MainActor
final class MenuListModel: ObservableObject {
    struct Level {
        let rows: [MenuListRow]
        let layout: MenuListLayout
        /// Whether the rows keep an icon column.
        let icons: Bool
        /// The row under the pointer or chosen with the keys.
        var highlighted: Int?
    }

    /// The menu (0), then each open submenu in order.
    @Published private(set) var levels: [Level] = []
    /// The ids of the rows to tick.
    @Published var checked: Set<String> = []

    /// A row that does something was chosen (a click, Return, Space).
    var onChoose: (MenuListRow) -> Void = { _ in }
    /// A level was shown (the menu, a submenu just opened): the place to
    /// start what its rows need (their `checked` tests).
    var onShow: ([MenuListRow]) -> Void = { _ in }
    /// The open submenus changed: the host re-places the side panels.
    var onLevels: () -> Void = {}

    private let width: CGFloat
    private let icons: Bool
    /// Per level: its submenu's timing, the pointer's last place in it, and
    /// whether its submenu's panel is at its left (no room at the right).
    private var intents: [MenuHoverIntent] = []
    private var pointers: [CGPoint?] = []
    private var submenuOnLeft: [Bool] = []
    /// The level the keys act on.
    private var focus = 0
    private var timer: Timer?

    /// - `width`: the menu's own panel; submenus fit their titles.
    /// - `icons`: the menu's rows keep an icon column (a row without an
    ///   icon keeps the indent). Submenus have none.
    init(width: CGFloat, icons: Bool) {
        self.width = width
        self.icons = icons
    }

    // MARK: Showing

    /// Shows `rows` as the menu, nothing open or highlighted.
    func show(_ rows: [MenuListRow]) {
        cancelTimer()
        checked = []
        levels = [level(rows, depth: 0)]
        intents = [MenuHoverIntent()]
        pointers = [nil]
        submenuOnLeft = [false]
        focus = 0
        onShow(rows)
        onLevels()
    }

    /// Nothing shown and nothing running (the panel closed).
    func clear() {
        cancelTimer()
        levels = []
        intents = []
        pointers = []
        submenuOnLeft = []
        focus = 0
    }

    /// Opens the submenus along `ids` (each a row of the level before) and
    /// highlights the last row named; stops at the first id that isn't there.
    func open(path ids: [String]) {
        for id in ids {
            let depth = levels.count - 1
            guard depth >= 0, let index = levels[depth].rows.firstIndex(where: { $0.id == id }) else { return }
            if levels[depth].rows[index].children != nil {
                openSubmenu(depth, index, highlightFirst: false)
            } else {
                highlight(depth, index)
                focus = depth
                return
            }
        }
    }

    /// The highlighted row of the level the keys act on.
    func highlight(first: Bool) {
        guard levels.indices.contains(focus) else { return }
        let selectable = levels[focus].rows.map(\.isSelectable)
        highlight(focus, first ? MenuListMove.first(selectable: selectable) : MenuListMove.last(selectable: selectable))
    }

    /// The side panels the open submenus need, in order.
    func sides(view: (Int) -> AnyView) -> [BarPanelSide] {
        (1..<max(levels.count, 1)).compactMap { depth in
            guard let open = intents[depth - 1].open, levels[depth - 1].layout.rows.indices.contains(open) else { return nil }
            return BarPanelSide(id: depth, view: view(depth), size: levels[depth].layout.size,
                                row: levels[depth - 1].layout.rows[open],
                                firstRow: MenuListMetrics.layout.edge,
                                placed: { [weak self] onLeft in
                                    guard let self, self.submenuOnLeft.indices.contains(depth - 1) else { return }
                                    self.submenuOnLeft[depth - 1] = onLeft
                                })
        }
    }

    private func level(_ rows: [MenuListRow], depth: Int) -> Level {
        let icons = depth == 0 && self.icons
        var width = self.width
        if depth > 0 {
            let titles = rows.map { MenuListMetrics.width(of: $0.title) + ($0.isSelectable ? GroveSpace.s8 + MenuListMetrics.mark : 0) }
            width = min(MenuListMetrics.widest,
                        max(MenuListMetrics.submenu, (titles.max() ?? 0) + 2 * PanelMetrics.inset))
        }
        // A note has the whole line (no icon column, no mark) and wraps.
        let heights = rows.map { row in
            row.isSelectable ? MenuListMetrics.row
                : MenuListMetrics.noteHeight(row.title, width: width - 2 * PanelMetrics.inset)
        }
        return Level(rows: rows,
                     layout: MenuListLayout(width: width, heights: heights.map(Double.init),
                                            separators: rows.map(\.separator), metrics: MenuListMetrics.layout),
                     icons: icons, highlighted: nil)
    }

    // MARK: Levels

    private func highlight(_ depth: Int, _ row: Int?) {
        guard levels.indices.contains(depth), levels[depth].highlighted != row else { return }
        levels[depth].highlighted = row
    }

    /// Opens the submenu of `row` at `depth`, at once. `highlightFirst`:
    /// the keys go into it (→, Return); otherwise they stay where they are.
    private func openSubmenu(_ depth: Int, _ row: Int, highlightFirst: Bool) {
        guard levels.indices.contains(depth), let children = levels[depth].rows[row].children else { return }
        let alreadyOpen = intents[depth].open == row && levels.count > depth + 1
        if !alreadyOpen {
            truncate(to: depth)
            intents[depth].set(open: row)
            levels.append(level(children, depth: depth + 1))
            intents.append(MenuHoverIntent())
            pointers.append(nil)
            submenuOnLeft.append(false)
        }
        highlight(depth, row)
        if highlightFirst {
            focus = depth + 1
            if levels[focus].highlighted == nil { highlight(first: true) }
        } else {
            focus = min(focus, depth + 1)
        }
        if !alreadyOpen {
            onShow(children)
            onLevels()
        }
        schedule()
    }

    /// Closes every submenu below `depth`'s panel. True when one was open.
    @discardableResult
    private func closeSubmenus(below depth: Int) -> Bool {
        guard levels.count > depth + 1 else { return false }
        truncate(to: depth)
        intents[depth].set(open: nil)
        focus = min(focus, depth)
        onLevels()
        schedule()
        return true
    }

    private func truncate(to depth: Int) {
        levels.removeSubrange((depth + 1)...)
        intents.removeSubrange((depth + 1)...)
        pointers.removeSubrange((depth + 1)...)
        submenuOnLeft.removeSubrange((depth + 1)...)
    }

    private func activate(_ depth: Int, _ index: Int, byKey: Bool) {
        guard levels.indices.contains(depth), levels[depth].rows.indices.contains(index) else { return }
        let row = levels[depth].rows[index]
        switch row.kind {
        case .submenu: openSubmenu(depth, index, highlightFirst: byKey)
        case .action, .link: onChoose(row)
        case .note: break
        }
    }

    // MARK: Keys

    /// ↑/↓ move (skipping what can't be chosen, wrapping), Home/End go to
    /// the ends, → or Return opens a submenu and goes into it, Return or
    /// Space runs a row, ← closes the submenu the keys are in, a letter
    /// jumps to the next row starting with it.
    func key(_ key: BarPanelKey) -> Bool {
        guard levels.indices.contains(focus) else { return false }
        let rows = levels[focus].rows
        let selectable = rows.map(\.isSelectable)
        let current = levels[focus].highlighted
        func move(to row: Int?) {
            guard let row else { return }
            // Moving off the row whose submenu is open closes it, as a native menu.
            if intents[focus].open != row { closeSubmenus(below: focus) }
            highlight(focus, row)
        }
        switch key {
        case .down: move(to: MenuListMove.step(from: current, by: 1, selectable: selectable))
        case .up: move(to: MenuListMove.step(from: current, by: -1, selectable: selectable))
        case .home, .pageUp: move(to: MenuListMove.first(selectable: selectable))
        case .end, .pageDown: move(to: MenuListMove.last(selectable: selectable))
        case .right:
            guard let current else {
                move(to: MenuListMove.first(selectable: selectable))
                return true
            }
            if rows[current].kind != .action { activate(focus, current, byKey: true) }
        case .left:
            if focus > 0 {
                let parent = focus - 1
                closeSubmenus(below: parent)
                focus = parent
            } else if !closeSubmenus(below: 0) {
                return false
            }
        case .enter, .space:
            guard let current else { return false }
            activate(focus, current, byKey: true)
        case .character(let letter):
            guard let row = MenuListMove.jump(to: letter, from: current, titles: rows.map(\.title),
                                              selectable: selectable) else { return false }
            move(to: row)
        }
        return true
    }

    /// Escape: the deepest open submenu closes. False with none open (the
    /// menu itself is then put away by its host).
    func escape() -> Bool {
        guard levels.count > 1 else { return false }
        let parent = levels.count - 2
        closeSubmenus(below: parent)
        focus = parent
        return true
    }

    // MARK: The pointer

    /// The pointer moved in the panel of `depth`, to `point` in the panel's
    /// coordinates; nil: it left the panel.
    func pointer(_ depth: Int, at point: CGPoint?) {
        guard levels.indices.contains(depth) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let point else {
            pointers[depth] = nil
            intents[depth].pointerAway()
            // Off the menu: only the row whose submenu is open stays lit.
            highlight(depth, intents[depth].open)
            schedule()
            return
        }
        focus = depth
        // It is inside the submenus of every level above: they stay, their
        // opening rows lit.
        for above in 0..<depth {
            intents[above].pointerInSubmenu()
            highlight(above, intents[above].open)
        }
        let last = pointers[depth]
        pointers[depth] = point
        let level = levels[depth]
        if let row = level.layout.row(at: point), level.rows[row].isSelectable {
            let dx = last.map { point.x - $0.x } ?? 0
            let toward = submenuOnLeft[depth] ? dx < 0 : dx > 0
            highlight(depth, row)
            intents[depth].pointer(over: row, opens: level.rows[row].children != nil, towardSubmenu: toward, now: now)
        } else {
            intents[depth].pointerAway()
        }
        schedule()
    }

    /// A click in the panel of `depth`.
    func click(_ depth: Int, at point: CGPoint) {
        guard levels.indices.contains(depth), let row = levels[depth].layout.row(at: point),
              levels[depth].rows[row].isSelectable else { return }
        focus = depth
        highlight(depth, row)
        activate(depth, row, byKey: false)
    }

    /// VoiceOver's "press" on a row.
    func press(_ depth: Int, _ row: Int) {
        focus = depth
        highlight(depth, row)
        activate(depth, row, byKey: true)
    }

    // MARK: Timing

    /// One timer, for the earliest thing any level waits for.
    private func schedule() {
        cancelTimer()
        guard let due = intents.compactMap(\.due).min() else { return }
        let delay = max(0, due - ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        // `.common`: it must fire while the pointer is tracked too.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func fire() {
        timer = nil
        let now = ProcessInfo.processInfo.systemUptime
        for depth in intents.indices {
            // `fire` has set the intent's own state; the levels follow.
            guard let change = intents[depth].fire(now: now) else { continue }
            switch change {
            case .open(let row):
                truncate(to: depth)
                intents[depth].set(open: nil)
                openSubmenu(depth, row, highlightFirst: false)
            case .close:
                closeSubmenus(below: depth)
            }
            // The levels below are new or gone: nothing of theirs is due.
            break
        }
        schedule()
    }
}

// MARK: Views

/// One level of a menu as a panel: `level` 0 is the menu, the others its
/// open submenus (side panels). Draws nothing for a level that isn't open.
struct MenuListPanel: View {
    @ObservedObject var model: MenuListModel
    let level: Int

    var body: some View {
        if model.levels.indices.contains(level) {
            let shown = model.levels[level]
            BarPanel(width: shown.layout.width) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.rows.enumerated()), id: \.element.id) { index, row in
                        if MenuListLayout.showsRule(index, separators: shown.rows.map(\.separator)) {
                            PanelRule().padding(.vertical, GroveSpace.s4)
                        }
                        MenuListRowView(row: row, height: shown.layout.rows[index].height, icons: shown.icons,
                                        highlighted: shown.highlighted == index,
                                        checked: model.checked.contains(row.id)) {
                            model.press(level, index)
                        }
                    }
                }
                // As `PanelRows`: the rows' own 4 pt is part of the inset.
                .padding(.vertical, -GroveSpace.s4)
            }
            // The pointer is followed by AppKit, over the whole panel: a
            // side panel never has the keyboard, and SwiftUI's hover and
            // buttons want a key window.
            .overlay(MenuListPointer(moved: { model.pointer(level, at: $0) },
                                     clicked: { model.click(level, at: $0) }))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(level == 0 ? "Menu" : "Submenu")
        }
    }
}

/// A menu's row: `PanelRow`'s measures and fill, lit by the model's
/// highlight (the pointer's or the keys') instead of its own hover.
private struct MenuListRowView: View {
    let row: MenuListRow
    let height: CGFloat
    let icons: Bool
    let highlighted: Bool
    let checked: Bool
    let press: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    var body: some View {
        if row.isSelectable {
            HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
                if icons {
                    // A row without an icon keeps the column, so titles line up.
                    Group {
                        if let icon = row.icon { GroveIcon(icon, size: GroveType.label) } else { Color.clear.frame(height: 1) }
                    }
                    .foregroundStyle(theme.quiet)
                    .frame(width: PanelMetrics.iconColumn)
                }
                Text(row.title).truncationMode(.tail)
                Spacer(minLength: 0)
                if checked { GroveIcon(.current, size: GroveType.label).foregroundStyle(Color(theme.green)) }
                if row.coreKind.showsChevron { GroveIcon(.forward, size: GroveType.body).foregroundStyle(theme.quiet) }
            }
            .font(GroveFont.mono(GroveType.label))
            .lineLimit(1)
            .padding(.horizontal, GroveSpace.s8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .background(highlighted ? theme.hoverFill(on: surface) : .clear,
                        in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control, when: highlighted)
            .padding(.horizontal, -GroveSpace.s8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.title)
            .accessibilityValue(checked ? "checked" : "")
            .accessibilityHint(row.children != nil ? "submenu" : "")
            .accessibilityAddTraits(highlighted ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, press)
        } else {
            Text(row.title)
                .font(GroveFont.mono(GroveType.label))
                .foregroundStyle(theme.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        }
    }
}

/// Follows the pointer and the clicks over a menu's panel, in the panel's
/// coordinates (y down), whether or not its window has the keyboard.
private struct MenuListPointer: NSViewRepresentable {
    let moved: (CGPoint?) -> Void
    let clicked: (CGPoint) -> Void

    func makeNSView(context: Context) -> MenuListPointerView {
        let view = MenuListPointerView()
        view.moved = moved
        view.clicked = clicked
        return view
    }

    func updateNSView(_ view: MenuListPointerView, context: Context) {
        view.moved = moved
        view.clicked = clicked
    }
}

final class MenuListPointerView: NSView {
    var moved: (CGPoint?) -> Void = { _ in }
    var clicked: (CGPoint) -> Void = { _ in }
    private var area: NSTrackingArea?

    override var isFlipped: Bool { true }
    // A click in a panel that isn't key counts at once.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The rows under it speak for themselves.
    override func isAccessibilityElement() -> Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    private func place(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseEntered(with event: NSEvent) { moved(place(event)) }
    override func mouseMoved(with event: NSEvent) { moved(place(event)) }
    override func mouseExited(with event: NSEvent) { moved(nil) }
    // Press, drag and release chooses too, as in a native menu.
    override func mouseDown(with event: NSEvent) { moved(place(event)) }
    override func mouseDragged(with event: NSEvent) {
        let point = place(event)
        moved(bounds.contains(point) ? point : nil)
    }

    override func mouseUp(with event: NSEvent) {
        let point = place(event)
        if bounds.contains(point) { clicked(point) }
    }
}
