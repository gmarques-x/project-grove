import AppKit
import Combine
import GroveKeysCore
import GroveThemesCore
import GroveUI
import os
import SwiftUI
import UniformTypeIdentifiers

// The tray pill's dropdown (spec 2026-11-14-bar-tray-design): the other
// apps' menu-bar items, which the Grove bar covers. One row per item, left to
// right (app icon, app name, the item's own text quiet at the right); a
// "Hidden (n)" disclosure, collapsed, with the hidden rows in quiet ink; and
// "Menu Bar Settings…". A click (or Return) closes the panel and presses the
// item (`TrayPresser`); a right-click opens the row's Grove menu (Open, Hide
// from tray or Show in tray, Bring <App> forward). The listing is
// `TrayWatcher`'s; what the rows are and how the keys move is
// GroveKeysCore's (`TrayList`).

/// The tray panel's state. Live, it shows `TrayWatcher.shared`'s last
/// listing at once and asks for a fresh one, which replaces it in place;
/// `.sample` is fixed data for `--render-panel` (GROVE_TRAY_SAMPLE) and never
/// lists, reads or presses anything.
@MainActor
final class TrayModel: ObservableObject, BarPanelWithSides {
    /// What the rows are; nil until the first listing is in.
    @Published private(set) var list: TrayList?
    /// Grove Keys has Accessibility (without it there are no items).
    @Published private(set) var accessible = true
    /// The hidden rows are shown. Collapsed at each opening.
    @Published private(set) var expanded = false
    /// The row (or the disclosure) ↑, ↓ or a letter lit; Return opens it.
    @Published private(set) var lit: TrayList.Entry?

    var link = BarPanelLink()
    /// No side panels: the protocol is for `link`, the host's actions for a
    /// row opened with Return.
    let sides: [BarPanelSide] = []

    private nonisolated static let log = Logger(subsystem: "com.projectgrove.keys", category: "tray")
    /// Presses, one at a time: never the main thread (a hung app can take
    /// seconds) nor the watcher's listing queue.
    private nonisolated static let pressQueue = DispatchQueue(label: "com.projectgrove.keys.tray.press",
                                                              qos: .userInitiated)

    private let live: Bool
    /// The listing `list` was made from: its elements are what a row presses.
    private var listing: TrayWatcher.Listing?
    private var icons: [pid_t: NSImage] = [:]
    private var watching: AnyCancellable?

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            live = true
        case .sample:
            live = false
            let name = ProcessInfo.processInfo.environment["GROVE_TRAY_SAMPLE"] ?? "items"
            let sample = Self.sample(name)
            list = TrayList(items: sample.items, hidden: sample.hidden)
            accessible = name != "noaccess"
            expanded = name == "hidden"
            // The system's generic app icon: a render reads no other app.
            let generic = NSWorkspace.shared.icon(for: .applicationBundle)
            for item in sample.items { icons[item.pid] = generic }
        }
    }

    func start() {
        guard live else { return }
        expanded = false
        lit = nil
        let watcher = TrayWatcher.shared
        if let latest = watcher.latest { take(latest) }
        // `$latest` sends the current value first, then each new one, on the
        // main actor (the watcher sets it there).
        watching = watcher.$latest.dropFirst().sink { [weak self] latest in
            MainActor.assumeIsolated {
                guard let self, let latest else { return }
                self.take(latest)
            }
        }
        watcher.refresh()
    }

    func stop() {
        watching = nil
    }

    /// A listing in: the rows, and the lit row kept while it is still there.
    private func take(_ latest: TrayWatcher.Listing) {
        listing = latest
        accessible = latest.accessible
        let fresh = TrayList(items: latest.items.map(\.0), hidden: latest.hidden)
        for item in fresh.items where icons[item.pid] == nil {
            icons[item.pid] = NSRunningApplication(processIdentifier: item.pid)?.icon
        }
        if fresh != list { list = fresh }
        lit = fresh.kept(lit, expanded: expanded)
    }

    func icon(_ row: TrayRow) -> NSImage? { icons[row.item.pid] }

    // MARK: Actions

    /// The panel closes, then the item is pressed off the main thread; if
    /// nothing opens, its app comes forward (`TrayPresser`). Live only.
    func open(_ id: String) {
        guard live, let row = list?.row(id), let listing, listing.items.indices.contains(row.index) else { return }
        let target = Target(item: listing.items[row.index].1, pid: row.item.pid)
        let name = row.item.appName
        link.actions.leave {}
        Self.pressQueue.async {
            let outcome = TrayPresser.press(target.item, pid: target.pid)
            Self.log.info("pressed \(name, privacy: .public)'s item: \(String(describing: outcome), privacy: .public)")
        }
    }

    /// Hide from tray or Show in tray: the hidden file and the bar's count
    /// follow (`TrayWatcher.setHidden`), keys worked out among this
    /// listing's items. Live only.
    func toggleHidden(_ id: String) {
        guard live, let hidden = list?.toggled(id) else { return }
        TrayWatcher.shared.setHidden(hidden)
    }

    /// The row's app to the front, the panel put away. Live only.
    func bringForward(_ id: String) {
        guard live, let pid = list?.row(id)?.item.pid else { return }
        link.actions.leave { TrayPresser.bringForward(pid) }
    }

    func toggleExpanded() {
        expanded.toggle()
        lit = list?.kept(lit, expanded: expanded) ?? nil
    }

    /// The row's Grove menu.
    func menu(_ id: String) -> [GroveMenuListRow] {
        guard let row = list?.row(id) else { return [] }
        return TrayList.menu(app: row.item.appName, hidden: row.hidden).map {
            GroveMenuListRow(id: $0.rawValue, title: $0.title(app: row.item.appName), separator: $0.separated)
        }
    }

    func choose(_ choice: String, on id: String) {
        switch TrayList.Choice(rawValue: choice) {
        case .open?: open(id)
        case .hide?, .show?: toggleHidden(id)
        case .bringForward?: bringForward(id)
        case nil: break
        }
    }

    // MARK: Keys

    /// ↑ and ↓ light a row (the disclosure too), a letter lights the next
    /// app whose name starts with it, Return opens the lit row or opens and
    /// closes the disclosure.
    func key(_ key: BarPanelKey) -> Bool {
        guard let list, accessible else { return false }
        switch key {
        case .up, .down:
            lit = list.moved(from: lit, by: key == .down ? 1 : -1, expanded: expanded) ?? lit
        case .enter, .space:
            switch lit {
            case .row(let id)?: open(id)
            case .disclosure?: toggleExpanded()
            case nil: return false
            }
        case .character(let letter):
            guard let found = list.jumped(to: letter, from: lit, expanded: expanded) else { return false }
            lit = found
        default:
            return false
        }
        return true
    }

    /// An element carried to the press queue, where alone it is used.
    private struct Target: @unchecked Sendable {
        let item: StatusItemLocator.Item
        let pid: pid_t
    }

    // MARK: The sample

    /// GROVE_TRAY_SAMPLE: `items` (the default: five apps, three hidden),
    /// `hidden` (the same with Hidden open), `noaccess` (no Accessibility
    /// permission), `empty` (nothing in the menu bar). Invented apps only.
    private static func sample(_ name: String) -> (items: [TrayItem], hidden: Set<String>) {
        func item(_ id: String, _ app: String, _ pid: pid_t, title: String? = nil) -> TrayItem {
            TrayItem(bundleID: id, appName: app, pid: pid, title: title, x: Double(pid))
        }
        switch name {
        case "empty", "noaccess": return ([], TrayItems.defaultHidden)
        default:
            let items = [
                item("com.example.vpn", "Example VPN", 1, title: "Example VPN"),
                item("com.example.sync", "Cloud Sync", 2, title: "Cloud Sync\nSync issue"),
                item("com.example.containers", "Containers", 3),
                item("com.example.passwords", "Passwords", 4),
                item("com.example.backup", "Backup", 5, title: "Uploading 3 files and checking the rest of the library"),
                item("com.example.tiles", "Tiles", 6, title: "1"),
                item("com.projectgrove.keys", "Grove Keys", 7),
                item("com.projectgrove.themes", "Grove Themes", 8),
            ]
            return (items, TrayItems.defaultHidden.union(["com.example.tiles#0"]))
        }
    }
}

struct TrayPanel: View {
    static let width: CGFloat = 300
    static let registration = BarPanelRegistration("tray", pill: "pill.tray", width: width,
                                                   model: TrayModel.init) { TrayPanel(model: $0) }

    @ObservedObject var model: TrayModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        BarPanel(width: Self.width) {
            if !model.accessible {
                VStack(alignment: .leading, spacing: GroveSpace.s8) {
                    theme.marked(TrayList.needsAccess, theme.yellow).fixedSize(horizontal: false, vertical: true)
                    PanelButton(TrayList.privacySettings) {
                        if let url = URL(string: WireGuardMenu.privacyURL) { panel.open(url) }
                    }
                    .help("Allow Grove Keys to use Accessibility")
                }
            } else if let list = model.list {
                if list.visible.isEmpty {
                    Text(TrayList.noItems).foregroundStyle(theme.quiet)
                } else {
                    PanelRows {
                        ForEach(list.visible) { row($0) }
                    }
                }
                if !list.hidden.isEmpty {
                    PanelRule()
                    PanelRows {
                        disclosure(list.hidden.count)
                        if model.expanded {
                            ForEach(list.hidden) { row($0) }
                        }
                    }
                }
            } else {
                Text("Reading…").foregroundStyle(theme.quiet)
            }
            PanelRule()
            PanelFooter(TrayList.menuBarSettings, action: menuBarSettings)
                .help("Opens Menu Bar in System Settings, where items are removed")
        }
    }

    private func row(_ row: TrayRow) -> some View {
        TrayRowView(row: row, icon: model.icon(row), lit: model.lit == .row(row.id),
                    open: { model.open(row.id) })
            .groveContextMenu(rows: { model.menu(row.id) }) { model.choose($0, on: row.id) }
    }

    private func disclosure(_ count: Int) -> some View {
        TrayLit(lit: model.lit == .disclosure) {
            PanelRow(action: model.toggleExpanded) {
                GroveIcon(model.expanded ? .menu : .forward, size: GroveType.body)
                    .frame(width: PanelMetrics.iconColumn)
                Text(TrayList.hiddenTitle(count)).font(GroveFont.mono(GroveType.label))
            }
            .foregroundStyle(theme.quiet)
        }
        .accessibilityLabel(TrayList.hiddenTitle(count))
        .accessibilityValue(model.expanded ? "expanded" : "collapsed")
    }

    /// System Settings ▸ Menu Bar; plain System Settings when the link
    /// doesn't open. Nothing in a render.
    private func menuBarSettings() {
        panel.leave {
            guard let url = URL(string: TrayList.menuBarSettingsURL), !NSWorkspace.shared.open(url),
                  let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CloudLinks.systemSettings)
            else { return }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
        }
    }
}

/// One item: its app's icon, the app's name, and the item's own text quiet
/// at the right. A hidden one is drawn in quiet ink, its icon at half
/// strength.
private struct TrayRowView: View {
    let row: TrayRow
    let icon: NSImage?
    let lit: Bool
    let open: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        TrayLit(lit: lit) {
            PanelRow(action: open) {
                // Centred: an icon has no baseline to line up on.
                HStack(alignment: .center, spacing: GroveSpace.s8) {
                    Group {
                        if let icon {
                            Image(nsImage: icon).resizable().interpolation(.high)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                    .opacity(row.hidden ? GroveOpacity.disabledImage : 1)
                    Text(row.item.appName).font(GroveFont.mono(GroveType.label)).truncationMode(.tail)
                        .foregroundStyle(row.hidden ? theme.quiet : Color(theme.fg))
                        .layoutPriority(1)
                    Spacer(minLength: GroveSpace.s8)
                    if let text = row.text {
                        Text(text).foregroundStyle(theme.quiet).truncationMode(.tail)
                    }
                }
            }
        }
        .accessibilityLabel([row.item.appName, row.text].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(row.hidden ? "hidden" : "")
        .help("Opens \(row.item.appName)'s menu")
    }
}

/// The row ↑ and ↓ lit, filled as under the pointer (as the sound panel's
/// output rows; `PanelRow` has no such state yet).
private struct TrayLit<Content: View>: View {
    let lit: Bool
    let content: Content
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    init(lit: Bool, @ViewBuilder content: () -> Content) {
        self.lit = lit
        self.content = content()
    }

    var body: some View {
        content
            .background {
                if lit {
                    RoundedRectangle(cornerRadius: GroveRadius.control).fill(theme.hoverFill(on: surface))
                        .lightOutline(cornerRadius: GroveRadius.control)
                        .padding(.horizontal, -GroveSpace.s8)
                }
            }
            .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
