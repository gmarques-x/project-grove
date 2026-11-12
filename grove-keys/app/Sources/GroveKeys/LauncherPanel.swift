import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The Grove Launcher (⌘Space, `grovekeys://launcher`): the installed apps
/// and every row of the Grove menu that does something, in a panel over the
/// focused screen, filtered as you type (`LauncherFilter`). ↑/↓ move, Return
/// opens the app or runs the row and closes, Escape or a click outside the
/// card closes. macOS has no such control; this is Grove's one.
@MainActor
final class LauncherPanel: ObservableObject {
    static let shared = LauncherPanel()
    /// More than anyone reads; keeps a one-letter search from drawing every app.
    static let most = 50

    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var results: [LauncherItem] = []
    @Published private(set) var selection = 0
    /// The ids of the rows whose `checked` test has succeeded.
    @Published private(set) var checked: Set<String> = []

    private var entries: [LauncherEntry] = []
    /// The apps as last scanned: shown at once, and scanned again (off the
    /// main thread) each time the panel opens.
    private var apps: [InstalledApps.App] = []
    private var scanning = false
    private let icons = NSCache<NSString, NSImage>()
    private let host = KeyPanelHost()
    /// Counts openings, so a test started by an earlier one ticks nothing.
    private var opening = 0

    func toggle() {
        if host.isOpen { close() } else { open() }
    }

    private func open() {
        entries = PointerMenu.shared.groveMenu().launcherEntries
        checked = []
        query = ""
        guard host.open(LauncherView(launcher: self, model: AppModel.shared)) else { return }
        refreshApps()
        opening += 1
        let opening = self.opening
        CheckedTests.run(entries.compactMap { entry in entry.checked.map { (id: entry.id, command: $0) } }) { [self] id in
            if opening == self.opening { checked.insert(id) }
        }
    }

    func close(handBack: Bool = true) {
        host.close(handBack: handBack)
    }

    /// Scans the app folders off the main thread; the list in use stays until
    /// the new one is in. Also run once when Grove Keys starts, so the first
    /// opening has apps.
    func refreshApps() {
        guard !scanning else { return }
        scanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                InstalledApps.scan(folders: InstalledApps.standardFolders(home: home))
            }.value
            scanning = false
            guard scanned != apps else { return }
            apps = scanned
            // Typed already: the list on screen is brought up to date, the selection kept.
            if host.isOpen, !query.isEmpty {
                let selected = results.indices.contains(selection) ? results[selection].id : nil
                results = found(for: query)
                selection = selected.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
            }
        }
    }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + step, 0), results.count - 1)
    }

    func runSelection() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    func run(_ item: LauncherItem) {
        switch item {
        case .app(let app):
            // The app comes forward itself: nothing to hand back.
            close(handBack: false)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration,
                                               completionHandler: nil)
        case .row(let entry):
            close(handBack: !entry.action.takesFocus)
            MenuRunner.run(entry.action, title: entry.title)
        }
    }

    /// The app's icon, as Finder shows it; kept, so a row is looked up once.
    func icon(_ app: InstalledApps.App) -> NSImage {
        if let icon = icons.object(forKey: app.path as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icons.setObject(icon, forKey: app.path as NSString)
        return icon
    }

    private func found(for query: String) -> [LauncherItem] {
        let all = LauncherFilter.filter(rows: entries, apps: apps, query)
        // Nothing typed is the whole Grove menu; a search is cut short.
        return TypedWords(query).isEmpty ? all : Array(all.prefix(Self.most))
    }

    private func refilter() {
        results = found(for: query)
        selection = 0
    }
}

/// The scrim and the card: the field, a line, the rows.
private struct LauncherView: View {
    @ObservedObject var launcher: LauncherPanel
    @ObservedObject var model: AppModel
    static let cardWidth: CGFloat = 560
    static let rowHeight: CGFloat = 30
    static let rowsShown = 10
    static let iconSize: CGFloat = 18

    var body: some View {
        let theme = model.colors
        GeometryReader { screen in
            ZStack(alignment: .top) {
                theme.scrim
                    .contentShape(Rectangle())
                    .onTapGesture { launcher.close() }
                card(theme)
                    // From a fixed height, so the field stays put as the list shrinks.
                    .padding(.top, screen.size.height * 0.22)
            }
        }
        .font(GroveFont.mono(GroveType.heading))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private func card(_ theme: ThemeColors) -> some View {
        VStack(spacing: 0) {
            FilterField(text: launcher.query, placeholder: "Open an app, or find a Grove menu row", theme: theme,
                        onChange: { launcher.query = $0 }, onMove: launcher.move,
                        onReturn: launcher.runSelection, onEscape: { launcher.close() })
                .padding(.horizontal, GroveSpace.s16)
                .frame(height: 46)
            Rectangle().fill(theme.line).frame(height: 1)
            if launcher.results.isEmpty {
                Text("Nothing matches")
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
        // With an app in the list every row keeps the icon's place, so the names line up.
        let icons = launcher.results.contains { if case .app = $0 { true } else { false } }
        return ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(launcher.results.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == launcher.selection, icons: icons, theme)
                            .id(item.id)
                    }
                }
                .padding(6)
            }
            .frame(height: CGFloat(min(launcher.results.count, Self.rowsShown)) * Self.rowHeight + 12)
            .onChange(of: launcher.selection) { _, now in
                if launcher.results.indices.contains(now) { scroll.scrollTo(launcher.results[now].id) }
            }
        }
    }

    /// An app: its icon and name. A Grove menu row, "Appearance › Dark
    /// Medium": the way there quiet, the row's own title in fg.
    private func row(_ item: LauncherItem, selected: Bool, icons: Bool, _ theme: ThemeColors) -> some View {
        HStack(spacing: GroveSpace.s8) {
            switch item {
            case .app(let app):
                Image(nsImage: launcher.icon(app))
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                Text(app.name)
                    .foregroundStyle(Color(theme.fg))
                    .lineLimit(1)
                Spacer(minLength: 0)
            case .row(let entry):
                if icons { Color.clear.frame(width: Self.iconSize, height: Self.iconSize) }
                let way = entry.path.dropLast().map { $0 + " › " }.joined()
                (Text(way).foregroundStyle(theme.quiet) + Text(entry.title).foregroundStyle(Color(theme.fg)))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if launcher.checked.contains(entry.id) {
                    Text("✓").foregroundStyle(theme.ink(theme.green))
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(selected ? Color(theme.bg2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .lightOutline(cornerRadius: 8, when: selected)
        .contentShape(Rectangle())
        .onTapGesture { launcher.run(item) }
    }
}
