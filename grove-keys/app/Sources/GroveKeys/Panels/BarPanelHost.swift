import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// Shows the bar's panels (`grovekeys://panel/<name>`): one at a time, each
/// a borderless, non-activating window hung from its pill, its outline on
/// the tiled windows' border lines (`BarPanelPlacement`). The window takes
/// the keyboard without Grove Keys coming forward.
///
/// A panel closes on Escape, a click anywhere outside it, another app coming
/// forward, a Space change, a change of the screens, `panel/close` (the bar
/// sends it on an AeroSpace workspace change) and its own toggle link. The
/// app that was in front keeps the keyboard throughout; if macOS did bring
/// Grove Keys forward for a link, that app is given it back on closing,
/// unless the panel closed to bring something else forward
/// (`BarPanelActions.leave`).
@MainActor
final class BarPanelHost {
    static let shared = BarPanelHost()

    private var toggle = BarPanelToggle()
    private var current: Open?
    private let bar = BarPill()

    /// One open panel.
    @MainActor
    private final class Open {
        let registration: BarPanelRegistration
        let model: any BarPanelModel
        let window: BarPanelWindow
        let layout = BarPanelLayout()
        let geometry: Geometry
        var handBackTo: pid_t?
        var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
        var monitors: [Any] = []

        init(registration: BarPanelRegistration, model: any BarPanelModel, window: BarPanelWindow,
             geometry: Geometry) {
            self.registration = registration
            self.model = model
            self.window = window
            self.geometry = geometry
        }
    }

    /// What the placement is computed from, read once at opening. In the
    /// window list's coordinates (y down from the main display's top).
    private struct Geometry {
        var pill: CGRect?
        var lines: BorderLines
        var bottom: Double
        var cornerRadius: Double
    }

    var isOpen: Bool { current != nil }

    // MARK: Links

    /// `grovekeys://panel/<name>`: shown, or put away if it is the one open.
    /// A name no panel has is ignored.
    func toggle(_ name: String) {
        guard let registration = BarPanels.named(name) else {
            PointerMenu.shared.handBackAfterLink()
            return
        }
        switch toggle.toggle(name, now: Date()) {
        case .open:
            let handBackTo = current?.handBackTo
            tearDown(handBack: false)
            if !open(registration, handBackTo: handBackTo) { toggle.closed() }
        case .close:
            tearDown(handBack: true)
            // `open` without -g can still bring Grove Keys forward after the link.
            PointerMenu.shared.handBackAfterLink()
        case .nothing:
            PointerMenu.shared.handBackAfterLink()
        }
    }

    /// Puts the open panel away (Escape, `panel/close`, a row chosen).
    /// `handBack: false` when something else was just brought forward.
    func close(handBack: Bool = true) {
        toggle.closed()
        tearDown(handBack: handBack)
    }

    /// The app is quitting: the bar is told now, not on a queue.
    func shutdown() {
        toggle.closed()
        tearDown(handBack: false)
        bar.forget()
    }

    /// A click outside the panel, or the keyboard gone elsewhere: put away,
    /// and remembered, so the click's own toggle link doesn't show it again.
    private func dismissFromOutside() {
        guard current != nil else { return }
        toggle.dismissedFromOutside(now: Date())
        tearDown(handBack: false)
    }

    // MARK: Opening

    private func open(_ registration: BarPanelRegistration, handBackTo inherited: pid_t?) -> Bool {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
            ?? NSScreen.screens.first else { return false }
        let colors = AppModel.shared.colors
        let entry = registration.opened()
        entry.model.start()

        let window = BarPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        // Above the windows and their borders; the panel starts below the
        // bar's strip, so the bar needs no room made.
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)

        let open = Open(registration: registration, model: entry.model, window: window,
                        geometry: Self.geometry(pill: registration.pill, on: screen))
        // Grove Keys' own window in front: nothing to give back.
        open.handBackTo = inherited ?? (NSApp.isActive && NSApp.mainWindow != nil ? nil : PointerMenu.shared.previousApp)

        var actions = BarPanelActions()
        actions.close = { [weak self] in self?.close() }
        actions.leave = { [weak self] action in
            self?.close(handBack: false)
            action()
        }
        let hosting = NSHostingView(rootView: BarPanelRoot(content: entry.view, layout: open.layout,
                                                           app: AppModel.shared, actions: actions))
        // The host sizes the window; the hosting view must not.
        hosting.sizingOptions = []
        window.contentView = hosting
        current = open

        // Placed for the size the content asks for now, measured on its own
        // (the root view fills whatever window it is given); `layout` reports
        // every later size (a section opened, a row gone).
        let fitting = NSHostingView(rootView: entry.view.environment(\.theme, colors)).fittingSize
        place(open, size: CGSize(width: registration.width, height: max(fitting.height, 1)))
        open.layout.onSize = { [weak self, weak open] size in
            guard let self, let open, self.current === open else { return }
            self.place(open, size: size)
        }

        window.orderFrontRegardless()
        window.makeKey()
        watch(open)
        bar.mark(open: registration.pill, fill: colors.hover)
        return true
    }

    /// Puts the window where `size` belongs, the top and the anchored edge
    /// where they were.
    private func place(_ open: Open, size: CGSize) {
        let geometry = open.geometry
        let placement = BarPanelPlacement.place(size: size, anchor: open.registration.anchor, pill: geometry.pill,
                                                lines: geometry.lines, bottom: geometry.bottom)
        let (frame, inset) = placement.window
        open.layout.inset = inset
        open.layout.shape = BarPanelShape(
            topLeading: placement.followsLeft ? geometry.cornerRadius : GroveRadius.card,
            topTrailing: placement.followsRight ? geometry.cornerRadius : GroveRadius.card)
        let target = Self.appKit(frame)
        if open.window.frame != target { open.window.setFrame(target, display: true) }
    }

    // MARK: Closing

    private func watch(_ open: Open) {
        let window = open.window
        func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil,
                     _ action: @escaping @MainActor (Notification) -> Void) {
            // Only what the action reads crosses to the main actor.
            let token = center.addObserver(forName: name, object: object, queue: .main) { note in
                nonisolated(unsafe) let note = note
                MainActor.assumeIsolated { action(note) }
            }
            open.observers.append((center, token))
        }
        // The keyboard went to another window: as a click outside.
        observe(.default, NSWindow.didResignKeyNotification, object: window) { [weak self] _ in
            self?.dismissFromOutside()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.close(handBack: false) }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.close(handBack: false) }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Grove Keys itself coming forward (a link opened without -g) closes nothing.
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.close(handBack: false)
        }

        // A click in another app, on the desktop or on the bar.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissFromOutside() }
            }) {
            open.monitors.append(monitor)
        }
        // A click in another window of Grove Keys; and the keys.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown], handler: { [weak self] event in
                nonisolated(unsafe) let event = event
                let used = MainActor.assumeIsolated { self?.used(event) ?? false }
                return used ? nil : event
            }) {
            open.monitors.append(monitor)
        }
    }

    /// An event of Grove Keys' own while a panel is open. True: the panel
    /// used it up (Escape, a key its model took).
    private func used(_ event: NSEvent) -> Bool {
        guard let open = current else { return false }
        if event.type != .keyDown {
            if event.window !== open.window { dismissFromOutside() }
            return false
        }
        guard event.window === open.window else { return false }
        if event.keyCode == 53 {  // Escape
            close()
            return true
        }
        if let key = BarPanelKey(event) { return open.model.key(key) }
        return false
    }

    private func tearDown(handBack: Bool) {
        guard let open = current else { return }
        current = nil
        for monitor in open.monitors { NSEvent.removeMonitor(monitor) }
        for observer in open.observers { observer.center.removeObserver(observer.token) }
        open.layout.onSize = nil
        open.model.stop()
        open.window.orderOut(nil)
        // The pointer still on the pill (the click that closed it): the
        // bar's hover keeps the fill until it leaves.
        let pointer = Self.windowList(NSEvent.mouseLocation)
        bar.markClosed(open.registration.pill, clear: !(open.geometry.pill?.contains(pointer) ?? false),
                       bg0: AppModel.shared.colors.bg0)
        if handBack, NSApp.isActive, let pid = open.handBackTo {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    // MARK: Geometry

    /// The height of the main display, whose top is y 0 of the window list.
    private static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// A rectangle of the window list (y down) as AppKit has it (y up).
    private static func appKit(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func windowList(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func windowList(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainHeight - point.y)
    }

    /// Where the pill is (the bar's answer) and where the window borders'
    /// lines are (the `borders` windows on screen; the configured gaps when
    /// no window is tiled there).
    private static func geometry(pill: String, on screen: NSScreen) -> Geometry {
        let frame = windowList(screen.frame)
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let width = WindowBorders.width(bordersrc: try? String(
            contentsOf: WindowBorders.configFile(home: home, environment: environment), encoding: .utf8))
        let fallback = WindowBorders.fallback(screen: frame, notchInset: screen.safeAreaInsets.top, width: width)
        let lines = WindowBorders.lines(borderWindows: borderWindows(), width: width, screen: frame, fallback: fallback)
        // The pill on this screen; with one screen, the one the bar gave.
        let rects = BarPill.rects(of: pill)
        let pillRect = rects.values.first { frame.contains(CGPoint(x: $0.midX, y: $0.midY)) }
            ?? (NSScreen.screens.count == 1 ? rects.values.first : nil)
        return Geometry(pill: pillRect, lines: lines, bottom: frame.maxY - WindowBorders.bottomGap,
                        cornerRadius: WindowBorders.cornerRadius(width: width))
    }

    /// The frames of JankyBorders' windows on screen (names need no Screen
    /// Recording permission). A few milliseconds, once per opening.
    private static func borderWindows() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { window in
            guard window[kCGWindowOwnerName as String] as? String == "borders",
                  let bounds = window[kCGWindowBounds as String] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
        }
    }
}

/// A borderless panel can't take the keyboard unless it says so.
private final class BarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Where the panel is drawn inside its window (the window sits on whole
/// points, the panel may start on a half), its corners, and the size its
/// content last asked for.
@MainActor
private final class BarPanelLayout: ObservableObject {
    @Published var inset = CGPoint.zero
    @Published var shape = BarPanelShape.card
    var onSize: ((CGSize) -> Void)?
    private var size = CGSize.zero

    func report(_ new: CGSize) {
        guard new != size, new.width > 0, new.height > 0 else { return }
        size = new
        onSize?(new)
    }
}

private struct BarPanelSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// A panel's view in its window: the scheme's colours (they follow a theme
/// switch while open), the host's actions, the corners, and the size
/// reported back.
private struct BarPanelRoot: View {
    let content: AnyView
    @ObservedObject var layout: BarPanelLayout
    @ObservedObject var app: AppModel
    let actions: BarPanelActions

    var body: some View {
        content
            .background(GeometryReader { geo in Color.clear.preference(key: BarPanelSizeKey.self, value: geo.size) })
            .onPreferenceChange(BarPanelSizeKey.self) { [layout] size in
                // After this layout pass: the window can't be resized inside it.
                Task { @MainActor in layout.report(size) }
            }
            .padding(.leading, layout.inset.x)
            .padding(.top, layout.inset.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.theme, app.colors)
            .environment(\.barPanel, actions)
            .environment(\.barPanelShape, layout.shape)
    }
}

/// What the bar is told about the open panel: its pill filled like a pill
/// under the pointer, and `$GROVE_STATE/bar-panel` naming it, which keeps
/// the bar's hover from clearing that fill and tells its workspaces plugin
/// there is a panel to close. In order, off the main thread.
@MainActor
final class BarPill {
    private nonisolated static let binary = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    private let queue = DispatchQueue(label: "com.projectgrove.keys.bar-pill", qos: .userInitiated)
    private let file = BarPanelFile.url(environment: ProcessInfo.processInfo.environment,
                                        home: FileManager.default.homeDirectoryForCurrentUser)

    /// Where the bar draws `item` (a pill is a bracket, and reports its own
    /// rectangle), by display; empty when the bar doesn't answer in time.
    static func rects(of item: String) -> [Int: CGRect] {
        guard let binary, BarPanelFile.isItemName(item) else { return [:] }
        let answer = Subprocess.run(binary, ["--query", item], timeout: 0.5)
        return answer.status == 0 ? BarQuery.rects(json: answer.output) : [:]
    }

    func mark(open pill: String, fill: RGB) {
        guard BarPanelFile.isItemName(pill) else { return }
        let color = BarPanelFile.argb(fill)
        queue.async { [file] in
            try? writeAtomically(Data((pill + "\n").utf8), to: file)
            Self.set(pill, color)
        }
    }

    /// `clear: false` leaves the fill to the bar's hover (the pointer is on
    /// the pill).
    func markClosed(_ pill: String, clear: Bool, bg0: RGB) {
        let color = BarPanelFile.transparent(bg0)
        queue.async { [file] in
            try? FileManager.default.removeItem(at: file)
            if clear { Self.set(pill, color) }
        }
    }

    /// At launch and at quitting: no panel is open, whatever a crash left.
    func forget() {
        queue.sync { [file] in try? FileManager.default.removeItem(at: file) }
    }

    private nonisolated static func set(_ pill: String, _ color: String) {
        guard let binary, BarPanelFile.isItemName(pill) else { return }
        _ = Subprocess.run(binary, ["--set", pill, "background.color=\(color)"], timeout: 1)
    }
}
