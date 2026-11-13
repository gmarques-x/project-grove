import AppKit
import Combine
import GroveThemesCore
import SwiftUI

// The Grove menu popped up at a point in a window: what a right-click menu,
// a dropdown's list and the Grove menu at the pointer are drawn in (spec
// 2026-11-13-grove-context-menus-design). Hand-built for the reason
// GroveMenuList.swift gives; hosted here, in AppKit, because what makes it a
// menu is the windows: one panel per level, none of which ever takes the
// keyboard, so the window it was opened from stays key, as with `NSMenu`.

/// Pops up the Grove menu (`GroveMenuListRow`s) at a point in a view.
///
/// One menu is open at a time in the app: a new `popUp` closes the open one
/// first (its `onClose` runs). While it is open every key-down of the app
/// goes to the menu and nothing else gets it: ↑↓ (Home/End) move, → or
/// Return opens a submenu, ← and Esc close one, Return and Space choose,
/// a letter jumps; Esc with no submenu open closes the menu, as does Return
/// with no row highlighted. It closes without choosing on a click outside
/// it (a right-click goes on to what it was on, so a second right-click
/// opens a menu there instead), the window it was opened from closing or
/// losing the keyboard, the app going to the background, a Space or screen
/// change.
@MainActor
public enum GroveMenuList {
    static let host = GroveMenuListHost()

    /// Shows `rows` with the menu's top-left corner at `point` (in `view`'s
    /// coordinates), flipped to stay on its screen, and returns at once.
    ///
    /// - `theme`: the colours it is drawn in (the window's). GroveUI has no
    ///   app-wide theme to read, and a menu in the wrong scheme is worse than
    ///   a parameter.
    /// - `onChoose`: a row was chosen (its `id`), after the menu has gone.
    /// - `onClose`: the menu closed, chosen or not: exactly once per `popUp`,
    ///   after `onChoose`. The place for what a caller did after a blocking
    ///   `NSMenu.popUp`. A `popUp` with no rows, or from a view not in a
    ///   window, shows nothing and calls it at once.
    public static func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
                             onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        host.popUp(rows: rows, at: point, in: view, theme: theme, onChoose: onChoose, onClose: onClose)
    }

    /// Closes the open menu without choosing (its `onClose` runs).
    public static func close() { host.close() }

    /// Whether a menu is open.
    public static var isOpen: Bool { host.isOpen }
}

/// What `GroveMenuList` runs on. Its own type so tests can make one whose
/// panels are never put on screen.
@MainActor
final class GroveMenuListHost {
    /// False in tests: the panels are made and placed, never shown.
    let showsPanels: Bool

    init(showsPanels: Bool = true) {
        self.showsPanels = showsPanels
    }

    /// One open menu.
    @MainActor
    final class Open {
        let model: GroveMenuListModel
        weak var owner: NSWindow?
        let theme: ThemeColors
        let onChoose: (String) -> Void
        let onClose: () -> Void
        /// What the panels may cover: the screen's visible frame, y down.
        let screen: CGRect
        /// Per level (0: the menu), its panel and frame (y down).
        var panels: [GroveMenuListWindow] = []
        var frames: [CGRect] = []
        var monitors: [Any] = []
        var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
        var changes: AnyCancellable?
        var refreshPending = false

        init(model: GroveMenuListModel, owner: NSWindow, theme: ThemeColors, screen: CGRect,
             onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void) {
            self.model = model
            self.owner = owner
            self.theme = theme
            self.screen = screen
            self.onChoose = onChoose
            self.onClose = onClose
        }

        func owns(_ window: NSWindow?) -> Bool { panels.contains { $0 === window } }
    }

    private(set) var current: Open?
    var isOpen: Bool { current != nil }

    func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
               onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        close()
        guard !rows.isEmpty, let owner = view.window else {
            onClose()
            return
        }
        let onScreen = owner.convertPoint(toScreen: view.convert(point, to: nil))
        let screen = NSScreen.screens.first { $0.frame.contains(onScreen) } ?? owner.screen ?? NSScreen.main
        let bounds = screen.map { Self.yDown($0.visibleFrame) } ?? Self.yDown(owner.frame)

        let model = GroveMenuListModel(width: nil, icons: false)
        model.show(rows)
        let open = Open(model: model, owner: owner, theme: theme, screen: bounds, onChoose: onChoose, onClose: onClose)
        current = open
        model.onChoose = { [weak self, weak open] row in
            guard let self, let open, self.current === open else { return }
            self.choose(row.id)
        }
        model.onLevels = { [weak self, weak open] in
            guard let self, let open, self.current === open else { return }
            self.placeSubmenus(open)
        }
        // Highlights and levels change inside the model's own calls; the
        // accessibility tree follows once they are done.
        open.changes = model.objectWillChange.sink { [weak self, weak open] _ in
            guard let self, let open, !open.refreshPending else { return }
            open.refreshPending = true
            DispatchQueue.main.async { [weak self, weak open] in
                guard let self, let open, self.current === open else { return }
                self.refreshAccessibility()
            }
        }

        let frame = MenuPlacement.menu(origin: Self.yDown(onScreen), size: model.levels[0].layout.size,
                                       screen: bounds)
        let panel = makePanel(open, depth: 0)
        panel.setFrame(Self.appKit(frame), display: false)
        open.panels = [panel]
        open.frames = [frame]
        if showsPanels { panel.orderFrontRegardless() }
        watch(open)
        refreshAccessibility()
        Self.post(panel.levelMenu, Self.menuOpened)
    }

    func close() {
        guard let open = current else { return }
        tearDown(open)
        open.onClose()
    }

    private func choose(_ id: String) {
        guard let open = current else { return }
        tearDown(open)
        open.onChoose(id)
        open.onClose()
    }

    private func tearDown(_ open: Open) {
        current = nil
        for monitor in open.monitors { NSEvent.removeMonitor(monitor) }
        for observer in open.observers { observer.center.removeObserver(observer.token) }
        open.monitors = []
        open.observers = []
        open.changes = nil
        open.model.onChoose = { _ in }
        open.model.onLevels = {}
        open.model.clear()
        for panel in open.panels.reversed() {
            Self.post(panel.levelMenu, Self.menuClosed)
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        open.panels = []
        open.frames = []
    }

    // MARK: Panels

    private func makePanel(_ open: Open, depth: Int) -> GroveMenuListWindow {
        let panel = GroveMenuListWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        // Above the app's windows, as a native menu; it closes itself when
        // the app goes to the background.
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: open.theme.isDark ? .darkAqua : .aqua)

        let menu = GroveMenuListAccessibleMenu(depth: depth)
        let hosting = NSHostingView(rootView: GroveMenuListPopUpRoot(model: open.model, level: depth, theme: open.theme))
        // The host sizes the window; the hosting view must not.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        menu.addSubview(hosting)
        panel.contentView = menu
        hosting.frame = menu.bounds
        panel.levelMenu = menu
        return panel
    }

    /// Shows, moves and removes the submenus' panels so they are what the
    /// model's `submenus` says: each beside the one before, on the screen.
    private func placeSubmenus(_ open: Open) {
        guard !open.panels.isEmpty else { return }
        var count = 1
        for submenu in open.model.submenus {
            let depth = submenu.depth
            guard depth == count, open.frames.indices.contains(depth - 1) else { break }
            let parent = open.frames[depth - 1]
            let frame = MenuPlacement.submenu(parent: parent, row: submenu.row, size: submenu.size,
                                              firstRow: submenu.firstRow, bounds: open.screen)
            let panel: GroveMenuListWindow
            if depth < open.panels.count {
                panel = open.panels[depth]
                open.frames[depth] = frame
            } else {
                panel = makePanel(open, depth: depth)
                open.panels.append(panel)
                open.frames.append(frame)
            }
            let target = Self.appKit(frame)
            if panel.frame != target { panel.setFrame(target, display: true) }
            // A child panel goes with the menu's and stays above it.
            if showsPanels, panel.parent == nil {
                open.panels[depth - 1].addChildWindow(panel, ordered: .above)
                Self.post(panel.levelMenu, Self.menuOpened)
            }
            open.model.placed(depth, onLeft: frame.minX < parent.minX)
            count += 1
        }
        while open.panels.count > count {
            let panel = open.panels.removeLast()
            open.frames.removeLast()
            Self.post(panel.levelMenu, Self.menuClosed)
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    // MARK: Events

    private func watch(_ open: Open) {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil) {
            // Posted on the main thread: handled there, at once.
            let token = center.addObserver(forName: name, object: object, queue: nil) { [weak self, weak open] _ in
                MainActor.assumeIsolated {
                    guard let self, let open, self.current === open else { return }
                    self.close()
                }
            }
            open.observers.append((center, token))
        }
        if let owner = open.owner {
            observe(.default, NSWindow.willCloseNotification, object: owner)
            observe(.default, NSWindow.didResignKeyNotification, object: owner)
        }
        observe(.default, NSApplication.didResignActiveNotification)
        observe(.default, NSApplication.didChangeScreenParametersNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)

        // The keys, and a click in another of the app's windows.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
                nonisolated(unsafe) let event = event
                let passes = MainActor.assumeIsolated { self?.handle(event) ?? true }
                return passes ? event : nil
            }) {
            open.monitors.append(monitor)
        }
        // A click in another app, the desktop, a status item.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }) {
            open.monitors.append(monitor)
        }
    }

    /// An event of the app's while a menu is open: whether it goes on
    /// (false: the menu used it up). Every key-down is the menu's; a click
    /// in its panels goes to them; a click anywhere else closes it, and only
    /// a right-click goes on.
    func handle(_ event: NSEvent) -> Bool {
        guard let open = current else { return true }
        switch event.type {
        case .keyDown:
            key(event, open.model)
            return false
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if open.owns(event.window) { return true }
            close()
            return event.type == .rightMouseDown
        default:
            return true
        }
    }

    private func key(_ event: NSEvent, _ model: GroveMenuListModel) {
        if event.keyCode == 53 {  // Escape
            if !model.escape() { close() }
            return
        }
        guard let key = GroveMenuListKey(event) else { return }
        // Return with nothing highlighted puts the menu away, as a native one.
        if !model.key(key), key == .enter { close() }
    }

    // MARK: Coordinates

    /// The top of the main display, y 0 when y goes down.
    private static var top: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// A point of AppKit's screen space (y up) with y going down.
    static func yDown(_ point: NSPoint) -> CGPoint { CGPoint(x: point.x, y: top - point.y) }

    static func yDown(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A rectangle with y going down as AppKit has it (y up).
    static func appKit(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Accessibility

    static let menuOpened = NSAccessibility.Notification(rawValue: "AXMenuOpened")
    static let menuClosed = NSAccessibility.Notification(rawValue: "AXMenuClosed")
    static let menuItemSelected = NSAccessibility.Notification(rawValue: "AXMenuItemSelected")

    private static func post(_ menu: GroveMenuListAccessibleMenu?, _ notification: NSAccessibility.Notification) {
        guard let menu else { return }
        NSAccessibility.post(element: menu, notification: notification)
    }

    /// Makes each panel's `AXMenu` say what its level shows.
    func refreshAccessibility() {
        guard let open = current else { return }
        open.refreshPending = false
        let model = open.model
        for (depth, panel) in open.panels.enumerated() where model.levels.indices.contains(depth) {
            let level = model.levels[depth]
            let submenu = depth + 1 < open.panels.count ? open.panels[depth + 1].levelMenu : nil
            panel.levelMenu?.update(level: level, checked: model.checked, openRow: model.openRow(depth),
                               submenu: submenu) { [weak model] row in model?.press(depth, row) }
        }
    }
}

/// A menu's panel: never key, never main, so the window the menu was
/// opened from keeps the keyboard; clicks and the pointer work in it all
/// the same (`GroveMenuListPointerView` takes the first click).
final class GroveMenuListWindow: NSPanel {
    /// Its content, the level's `AXMenu`.
    weak var levelMenu: GroveMenuListAccessibleMenu?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A level's panel, as the window is: the card at the top-left, its own
/// size (the window is made to fit it).
private struct GroveMenuListPopUpRoot: View {
    let model: GroveMenuListModel
    let level: Int
    let theme: ThemeColors

    var body: some View {
        Color.clear.overlay(alignment: .topLeading) {
            GroveMenuListPanel(model: model, level: level, surface: .panel)
        }
        .environment(\.theme, theme)
    }
}

// MARK: Accessibility

/// A level's panel to the accessibility server: an `AXMenu` whose children
/// are its rows as `AXMenuItem`s (title, enabled, the tick as
/// `AXMenuItemMarkChar`, an open submenu's `AXMenu` as a child). It stands
/// in for the SwiftUI rows drawn under it, which VoiceOver doesn't see.
final class GroveMenuListAccessibleMenu: NSView {
    let depth: Int
    // Read by the accessibility server's calls, which AppKit makes on the
    // main thread; written only from the main actor.
    nonisolated(unsafe) private(set) var items: [GroveMenuListAccessibleItem] = []
    /// The child a closed submenu's row has, so it reads as one.
    private var closedSubmenus: [String: NSAccessibilityElement] = [:]

    init(depth: Int) {
        self.depth = depth
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menu }
    override func accessibilityChildren() -> [Any]? { items }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        items.first { $0.accessibilityFrame().contains(point) } ?? self
    }

    func update(level: GroveMenuListModel.Level, checked: Set<String>, openRow: Int?,
                submenu: GroveMenuListAccessibleMenu?, press: @escaping (Int) -> Void) {
        if items.map(\.id) != level.rows.map(\.id) {
            items = level.rows.map { GroveMenuListAccessibleItem(id: $0.id) }
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        for (index, row) in level.rows.enumerated() {
            let item = items[index]
            item.setAccessibilityParent(self)
            item.setAccessibilityRole(.menuItem)
            item.setAccessibilityTitle(row.title)
            item.setAccessibilityEnabled(row.isSelectable)
            item.setAccessibilityFrameInParentSpace(level.layout.rows[index])
            item.mark = checked.contains(row.id) ? "\u{2713}" : nil
            item.press = { press(index) }
            if row.children != nil {
                if index == openRow, let submenu {
                    submenu.setAccessibilityParent(item)
                    item.setAccessibilityChildren([submenu])
                } else {
                    let closed = closedSubmenus[row.id] ?? NSAccessibilityElement()
                    closed.setAccessibilityRole(.menu)
                    closed.setAccessibilityParent(item)
                    closedSubmenus[row.id] = closed
                    item.setAccessibilityChildren([closed])
                }
            } else {
                item.setAccessibilityChildren([])
            }
            let selected = level.highlighted == index
            if selected != item.isAccessibilitySelected() {
                item.setAccessibilitySelected(selected)
                if selected { NSAccessibility.post(element: item, notification: GroveMenuListHost.menuItemSelected) }
            }
        }
    }
}

/// One row as an `AXMenuItem`. VoiceOver's press is the row's click.
final class GroveMenuListAccessibleItem: NSAccessibilityElement {
    let id: String
    var press: () -> Void = {}
    /// The tick, as a native menu item reports it; nil when not ticked.
    var mark: String?

    static let markChar = NSAccessibility.Attribute(rawValue: "AXMenuItemMarkChar")

    init(id: String) {
        self.id = id
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityEnabled() else { return false }
        press()
        return true
    }

    // `AXMenuItemMarkChar` has no property in the NSAccessibility protocol;
    // the attribute-name API (deprecated, still read by the accessibility
    // server, and what a native menu item answers it with) is how an
    // element adds one.
    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeNames() -> [NSAccessibility.Attribute] {
        super.accessibilityAttributeNames() + [Self.markChar]
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        attribute == Self.markChar ? mark : super.accessibilityAttributeValue(attribute)
    }
}
