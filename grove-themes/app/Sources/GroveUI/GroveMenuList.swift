import AppKit
import GroveThemesCore
import SwiftUI

// The Grove menu: rows in a panel (the panels' card, its outline, mono
// type), a submenu as a second panel beside it, one highlighted row per
// level shared by the pointer and the keys. Grove Keys' bar Grove menu is
// built from it, and so is every in-window menu: give `GroveMenuListModel`
// its rows, draw `GroveMenuListPanel(model:level: 0)` (and a panel per open
// submenu, `submenus`) and pass on the keys.
//
// Hand-built on purpose: a native menu (`NSMenu`, `Menu`) can't take the
// panels' frame, outline, font or place (the owner's decision, spec
// 2026-11-12-bar-panels-design §2; for every in-window menu, spec
// 2026-11-13-grove-context-menus-design), and `KeyPanelList` has no
// levels. What is pure (the keys' moves, the hover timing, the rows'
// rectangles, a submenu's place) is `GroveThemesCore/MenuListRules.swift`,
// tested.

/// What is drawn before a row's title.
public enum GroveMenuListIcon: Equatable {
    /// One of Grove's icons.
    case symbol(GroveIcon.Name)
    /// An image of its own (an app's icon), drawn in the icon column's square.
    case image(NSImage)
}

/// One row of a menu.
public struct GroveMenuListRow: Identifiable, Equatable {
    public enum Kind: Equatable {
        /// Choosing it does something.
        case action
        /// The same, for a row that opens something that is not one of
        /// these panels (the native Global Menu): → opens it too; drawn
        /// without the chevron (`MenuListRowKind.showsChevron`).
        case link
        /// It opens these rows in a panel beside this one.
        case submenu([GroveMenuListRow])
        /// Text that can't be chosen (an error, a warning's line).
        case note
    }

    /// Unique in the whole menu: what `onChoose` and `checked` know a row by.
    public var id: String
    public var title: String
    /// Drawn before the title, in a column every row of the level keeps
    /// (at any level: a level keeps the column when one of its rows has an
    /// icon, and the menu's own level when the model is told to).
    public var icon: GroveMenuListIcon?
    /// A line above the row (not drawn above a level's first row).
    public var separator: Bool
    public var kind: Kind
    /// A disabled row is drawn quiet; the keys and the pointer pass it by
    /// and it can't be chosen.
    public var enabled: Bool
    /// Ticked when the menu is shown (the model's `checked` can add more).
    public var checked: Bool
    /// A submenu's rows, asked for each time it opens (Open With asks
    /// NSWorkspace then); they replace the kind's own rows. Nil: the kind's
    /// rows. A filled submenu with no rows doesn't open. Not compared by `==`.
    public var fill: (() -> [GroveMenuListRow])?

    public init(id: String, title: String, icon: GroveMenuListIcon? = nil, separator: Bool = false,
                kind: Kind = .action, enabled: Bool = true, checked: Bool = false,
                fill: (() -> [GroveMenuListRow])? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.separator = separator
        self.kind = kind
        self.enabled = enabled
        self.checked = checked
        self.fill = fill
    }

    /// Everything but `fill` (a function can't be compared).
    public static func == (lhs: GroveMenuListRow, rhs: GroveMenuListRow) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.icon == rhs.icon && lhs.separator == rhs.separator
            && lhs.kind == rhs.kind && lhs.enabled == rhs.enabled && lhs.checked == rhs.checked
    }

    /// The keys, the pointer and type-to-jump stop on it.
    public var isSelectable: Bool { kind != .note && enabled }

    public var children: [GroveMenuListRow]? {
        if case .submenu(let rows) = kind { return rows }
        return nil
    }

    /// The kind without its rows, for what Core decides about it.
    public var coreKind: MenuListRowKind {
        switch kind {
        case .action: .action
        case .link: .link
        case .submenu: .submenu
        case .note: .note
        }
    }
}

/// A key as a menu (and a Grove Keys bar panel) is told it.
public enum GroveMenuListKey: Equatable, Sendable {
    case left, right, up, down, home, end, pageUp, pageDown, enter, space
    /// A typed character, lower-cased ("t").
    case character(String)

    /// The key of a key-down event; nil for one pressed with ⌘, ⌃ or ⌥ and
    /// for what is neither a moving key nor a letter or digit.
    public init?(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        case 115: self = .home
        case 119: self = .end
        case 116: self = .pageUp
        case 121: self = .pageDown
        case 36, 76: self = .enter
        case 49: self = .space
        default:
            guard let text = event.charactersIgnoringModifiers?.lowercased(), text.count == 1,
                  let scalar = text.unicodeScalars.first, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
            else { return nil }
            self = .character(text)
        }
    }
}

/// The measures of a menu's panel. Rows have fixed heights, so where each
/// row is can be computed (`MenuListLayout`) rather than read back from the
/// drawn views.
@MainActor
enum GroveMenuListMetrics {
    /// A row: a line of label text and the rows' 4 pt above and below.
    static let row = GroveSpace.s24
    /// A submenu's width, and a popped-up menu's (`GroveMenuList.popUp`),
    /// unless its titles need more (up to `widest`).
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
public final class GroveMenuListModel: ObservableObject {
    public struct Level {
        public let rows: [GroveMenuListRow]
        public let layout: MenuListLayout
        /// Whether the rows keep an icon column.
        public let icons: Bool
        /// The row under the pointer or chosen with the keys.
        public internal(set) var highlighted: Int?
    }

    /// An open submenu's panel, for the host to place beside the panel
    /// before it (`MenuPlacement.submenu`).
    public struct Submenu {
        /// Its level (1 for the menu's own submenu): `GroveMenuListPanel`'s.
        public let depth: Int
        public let size: CGSize
        /// The row it opens from, in the coordinates of the panel before it:
        /// points from that panel's top-left corner, y down.
        public let row: CGRect
        /// From the panel's top to its first row.
        public let firstRow: CGFloat
    }

    /// The menu (0), then each open submenu in order.
    @Published public private(set) var levels: [Level] = []
    /// The ids of the rows to tick: the rows' own `checked` when shown, and
    /// whatever is added while the menu is up.
    @Published public var checked: Set<String> = []

    /// A row that does something was chosen (a click, Return, Space).
    public var onChoose: (GroveMenuListRow) -> Void = { _ in }
    /// A level was shown (the menu, a submenu just opened): the place to
    /// start what its rows need (their `checked` tests).
    public var onShow: ([GroveMenuListRow]) -> Void = { _ in }
    /// The open submenus changed: the host re-places the side panels.
    public var onLevels: () -> Void = {}

    private let width: CGFloat?
    private let icons: Bool
    /// Per level: its submenu's timing, the pointer's last place in it, and
    /// whether its submenu's panel is at its left (no room at the right).
    private var intents: [MenuHoverIntent] = []
    private var pointers: [CGPoint?] = []
    private var submenuOnLeft: [Bool] = []
    /// The level the keys act on.
    private var focus = 0
    private var timer: Timer?

    /// - `width`: the menu's own panel; nil fits its titles, as submenus
    ///   always do.
    /// - `icons`: the menu's rows keep an icon column even when none has an
    ///   icon (a row without one keeps the indent). Any level whose rows
    ///   have an icon keeps one.
    public init(width: CGFloat?, icons: Bool) {
        self.width = width
        self.icons = icons
    }

    // MARK: Showing

    /// Shows `rows` as the menu, nothing open or highlighted.
    public func show(_ rows: [GroveMenuListRow]) {
        cancelTimer()
        checked = Self.checkedIDs(rows)
        levels = [level(rows, depth: 0)]
        intents = [MenuHoverIntent()]
        pointers = [nil]
        submenuOnLeft = [false]
        focus = 0
        onShow(rows)
        onLevels()
    }

    private static func checkedIDs(_ rows: [GroveMenuListRow]) -> Set<String> {
        rows.reduce(into: Set<String>()) { ids, row in
            if row.checked { ids.insert(row.id) }
            if let children = row.children { ids.formUnion(checkedIDs(children)) }
        }
    }

    /// Nothing shown and nothing running (the panel closed).
    public func clear() {
        cancelTimer()
        levels = []
        intents = []
        pointers = []
        submenuOnLeft = []
        focus = 0
    }

    /// Opens the submenus along `ids` (each a row of the level before) and
    /// highlights the last row named; stops at the first id that isn't
    /// there or can't be chosen (a note, a disabled row).
    public func open(path ids: [String]) {
        for id in ids {
            let depth = levels.count - 1
            guard depth >= 0, let index = levels[depth].rows.firstIndex(where: { $0.id == id }),
                  levels[depth].rows[index].isSelectable else { return }
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
    public func highlight(first: Bool) {
        guard levels.indices.contains(focus) else { return }
        let selectable = levels[focus].rows.map(\.isSelectable)
        highlight(focus, first ? MenuListMove.first(selectable: selectable) : MenuListMove.last(selectable: selectable))
    }

    /// The panels the open submenus need, in order.
    public var submenus: [Submenu] {
        (1..<max(levels.count, 1)).compactMap { depth in
            guard let open = intents[depth - 1].open, levels[depth - 1].layout.rows.indices.contains(open) else { return nil }
            return Submenu(depth: depth, size: levels[depth].layout.size, row: levels[depth - 1].layout.rows[open],
                           firstRow: GroveMenuListMetrics.layout.edge)
        }
    }

    /// The row of `depth` whose submenu is open, if one is.
    func openRow(_ depth: Int) -> Int? {
        guard levels.count > depth + 1, intents.indices.contains(depth) else { return nil }
        return intents[depth].open
    }

    /// The host put the submenu of `depth` at the left of the panel before
    /// it (`onLeft`, no room at the right) or at its right: the pointer
    /// moving that way is on its way into it.
    public func placed(_ depth: Int, onLeft: Bool) {
        guard submenuOnLeft.indices.contains(depth - 1) else { return }
        submenuOnLeft[depth - 1] = onLeft
    }

    private func level(_ rows: [GroveMenuListRow], depth: Int) -> Level {
        let icons = (depth == 0 && self.icons) || rows.contains { $0.icon != nil }
        var width = self.width ?? 0
        if depth > 0 || self.width == nil {
            let column = icons ? PanelMetrics.iconColumn + GroveSpace.s8 : 0
            let titles = rows.map {
                GroveMenuListMetrics.width(of: $0.title)
                    + ($0.kind != .note ? column + GroveSpace.s8 + GroveMenuListMetrics.mark : 0)
            }
            width = min(GroveMenuListMetrics.widest,
                        max(GroveMenuListMetrics.submenu, (titles.max() ?? 0) + 2 * PanelMetrics.inset))
        }
        // A note has the whole line (no icon column, no mark) and wraps.
        let heights = rows.map { row in
            row.kind != .note ? GroveMenuListMetrics.row
                : GroveMenuListMetrics.noteHeight(row.title, width: width - 2 * PanelMetrics.inset)
        }
        return Level(rows: rows,
                     layout: MenuListLayout(width: width, heights: heights.map(Double.init),
                                            separators: rows.map(\.separator), metrics: GroveMenuListMetrics.layout),
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
        guard levels.indices.contains(depth), var children = levels[depth].rows[row].children else { return }
        let alreadyOpen = intents[depth].open == row && levels.count > depth + 1
        if !alreadyOpen {
            if let fill = levels[depth].rows[row].fill {
                children = fill()
                guard !children.isEmpty else { return }
                checked.formUnion(Self.checkedIDs(children))
            }
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
        guard row.isSelectable else { return }
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
    /// jumps to the next row starting with it. False: the menu didn't use
    /// the key.
    public func key(_ key: GroveMenuListKey) -> Bool {
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
    public func escape() -> Bool {
        guard levels.count > 1 else { return false }
        let parent = levels.count - 2
        closeSubmenus(below: parent)
        focus = parent
        return true
    }

    // MARK: The pointer

    /// The pointer moved in the panel of `depth`, to `point` in the panel's
    /// coordinates; nil: it left the panel.
    public func pointer(_ depth: Int, at point: CGPoint?) {
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
    public func click(_ depth: Int, at point: CGPoint) {
        guard levels.indices.contains(depth), let row = levels[depth].layout.row(at: point),
              levels[depth].rows[row].isSelectable else { return }
        focus = depth
        highlight(depth, row)
        activate(depth, row, byKey: false)
    }

    /// VoiceOver's "press" on a row.
    public func press(_ depth: Int, _ row: Int) {
        guard levels.indices.contains(depth), levels[depth].rows.indices.contains(row),
              levels[depth].rows[row].isSelectable else { return }
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
public struct GroveMenuListPanel: View {
    @ObservedObject var model: GroveMenuListModel
    let level: Int
    let surface: Surface

    /// `surface`: the card's fill: `.base` (bg0) for the bar's Grove menu,
    /// `.panel` (bg1) for a menu over a window (`GroveMenuList.popUp`).
    public init(model: GroveMenuListModel, level: Int, surface: Surface = .base) {
        self.model = model
        self.level = level
        self.surface = surface
    }

    public var body: some View {
        if model.levels.indices.contains(level) {
            let shown = model.levels[level]
            BarPanel(width: shown.layout.width, surface: surface) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.rows.enumerated()), id: \.element.id) { index, row in
                        if MenuListLayout.showsRule(index, separators: shown.rows.map(\.separator)) {
                            PanelRule().padding(.vertical, GroveSpace.s4)
                        }
                        GroveMenuListRowView(row: row, height: shown.layout.rows[index].height, icons: shown.icons,
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
            .overlay(GroveMenuListPointer(moved: { model.pointer(level, at: $0) },
                                          clicked: { model.click(level, at: $0) }))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(level == 0 ? "Menu" : "Submenu")
        }
    }
}

/// A menu's row: `PanelRow`'s measures and fill, lit by the model's
/// highlight (the pointer's or the keys') instead of its own hover. A
/// disabled row is drawn quiet, title and all.
private struct GroveMenuListRowView: View {
    let row: GroveMenuListRow
    let height: CGFloat
    let icons: Bool
    let highlighted: Bool
    let checked: Bool
    let press: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    var body: some View {
        if row.kind != .note {
            HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
                if icons {
                    // A row without an icon keeps the column, so titles line up.
                    Group {
                        switch row.icon {
                        case .symbol(let name): GroveIcon(name, size: GroveType.label)
                        case .image(let image):
                            Image(nsImage: image).resizable().interpolation(.high)
                                .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + GroveType.label / 3 }
                                .opacity(row.enabled ? 1 : GroveOpacity.disabledImage)
                        case nil: Color.clear.frame(height: 1)
                        }
                    }
                    .foregroundStyle(theme.quiet)
                    .frame(width: PanelMetrics.iconColumn)
                }
                if row.enabled {
                    Text(row.title).truncationMode(.tail)
                } else {
                    Text(row.title).truncationMode(.tail).foregroundStyle(theme.quiet)
                }
                Spacer(minLength: 0)
                // A disabled row's tick is quiet, as its title.
                if checked {
                    GroveIcon(.current, size: GroveType.label)
                        .foregroundStyle(row.enabled ? Color(theme.green) : theme.quiet)
                }
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
            .disabled(!row.enabled)
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
private struct GroveMenuListPointer: NSViewRepresentable {
    let moved: (CGPoint?) -> Void
    let clicked: (CGPoint) -> Void

    func makeNSView(context: Context) -> GroveMenuListPointerView {
        let view = GroveMenuListPointerView()
        view.moved = moved
        view.clicked = clicked
        return view
    }

    func updateNSView(_ view: GroveMenuListPointerView, context: Context) {
        view.moved = moved
        view.clicked = clicked
    }
}

final class GroveMenuListPointerView: NSView {
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
