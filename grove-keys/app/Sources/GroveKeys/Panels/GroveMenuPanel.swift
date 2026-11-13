import AppKit
import GroveKeysCore
import GroveUI
import SwiftUI

/// The Grove menu's state: the menu's files as rows of a `MenuListModel`,
/// their `checked` tests, and what choosing a row does.
///
/// The rows are the ones the launcher lists and `grovekeys://menu/<id>`
/// runs: `menu.toml` with `menu.local.toml` over it and Grove Keys' own
/// items in place of the `keys` builtin, read at every opening (an edit
/// shows the next time). A broken file is a note at the top, as it was in
/// the native menu.
@MainActor
final class GroveMenuModel: ObservableObject, BarPanelWithSides {
    /// A submenu's id to open the menu at, once: set by `grovekeys://menu/<id>`
    /// just before it shows the panel.
    static var openAt: String?

    let list = MenuListModel(width: GroveMenuPanel.width, icons: true)
    var link = BarPanelLink()
    private var menu = GroveMenu(rows: [])
    /// Which opening the running `checked` tests belong to: a tick that
    /// arrives after the menu closed (or opened again) is dropped.
    private var opening = 0
    private let isSample: Bool

    init(_ data: BarPanelData) {
        isSample = data == .sample
        list.onChoose = { [weak self] in self?.choose($0) }
        list.onShow = { [weak self] in self?.test($0) }
        list.onLevels = { [weak self] in self?.link.sidesChanged() }
        if isSample { showSample() }
    }

    /// The submenus' panels, beside the menu.
    var sides: [BarPanelSide] {
        list.sides { [list] depth in AnyView(MenuListPanel(model: list, level: depth)) }
    }

    func start() {
        opening += 1
        menu = PointerMenu.shared.groveMenu()
        list.show(Self.rows(menu.rows))
        if let id = Self.openAt {
            Self.openAt = nil
            list.open(path: menu.path(to: id))
        }
    }

    /// Nothing is left running: the hover timer goes with the rows, and a
    /// `checked` test still out (0.5 s at most) reports to no one.
    func stop() {
        opening += 1
        list.clear()
    }

    func key(_ key: BarPanelKey) -> Bool { list.key(key) }
    func escape() -> Bool { list.escape() }

    // MARK: Rows

    /// The menu's rows as the list draws them. An icon is drawn when its
    /// name is one of Grove's (`GroveIcon.Name`); any other name is no icon.
    static func rows(_ rows: [GroveMenuRow]) -> [MenuListRow] {
        var notes = 0
        func convert(_ rows: [GroveMenuRow]) -> [MenuListRow] {
            rows.map { row in
                let kind: MenuListRow.Kind
                var id = row.id
                switch MenuListRowKind(row) {
                case .note:
                    notes += 1
                    id = "note \(notes)"   // a row's id has no space
                    kind = .note
                case .submenu: kind = .submenu(convert(row.children))
                case .link: kind = .link
                case .action: kind = .action
                }
                return MenuListRow(id: id, title: row.title, icon: row.icon.flatMap(GroveIcon.Name.init(rawValue:)),
                                   separator: row.separator, kind: kind)
            }
        }
        return convert(rows)
    }

    /// The `checked` tests of a level just shown: all at once, off the main
    /// thread, each with its 0.5 s limit; a row is ticked when its test
    /// succeeds.
    private func test(_ rows: [MenuListRow]) {
        guard !isSample else { return }
        let tests = rows.compactMap { row in
            menu.row(id: row.id)?.checked.map { (id: row.id, command: $0) }
        }
        let opening = self.opening
        CheckedTests.run(tests) { [weak self] id in
            guard let self, self.opening == opening else { return }
            self.list.checked.insert(id)
        }
    }

    // MARK: Choosing

    /// Does what the row says, as `MenuRunner` does for the launcher. The
    /// panel is put away first; the app that was in front keeps the
    /// keyboard unless the row brings something forward itself.
    private func choose(_ chosen: MenuListRow) {
        guard let row = menu.row(id: chosen.id), let action = row.action else { return }
        let panel = link.actions
        if action == .builtin(.globalMenu) {
            // The front app's own menus: only macOS can draw them. The
            // native menu takes the panel's place, corner on corner.
            let corner = link.frame().map { NSPoint(x: $0.minX, y: $0.maxY) }
            panel.leave { PointerMenu.shared.showAppMenu(at: corner) }
        } else if action.takesFocus {
            panel.leave { MenuRunner.run(action, title: row.title) }
        } else {
            panel.close()
            MenuRunner.run(action, title: row.title)
        }
    }

    // MARK: The sample

    /// The shipped menu's shape with fixed rows, for `--render-panel`:
    /// "Appearance" highlighted. `GROVE_MENU_OPEN=<row id>` draws the
    /// submenus down to that row open beside it (`appearance`,
    /// `appearance.dark-medium`); `GROVE_MENU_CHECKED=<row id>` moves the
    /// tick (default `appearance.dark-medium`); `GROVE_MENU_BROKEN=1` draws
    /// the menu as it is with an error in `menu.local.toml` and Grove Keys
    /// missing a permission (the notes: a first row, the Grove Keys submenu).
    private func showSample() {
        let environment = ProcessInfo.processInfo.environment
        let broken = !(environment["GROVE_MENU_BROKEN"] ?? "").isEmpty
        menu = GroveMenu.load(main: .success(Self.sample),
                              local: broken ? .success("[learn.mine]\ntitle = \"Mine\"\nrun = \"x\"\nicons = \"book\"\n") : nil)
            .expandingKeys(KeysMenuItem.items(
                accessibility: !broken, inputMonitoring: true,
                redLine: broken ? "keys.toml line 12: unknown key \"hyperr\"" : nil, offersRestart: broken,
                paused: false))
        list.show(Self.rows(menu.rows))
        list.checked = [environment["GROVE_MENU_CHECKED"].flatMap { $0.isEmpty ? nil : $0 } ?? "appearance.dark-medium"]
        if let id = environment["GROVE_MENU_OPEN"], !id.isEmpty {
            list.open(path: menu.path(to: id))
        } else {
            list.highlight(first: true)
        }
    }

    private static let sample = """
        [appearance]
        title = "Appearance"
        icon = "paintpalette"
        [appearance.gallery]
        title = "Grove Themes…"
        open = "grovethemes://gallery"
        [appearance.dark-hard]
        title = "Dark Hard"
        separator = true
        run = "true"
        [appearance.dark-medium]
        title = "Dark Medium"
        run = "true"
        [appearance.dark-soft]
        title = "Dark Soft"
        run = "true"
        [appearance.light-hard]
        title = "Light Hard"
        run = "true"
        [appearance.light-medium]
        title = "Light Medium"
        run = "true"
        [appearance.light-soft]
        title = "Light Soft"
        run = "true"
        [keys]
        title = "Grove Keys"
        icon = "keyboard"
        builtin = "keys"
        [update]
        title = "Update"
        icon = "arrow.triangle.2.circlepath"
        [update.check]
        title = "Check"
        run = "true"
        [update.grove]
        title = "Update Grove"
        run = "true"
        [update.install]
        title = "Run the Installer"
        run = "true"
        [learn]
        title = "Learn"
        icon = "book"
        [learn.keys]
        title = "Keybindings"
        run = "true"
        [learn.manual]
        title = "The Grove Manual"
        separator = true
        run = "true"
        [about]
        title = "About"
        icon = "info.circle"
        run = "true"
        [system]
        title = "System"
        icon = "power"
        [system.settings]
        title = "System Settings…"
        run = "true"
        [system.lock]
        title = "Lock"
        separator = true
        builtin = "lock"
        [global-menu]
        title = "Global Menu"
        icon = "menubar.rectangle"
        separator = true
        builtin = "global-menu"
        """
}

/// The Grove menu (the pine's dropdown; variant B of the approved
/// mock-ups): the menu file's rows in the panels' frame, an icon before
/// each top-level row, a submenu as a second panel beside the first.
/// "Global Menu" stays native: its row puts the panel away and pops the
/// front app's menus where the panel was.
struct GroveMenuPanel: View {
    static let registration = BarPanelRegistration("grove", pill: "pill.grove", anchor: .leading, width: width,
                                                   model: GroveMenuModel.init) { GroveMenuPanel(model: $0) }

    /// The approved mock-up's.
    static let width: CGFloat = 200

    let model: GroveMenuModel

    var body: some View {
        MenuListPanel(model: model.list, level: 0)
    }
}
