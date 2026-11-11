import AppKit
import GroveKeysCore
import GroveThemesCore
import SwiftUI

/// The palette (`grovekeys://palette`, Hyper + Space): every row of the Grove
/// menu that does something, in a panel over the focused screen, filtered as
/// you type. ↑/↓ move, Return runs the row and closes, Escape or a click
/// outside the card closes.
///
/// The panel is non-activating and can be key, so it takes the keyboard
/// without Grove Keys coming forward; `open` may bring Grove Keys forward all
/// the same, so on closing the app that was in front is given the keyboard
/// back, unless the row run brings a window forward itself or the palette
/// closed because another app was clicked.
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
    private var panel: KeyPanel?
    private var handBackTo: pid_t?
    private var observers: [NSObjectProtocol] = []
    /// Counts openings, so a test started by an earlier one ticks nothing.
    private var opening = 0

    func toggle() {
        if panel == nil { open() } else { close() }
    }

    private func open() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        entries = PointerMenu.shared.groveMenu().paletteEntries
        checked = []
        query = ""
        // Grove Keys' own window in front: nothing to hand back.
        handBackTo = NSApp.isActive ? nil : PointerMenu.shared.previousApp
        opening += 1
        let opening = self.opening
        CheckedTests.run(entries.compactMap { entry in entry.checked.map { (id: entry.id, command: $0) } }) { [self] id in
            if opening == self.opening { checked.insert(id) }
        }

        // Below the menu bar, as the cheat sheet.
        let full = screen.frame
        let frame = NSRect(x: full.minX, y: full.minY, width: full.width,
                           height: max(0, screen.visibleFrame.maxY - full.minY))
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: PaletteView(palette: self, model: AppModel.shared))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        // Another window or app took the keyboard (a click elsewhere, ⌘Tab):
        // the palette goes, and the keyboard stays where it went.
        let center = NotificationCenter.default
        for (name, object) in [(NSWindow.didResignKeyNotification, panel as Any?),
                               (NSApplication.didResignActiveNotification, nil)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { _ in
                MainActor.assumeIsolated { PalettePanel.shared.close(handBack: false) }
            })
        }
        // If macOS didn't give a background app's panel the keyboard, Grove
        // Keys comes forward for it, as it does for the pointer menus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            guard self.panel === panel, !panel.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close(handBack: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        panel.orderOut(nil)
        if handBack, let handBackTo {
            NSRunningApplication(processIdentifier: handBackTo)?.activate()
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

    func run(_ entry: PaletteEntry) {
        close(handBack: !entry.action.takesFocus(home: MenuRunner.home))
        MenuRunner.run(entry.action, title: entry.title)
    }

    private func refilter() {
        results = PaletteFilter.filter(entries, query)
        selection = 0
    }
}

/// A borderless panel can't be key unless it says so.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
            PaletteField(palette: palette, theme: theme)
                .padding(.horizontal, 16)
                .frame(height: 46)
            Rectangle().fill(theme.line).frame(height: 1)
            if palette.results.isEmpty {
                Text("No row matches")
                    .foregroundStyle(theme.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: Self.rowHeight + 12)
            } else {
                rows(theme)
            }
        }
        .frame(width: Self.cardWidth)
        .background(Color(theme.bg0).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.line, lineWidth: 1))
        .shadow(color: theme.cardShadow, radius: 30, y: 15)
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
        return HStack(spacing: 8) {
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

/// The palette's text field. AppKit's, so that it is the panel's first
/// responder from the start and ↑/↓, Return and Escape reach the palette
/// while the typing stays in the field.
private struct PaletteField: NSViewRepresentable {
    @ObservedObject var palette: PalettePanel
    let theme: ThemeColors

    func makeCoordinator() -> Coordinator { Coordinator(palette: palette) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FirstResponderField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = GroveFont.monoNS(15)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != palette.query { field.stringValue = palette.query }
        field.textColor = NSColor(theme.fg)
        field.placeholderAttributedString = NSAttributedString(string: "Type to find a row", attributes: [
            .foregroundColor: NSColor(theme.dim), .font: GroveFont.monoNS(15),
        ])
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let palette: PalettePanel
        init(palette: PalettePanel) { self.palette = palette }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            palette.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): palette.move(-1)
            case #selector(NSResponder.moveDown(_:)): palette.move(1)
            case #selector(NSResponder.insertNewline(_:)): palette.runSelection()
            case #selector(NSResponder.cancelOperation(_:)): palette.close()
            default: return false
            }
            return true
        }
    }
}

private final class FirstResponderField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
