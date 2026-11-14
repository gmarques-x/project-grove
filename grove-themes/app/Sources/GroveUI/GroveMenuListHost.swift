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
/// first (its `onClose` runs). A menu popped up while the app is in the
/// background brings the app forward (the panels still never take the
/// keyboard), or no key would reach it. While it is open every key-down of
/// the app goes to the menu and nothing else gets it: ↑↓ (Home/End) move, →
/// or Return opens a submenu, ← and Esc close one, Return and Space choose,
/// a letter jumps; Esc with no submenu open closes the menu, as does Return
/// with no row highlighted. A press held and released over a row chooses
/// it; a plain click's release leaves the menu open (`MenuPress`).
/// Scrolling outside the menu does nothing while it is open. It closes
/// without choosing on a click outside it (a right-click goes on to what it
/// was on, so a second right-click opens a menu there instead), the window
/// it was opened from closing or losing the keyboard, the view leaving that
/// window, the app going to the background, a Space or screen change.
@MainActor
public enum GroveMenuList {
    static let host = GroveMenuListHost()

    /// Shows `rows` with the menu's top-left corner at `point` (in `view`'s
    /// coordinates), flipped to stay on its screen, and returns at once.
    ///
    /// - `theme`: the colours it is drawn in (the window's). GroveUI has no
    ///   app-wide theme to read, and a menu in the wrong scheme is worse than
    ///   a parameter.
    /// - `opening`: the event that asked for the menu (a right-click), when
    ///   it isn't the app's current event (a caller in an event monitor):
    ///   its release chooses a row only when the press was held (`MenuPress`).
    /// - `onChoose`: a row was chosen (its `id`), after the menu has gone.
    /// - `onClose`: the menu closed, chosen or not: exactly once per `popUp`,
    ///   after `onChoose`. The place for what a caller did after a blocking
    ///   `NSMenu.popUp`. A `popUp` with no rows, or from a view not in a
    ///   window, shows nothing and calls it at once.
    public static func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
                             opening: NSEvent? = NSApp.currentEvent,
                             onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        host.popUp(rows: rows, at: point, in: view, theme: theme, opening: opening, onChoose: onChoose,
                   onClosed: { _ in onClose() })
    }

    /// The same, told why the menu closed: for a caller whose after-work
    /// depends on it (the Grove menu at the pointer gives the keyboard back
    /// to the app that was in front, but not when the user went to another).
    public static func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
                             opening: NSEvent? = NSApp.currentEvent,
                             onChoose: @escaping (String) -> Void,
                             onClosed: @escaping (CloseReason) -> Void) {
        host.popUp(rows: rows, at: point, in: view, theme: theme, opening: opening, onChoose: onChoose,
                   onClosed: onClosed)
    }

    /// Why a menu closed.
    public enum CloseReason: Equatable, Sendable {
        /// A row was chosen (`onChoose` ran just before).
        case chosen
        /// Esc, Return with nothing highlighted, or `close()`.
        case dismissed
        /// A click outside the menu, in one of the app's windows.
        case clickedOutside
        /// A click in another app, on the desktop or a status item.
        case clickedInAnotherApp
        /// The app went to the background.
        case appDeactivated
        /// Its window closed or lost the keyboard, its view left the window,
        /// the screens or the Space changed, or another menu replaced it.
        case ownerGone
    }

    /// Closes the open menu without choosing (its `onClose` runs).
    public static func close() { host.close() }

    /// Whether a menu is open.
    public static var isOpen: Bool { host.isOpen }

    /// Ticks the row `id` of the open menu, when it has one: for a tick
    /// known only after the menu opened (the Grove menu's `checked` tests).
    public static func check(_ id: String) { host.check(id) }

}

/// What `GroveMenuList` runs on. Its own type so tests can make one whose
/// panels are never put on screen.
@MainActor
final class GroveMenuListHost {
    /// False in tests: the panels are made and placed, never shown.
    let showsPanels: Bool
    /// Whether the app is in front, and bringing it there (tests replace them).
    let isActive: @MainActor () -> Bool
    let activate: @MainActor () -> Void
    /// Each accessibility notification posted, with the level's depth (for tests).
    var onPost: ((Int, NSAccessibility.Notification) -> Void)?

    init(showsPanels: Bool = true, isActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
         activate: @escaping @MainActor () -> Void = { NSApp.activate() }) {
        self.showsPanels = showsPanels
        self.isActive = isActive
        self.activate = activate
    }

    /// One open menu.
    @MainActor
    final class Open {
        let model: GroveMenuListModel
        weak var owner: NSWindow?
        /// The view it was popped up in: it leaving the window closes the menu.
        weak var view: NSView?
        /// The press that opened it (its time and place on screen, y down),
        /// until its release comes.
        var press: (time: TimeInterval, point: CGPoint)?
        let theme: ThemeColors
        let onChoose: (String) -> Void
        let onClose: (GroveMenuList.CloseReason) -> Void
        /// What the panels may cover: the screen's visible frame, y down.
        let screen: CGRect
        /// Per level (0: the menu), its panel and frame (y down).
        var panels: [GroveMenuListWindow] = []
        var frames: [CGRect] = []
        var monitors: [Any] = []
        var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
        var changes: AnyCancellable?
        var refreshPending = false

        init(model: GroveMenuListModel, owner: NSWindow, view: NSView, theme: ThemeColors, screen: CGRect,
             onChoose: @escaping (String) -> Void, onClose: @escaping (GroveMenuList.CloseReason) -> Void) {
            self.model = model
            self.owner = owner
            self.view = view
            self.theme = theme
            self.screen = screen
            self.onChoose = onChoose
            self.onClose = onClose
        }

        func owns(_ window: NSWindow?) -> Bool { panels.contains { $0 === window } }

        /// The view is gone or in another window.
        var viewLeft: Bool { view?.window == nil || view?.window !== owner }
    }

    private(set) var current: Open?
    var isOpen: Bool { current != nil }

    /// An id no row has ticks nothing.
    func check(_ id: String) {
        current?.model.checked.insert(id)
    }


    /// `opening`: the event that asked for the menu (the right-click), whose
    /// release must not choose a row unless it was held (`MenuPress`).
    func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
               opening: NSEvent? = NSApp.currentEvent,
               onChoose: @escaping (String) -> Void,
               onClosed onClose: @escaping (GroveMenuList.CloseReason) -> Void) {
        // The open menu's `onClose` may pop up another: this, the newest
        // call, closes that one too. Never two at once.
        for _ in 0..<8 where current != nil { close(.ownerGone) }
        guard current == nil, !rows.isEmpty, let owner = view.window else {
            onClose(.dismissed)
            return
        }
        let onScreen = owner.convertPoint(toScreen: view.convert(point, to: nil))
        let screen = NSScreen.screens.first { $0.frame.contains(onScreen) } ?? owner.screen ?? NSScreen.main
        let bounds = screen.map { Self.yDown($0.visibleFrame) } ?? Self.yDown(owner.frame)

        let model = GroveMenuListModel(width: nil, icons: false)
        model.show(rows)
        let open = Open(model: model, owner: owner, view: view, theme: theme, screen: bounds,
                        onChoose: onChoose, onClose: onClose)
        if let opening, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(opening.type) {
            open.press = (opening.timestamp, Self.yDown(Self.screenPoint(opening)))
        }
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
        // In the background no key would reach the menu: the app comes
        // forward (its window keeps the keyboard; the panels never take it).
        // Not for a key non-activating panel (a bar panel): its keys reach
        // the app already, and the app in front keeps its place.
        if !isActive(), !owner.isKeyWindow { activate() }
        if showsPanels { panel.orderFrontRegardless() }
        watch(open)
        refreshAccessibility()
        post(panel, Self.menuOpened)
    }

    func close(_ reason: GroveMenuList.CloseReason = .dismissed) {
        guard let open = current else { return }
        tearDown(open)
        open.onClose(reason)
    }

    /// `popUp` for a caller that doesn't need to know why it closed.
    func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
               opening: NSEvent? = NSApp.currentEvent,
               onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        popUp(rows: rows, at: point, in: view, theme: theme, opening: opening, onChoose: onChoose,
              onClosed: { _ in onClose() })
    }

    /// The global monitor's: a click in another app.
    func clickedInAnotherApp() { close(.clickedInAnotherApp) }

    private func choose(_ id: String) {
        guard let open = current else { return }
        // Chosen from a view that is gone: nothing to do it for.
        if open.viewLeft { return close(.ownerGone) }
        tearDown(open)
        open.onChoose(id)
        open.onClose(.chosen)
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
            post(panel, Self.menuClosed)
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
            let rows = open.model.levels.indices.contains(depth) ? open.model.levels[depth].rows.map(\.id) : []
            if depth < open.panels.count {
                panel = open.panels[depth]
                open.frames[depth] = frame
                // The panel now shows another row's submenu: to VoiceOver,
                // one menu closed and another opened.
                if panel.shownRows != rows {
                    post(panel, Self.menuClosed)
                    post(panel, Self.menuOpened)
                }
            } else {
                panel = makePanel(open, depth: depth)
                open.panels.append(panel)
                open.frames.append(frame)
                post(panel, Self.menuOpened)
            }
            panel.shownRows = rows
            let target = Self.appKit(frame)
            if panel.frame != target { panel.setFrame(target, display: true) }
            // A child panel goes with the menu's and stays above it. (Not
            // in tests: a child is ordered in with its parent.)
            if showsPanels, panel.parent == nil {
                open.panels[depth - 1].addChildWindow(panel, ordered: .above)
            }
            open.model.placed(depth, onLeft: frame.minX < parent.minX)
            count += 1
        }
        while open.panels.count > count {
            let panel = open.panels.removeLast()
            open.frames.removeLast()
            post(panel, Self.menuClosed)
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    // MARK: Events

    private func watch(_ open: Open) {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil,
                     _ reason: GroveMenuList.CloseReason = .ownerGone) {
            // Posted on the main thread: handled there, at once.
            let token = center.addObserver(forName: name, object: object, queue: nil) { [weak self, weak open] _ in
                MainActor.assumeIsolated {
                    guard let self, let open, self.current === open else { return }
                    self.close(reason)
                }
            }
            open.observers.append((center, token))
        }
        if let owner = open.owner {
            observe(.default, NSWindow.willCloseNotification, object: owner)
            observe(.default, NSWindow.didResignKeyNotification, object: owner)
        }
        observe(.default, NSApplication.didResignActiveNotification, .appDeactivated)
        observe(.default, NSApplication.didChangeScreenParametersNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)

        // The keys, a click in another of the app's windows, a held press's
        // release, scrolling.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp,
                       .scrollWheel], handler: { [weak self] event in
                nonisolated(unsafe) let event = event
                let passes = MainActor.assumeIsolated { self?.handle(event) ?? true }
                return passes ? event : nil
            }) {
            open.monitors.append(monitor)
        }
        // A click in another app, the desktop, a status item.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.clickedInAnotherApp() }
            }) {
            open.monitors.append(monitor)
        }
    }

    /// An event of the app's while a menu is open: whether it goes on
    /// (false: the menu used it up). Every key-down is the menu's; a click
    /// in its panels goes to them; a click anywhere else closes it, and only
    /// a right-click goes on. A release over a row chooses it, unless it is
    /// a plain click's (the press that opened the menu, not held). Scrolling
    /// outside the menu is swallowed.
    func handle(_ event: NSEvent) -> Bool {
        guard let open = current else { return true }
        if open.viewLeft {
            close(.ownerGone)
            return true
        }
        switch event.type {
        case .keyDown:
            key(event, open.model)
            return false
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if open.owns(event.window) { return true }
            close(.clickedOutside)
            return event.type == .rightMouseDown
        case .leftMouseUp, .rightMouseUp:
            // A left click in a panel is its pointer view's.
            if event.type == .leftMouseUp, open.owns(event.window) {
                open.press = nil
                return true
            }
            let point = Self.yDown(Self.screenPoint(event))
            if let press = open.press {
                open.press = nil
                guard MenuPress.releaseChooses(pressedAt: press.time, at: press.point,
                                               releasedAt: event.timestamp, at: point) else { return true }
            }
            return !release(at: point, open)
        case .scrollWheel:
            return open.owns(event.window)
        default:
            return true
        }
    }

    /// A release at `point` (screen, y down): over a row that can be chosen
    /// it is that row's click. True when it was over a panel.
    private func release(at point: CGPoint, _ open: Open) -> Bool {
        for depth in open.frames.indices.reversed() where open.frames[depth].contains(point) {
            let frame = open.frames[depth]
            let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
            let model = open.model
            if model.levels.indices.contains(depth), let row = model.levels[depth].layout.row(at: local),
               model.levels[depth].rows[row].isSelectable {
                model.click(depth, at: local)
            }
            return true
        }
        return false
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

    /// Where an event happened, in AppKit's screen space.
    static func screenPoint(_ event: NSEvent) -> NSPoint {
        event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
    }

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

    private func post(_ panel: GroveMenuListWindow, _ notification: NSAccessibility.Notification) {
        guard let menu = panel.levelMenu else { return }
        NSAccessibility.post(element: menu, notification: notification)
        onPost?(menu.depth, notification)
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
    /// The ids of the rows it shows, to tell when a submenu's panel changes
    /// to another row's submenu.
    var shownRows: [String] = []

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
            // The bar's Grove menu's own card: bg0, its outline.
            GroveMenuListPanel(model: model, level: level)
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
    private(set) var items: [GroveMenuListAccessibleItem] = []
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

    // Not main-actor isolated in AppKit, but called on the main thread.
    // Only the element found leaves the main actor's region, and it is
    // read by the accessibility server on that same thread.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        nonisolated(unsafe) var hit: Any?
        MainActor.assumeIsolated { hit = items.first { $0.accessibilityFrame().contains(point) } ?? self }
        return hit
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
