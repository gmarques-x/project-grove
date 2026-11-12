import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The cheat sheet to search in (`grovekeys://cheatsheet`, Hyper + K, Show
/// cheat sheet): every key Grove relies on, in sections, filtered as you
/// type. ↑/↓ move across the rows, Return runs the row where it can be run
/// (a launcher, a binding) and closes, Escape or a click outside the card
/// closes. The panel and the way the keyboard is handed back are the
/// launcher's (`KeyPanelHost`).
@MainActor
final class CheatSearchPanel: ObservableObject {
    static let shared = CheatSearchPanel()

    @Published var query = "" {
        didSet { refilter(keepingSelection: false) }
    }
    @Published private(set) var results: [CheatSection] = []
    /// The selected row's id.
    @Published private(set) var selection: String?

    private var sections: [CheatSection] = []
    private let host = KeyPanelHost()
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
        let ids = results.flatMap(\.rows).map(\.id)
        guard !ids.isEmpty else { return }
        let at = selection.flatMap(ids.firstIndex(of:)) ?? 0
        selection = ids[min(max(at + step, 0), ids.count - 1)]
    }

    func select(_ row: CheatRow) {
        selection = row.id
    }

    func runSelection() {
        guard let row = results.flatMap(\.rows).first(where: { $0.id == selection }) else { return }
        host.close(handBack: !row.action.takesFocus)
        switch row.action {
        case .none: break
        case .launch(let bundleID): _ = Launcher.open(bundleID: bundleID)
        case .run(let steps): Self.run(steps)
        }
    }

    /// A binding's commands. A link is answered at once; the AeroSpace and
    /// shell commands follow in order, off the main thread, after a moment:
    /// they act on the focused window, and the app that was in front must
    /// have the keyboard back by then.
    private static func run(_ steps: [CheatStep]) {
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
                case .shell(let shell): MenuShell.spawn(shell)
                case .link: break  // answered above
                }
            }
        }
    }

    private func refilter(keepingSelection: Bool) {
        results = CheatSheet.filter(sections, query)
        let rows = results.flatMap(\.rows)
        if !keepingSelection || !rows.contains(where: { $0.id == selection }) {
            selection = rows.first?.id
        }
    }
}

/// The scrim and the card: the field, a line, the sections in two columns
/// (keys.toml's on the left, the fixed lists on the right), each scrolling
/// on its own. The card keeps its size as the rows are filtered.
private struct CheatSearchView: View {
    @ObservedObject var sheet: CheatSearchPanel
    @ObservedObject var model: AppModel
    static let cardWidth: CGFloat = 1040
    static let cardHeight: CGFloat = 940
    static let rowHeight: CGFloat = 26
    static let keysWidth: CGFloat = 136

    var body: some View {
        let theme = model.colors
        GeometryReader { screen in
            ZStack {
                theme.scrim
                    .contentShape(Rectangle())
                    .onTapGesture { sheet.close() }
                card(theme)
                    .frame(width: min(Self.cardWidth, screen.size.width - 48),
                           height: min(Self.cardHeight, screen.size.height - 96))
            }
        }
        .font(GroveFont.mono(GroveType.heading))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private func card(_ theme: ThemeColors) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: GroveSpace.s12) {
                FilterField(text: sheet.query, placeholder: "Type to find a key", theme: theme,
                            onChange: { sheet.query = $0 }, onMove: sheet.move,
                            onReturn: sheet.runSelection, onEscape: sheet.close)
                Text("↑↓ move · ↩ run · esc close")
                    .font(GroveFont.mono(GroveType.body))
                    .foregroundStyle(theme.quiet)
                    .fixedSize()
            }
            .padding(.horizontal, GroveSpace.s16)
            .frame(height: 46)
            Rectangle().fill(theme.line).frame(height: 1)
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
        .sheetCard(theme)
    }

    private func column(_ sections: [CheatSection], _ theme: ThemeColors) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(GroveFont.mono(GroveType.body, .semibold))
                            .foregroundStyle(theme.quiet)
                            .padding(.horizontal, 10)
                            .padding(.top, GroveSpace.s12)
                            .padding(.bottom, GroveSpace.s4)
                        ForEach(section.rows) { row in
                            self.row(row, selected: row.id == sheet.selection, theme)
                                .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, GroveSpace.s8)
            }
            .frame(maxWidth: .infinity)
            // A row of the other column isn't here, and nothing scrolls.
            .onChange(of: sheet.selection) { _, now in
                if let now { scroll.scrollTo(now) }
            }
        }
    }

    /// The key in a cap, as the keyboard's; what it does; ↩ on the selected
    /// row when Return runs it.
    private func row(_ row: CheatRow, selected: Bool, _ theme: ThemeColors) -> some View {
        HStack(spacing: 10) {
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
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(selected ? Color(theme.bg2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .lightOutline(cornerRadius: 8, when: selected)
        .contentShape(Rectangle())
        .onTapGesture { sheet.select(row) }
    }
}
