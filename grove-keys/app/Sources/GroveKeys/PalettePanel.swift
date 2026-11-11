import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The palette (`grovekeys://palette`, Hyper + Space): every row of the Grove
/// menu that does something, in a panel over the focused screen, filtered as
/// you type. ↑/↓ move, Return runs the row and closes, Escape or a click
/// outside the card closes.
@MainActor
final class PalettePanel: ObservableObject {
    static let shared = PalettePanel()

    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var results: [PaletteEntry] = []
    @Published private(set) var selection = 0
    /// The ids of the rows whose `checked` test has succeeded.
    @Published private(set) var checked: Set<String> = []

    private var entries: [PaletteEntry] = []
    private let host = KeyPanelHost()
    /// Counts openings, so a test started by an earlier one ticks nothing.
    private var opening = 0

    func toggle() {
        if host.isOpen { close() } else { open() }
    }

    private func open() {
        entries = PointerMenu.shared.groveMenu().paletteEntries
        checked = []
        query = ""
        guard host.open(PaletteView(palette: self, model: AppModel.shared)) else { return }
        opening += 1
        let opening = self.opening
        CheckedTests.run(entries.compactMap { entry in entry.checked.map { (id: entry.id, command: $0) } }) { [self] id in
            if opening == self.opening { checked.insert(id) }
        }
    }

    func close(handBack: Bool = true) {
        host.close(handBack: handBack)
    }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + step, 0), results.count - 1)
    }

    func runSelection() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    func run(_ entry: PaletteEntry) {
        close(handBack: !entry.action.takesFocus)
        MenuRunner.run(entry.action, title: entry.title)
    }

    private func refilter() {
        results = PaletteFilter.filter(entries, query)
        selection = 0
    }
}

/// The scrim and the card: the field, a line, the rows.
private struct PaletteView: View {
    @ObservedObject var palette: PalettePanel
    @ObservedObject var model: AppModel
    static let cardWidth: CGFloat = 560
    static let rowHeight: CGFloat = 30
    static let rowsShown = 10

    var body: some View {
        let theme = model.colors
        GeometryReader { screen in
            ZStack(alignment: .top) {
                theme.scrim
                    .contentShape(Rectangle())
                    .onTapGesture { palette.close() }
                card(theme)
                    // From a fixed height, so the field stays put as the list shrinks.
                    .padding(.top, screen.size.height * 0.22)
            }
        }
        .font(GroveFont.mono(13))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private func card(_ theme: ThemeColors) -> some View {
        VStack(spacing: 0) {
            FilterField(text: palette.query, placeholder: "Type to find a row", theme: theme,
                        onChange: { palette.query = $0 }, onMove: palette.move,
                        onReturn: palette.runSelection, onEscape: { palette.close() })
                .padding(.horizontal, GroveSpace.s16)
                .frame(height: 46)
            Rectangle().fill(theme.line).frame(height: 1)
            if palette.results.isEmpty {
                Text("No row matches")
                    .foregroundStyle(theme.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, GroveSpace.s16)
                    .frame(height: Self.rowHeight + 12)
            } else {
                rows(theme)
            }
        }
        .frame(width: Self.cardWidth)
        .sheetCard(theme)
    }

    private func rows(_ theme: ThemeColors) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(palette.results.enumerated()), id: \.element.id) { index, entry in
                        row(entry, selected: index == palette.selection, theme)
                            .id(entry.id)
                    }
                }
                .padding(6)
            }
            .frame(height: CGFloat(min(palette.results.count, Self.rowsShown)) * Self.rowHeight + 12)
            .onChange(of: palette.selection) { _, now in
                if palette.results.indices.contains(now) { scroll.scrollTo(palette.results[now].id) }
            }
        }
    }

    /// "Appearance › Dark Medium": the way there quiet, the row's own title in fg.
    private func row(_ entry: PaletteEntry, selected: Bool, _ theme: ThemeColors) -> some View {
        let way = entry.path.dropLast().map { $0 + " › " }.joined()
        return HStack(spacing: GroveSpace.s8) {
            (Text(way).foregroundStyle(theme.quiet) + Text(entry.title).foregroundStyle(Color(theme.fg)))
                .lineLimit(1)
            Spacer(minLength: 0)
            if palette.checked.contains(entry.id) {
                Text("✓").foregroundStyle(theme.ink(theme.green))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(selected ? Color(theme.bg2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .lightOutline(cornerRadius: 8, when: selected)
        .contentShape(Rectangle())
        .onTapGesture { palette.run(entry) }
    }
}
