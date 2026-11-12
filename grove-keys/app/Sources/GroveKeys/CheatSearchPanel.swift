import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The cheat sheet to search in (`grovekeys://cheatsheet`, Hyper + K, Show
/// cheat sheet): every key Grove relies on, in sections, filtered as you
/// type. ↑/↓ move across the rows, Return or a click runs the row where it
/// can be run (a launcher, a binding) and closes, as in the launcher; a click
/// on a row that can't be run selects it. Escape or a click outside the card
/// closes. The panel, the field, the card and the rows are GroveUI's key
/// panel, as the launcher's; the sections, the two columns and what Return
/// runs are here.
@MainActor
final class CheatSearchPanel: ObservableObject {
    static let shared = CheatSearchPanel()

    @Published var query = "" {
        didSet { refilter(keepingSelection: false) }
    }
    @Published private(set) var results: [CheatSection] = []
    /// Over every row of both columns, in the sections' order.
    @Published private(set) var selection = KeyPanelSelection<String>()

    private var sections: [CheatSection] = []
    private let host = KeyPanelHost { PointerMenu.shared.previousApp }
    /// Counts openings, so Ghostty's keys asked for by an earlier one are dropped.
    private var opening = 0

    func toggle() {
        if host.isOpen {
            host.close()
        } else if !host.closedByItsOwnLink() {
            open()
        }
    }

    private func open() {
        let keys = AppModel.shared.keys
        sections = Self.sections(keys, ghostty: [])
        query = ""
        guard host.open(CheatSearchView(sheet: self, model: AppModel.shared)) else { return }
        opening += 1
        let opening = self.opening
        // Ghostty is asked once per opening, off the main thread; if it
        // doesn't answer within a second, the sheet has no Ghostty section.
        DispatchQueue.global(qos: .userInitiated).async {
            let listing = Subprocess.run(GhosttyKeybinds.binary, GhosttyKeybinds.arguments, timeout: 1)
            guard listing.status == 0 else { return }
            let rows = GhosttyKeybinds.rows(listing: listing.output)
            DispatchQueue.main.async { [self] in
                guard opening == self.opening, host.isOpen else { return }
                sections = Self.sections(keys, ghostty: rows)
                refilter(keepingSelection: true)
            }
        }
    }

    private static func sections(_ keys: KeysFile, ghostty: [CheatRow]) -> [CheatSection] {
        CheatSheet.sections(keys: keys, ghostty: ghostty) { Launcher.appName(bundleID: $0) }
    }

    func close() {
        host.close()
    }

    func move(_ step: Int) {
        selection.move(step)
    }

    /// A click: the row is run, as Return would (the launcher's rule); one
    /// that has nothing to run is only selected, and the sheet stays.
    func click(_ row: CheatRow) {
        selection.select(row.id)
        if row.action != .none { runSelection() }
    }

    func runSelection() {
        guard let id = selection.selected,
              let row = results.flatMap(\.rows).first(where: { $0.id == id }) else { return }
        host.close(handBack: !row.action.takesFocus)
        switch row.action {
        case .none: break
        case .launch(let bundleID): _ = Launcher.open(bundleID: bundleID)
        case .run(let steps): Self.run(steps, row: row.keys + " " + row.text)
        }
    }

    /// A binding's commands. A link is answered at once; the AeroSpace and
    /// shell commands follow in order, off the main thread, after a moment:
    /// they act on the focused window, and the app that was in front must
    /// have the keyboard back by then.
    private static func run(_ steps: [CheatStep], row: String) {
        for case .link(let link) in steps { Links.answer(link) }
        let commands = steps.filter { step in
            if case .link = step { return false }
            return true
        }
        guard !commands.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
            let aerospace = AeroSpaceCLI(timeout: 2)
            for command in commands {
                switch command {
                case .aerospace(let arguments): aerospace.run(arguments)
                case .shell(let shell): MenuShell.spawn(shell, row: row)
                case .link: break  // answered above
                }
            }
        }
    }

    private func refilter(keepingSelection: Bool) {
        results = CheatSheet.filter(sections, query)
        selection.show(results.flatMap(\.rows).map(\.id), keepingSelection: keepingSelection)
    }
}

/// The sheet in GroveUI's key panel: the sections in two columns (keys.toml's
/// on the left, the fixed lists on the right), each scrolling on its own.
/// The card keeps its size as the rows are filtered.
private struct CheatSearchView: View {
    @ObservedObject var sheet: CheatSearchPanel
    @ObservedObject var model: AppModel
    static let cardWidth: CGFloat = 1040
    static let cardHeight: CGFloat = 940
    static let rowHeight: CGFloat = 26
    static let keysWidth: CGFloat = 136

    var body: some View {
        let theme = model.colors
        KeyPanelView(theme: theme, placement: .centred(width: Self.cardWidth, height: Self.cardHeight),
                     query: sheet.query, placeholder: "Type to find a key",
                     onQuery: { sheet.query = $0 }, onMove: sheet.move,
                     onReturn: sheet.runSelection, onClose: sheet.close) {
            Text("↑↓ move · ↩ run · esc close")
                .font(GroveFont.mono(GroveType.body))
                .foregroundStyle(theme.quiet)
                .fixedSize()
        } content: {
            let columns = [sheet.results.filter { !$0.fixed }, sheet.results.filter(\.fixed)].filter { !$0.isEmpty }
            if columns.isEmpty {
                Text("No key matches")
                    .foregroundStyle(theme.quiet)
                    .padding(GroveSpace.s16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, sections in
                        if index > 0 { Rectangle().fill(theme.line).frame(width: 1) }
                        column(sections, theme)
                    }
                }
            }
        }
    }

    private func column(_ sections: [CheatSection], _ theme: ThemeColors) -> some View {
        KeyPanelList(sections.map { KeyPanelGroup(id: $0.id, title: $0.title, rows: $0.rows) },
                     selection: sheet.selection.selected, rowHeight: Self.rowHeight,
                     insets: EdgeInsets(top: 0, leading: GroveSpace.s8, bottom: GroveSpace.s8, trailing: GroveSpace.s8),
                     label: { $0.keys + ", " + $0.text }, onClick: sheet.click) { title in
            Text(title)
                .font(GroveFont.mono(GroveType.body, .semibold))
                .foregroundStyle(theme.quiet)
                .padding(.horizontal, GroveSpace.s8)
                .padding(.top, GroveSpace.s12)
                .padding(.bottom, GroveSpace.s4)
        } row: { row, selected in
            self.row(row, selected: selected, theme)
        }
        .frame(maxWidth: .infinity)
    }

    /// The key in a cap, as the keyboard's; what it does; ↩ on the selected
    /// row when Return runs it.
    private func row(_ row: CheatRow, selected: Bool, _ theme: ThemeColors) -> some View {
        HStack(spacing: GroveSpace.s12) {
            Text(row.keys)
                .font(GroveFont.mono(GroveType.body, .medium))
                .foregroundStyle(Color(theme.fg))
                .lineLimit(1)
                .padding(.horizontal, GroveSpace.s8)
                .frame(height: 20)
                .background(Color(theme.bg1), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.capLine(dark: theme.bg2), lineWidth: 1))
                .frame(width: Self.keysWidth, alignment: .leading)
            Text(row.text)
                .foregroundStyle(Color(theme.fg))
                .lineLimit(1)
            Spacer(minLength: 0)
            if selected, row.action != .none {
                Text("↩").foregroundStyle(theme.quiet)
            }
        }
    }
}
