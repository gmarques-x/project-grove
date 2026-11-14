import AppKit
import GroveThemesCore
import SwiftUI

// Where a SwiftUI view's Grove menu opens from: an empty AppKit view behind
// it (the menu needs a view in a window, `GroveMenuList.popUp`). A
// right-click menu (`groveContextMenu`) and GroveSelect's list both open
// from one.

extension View {
    /// A right-click menu drawn as the Grove menu (`GroveMenuList`), in
    /// place of `.contextMenu`: a right-click or ⌃-click on the view opens
    /// `rows()` at the pointer, and a "Show Menu" accessibility action opens
    /// them under the view (offered only while there are rows: SwiftUI has
    /// no standard AXShowMenu kind for a view, so it is a named action).
    /// `rows` is asked at each opening; when it gives none there is no menu
    /// and the click goes on, as with an empty `.contextMenu`, and a
    /// disabled view has none. A text field being typed in keeps its own
    /// menu (Cut, Copy, Paste).
    public func groveContextMenu(rows: @escaping () -> [GroveMenuListRow],
                                 onChoose: @escaping (String) -> Void) -> some View {
        modifier(GroveContextMenu(rows: rows, onChoose: onChoose))
    }
}

private struct GroveContextMenu: ViewModifier {
    let rows: () -> [GroveMenuListRow]
    let onChoose: (String) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private let anchor = State(initialValue: GroveMenuListAnchor.Box())

    func body(content: Content) -> some View {
        // A disabled view (`.disabled`) has no menu.
        let rows = isEnabled ? rows : { [] }
        let hasRows = !rows().isEmpty
        return content
            .background(GroveMenuListAnchor(box: anchor.wrappedValue, theme: theme, rightClick: true,
                                            rows: rows, onChoose: onChoose))
            .accessibilityActions {
                if hasRows {
                    Button("Show Menu") { anchor.wrappedValue.view?.showUnder() }
                }
            }
    }
}

/// The empty view behind a view whose menu opens from it.
struct GroveMenuListAnchor: NSViewRepresentable {
    /// How the SwiftUI side reaches the view (a button's action).
    @MainActor
    final class Box {
        weak var view: GroveMenuListAnchorView?
    }

    let box: Box
    let theme: ThemeColors
    /// A right-click (or ⌃-click) on the view opens the menu at the pointer.
    let rightClick: Bool
    let rows: () -> [GroveMenuListRow]
    let onChoose: (String) -> Void
    /// A dropdown's: the view is its pop-up button to VoiceOver.
    var popUp: GroveMenuListAnchorView.PopUp? = nil

    func makeNSView(context: Context) -> GroveMenuListAnchorView {
        let view = GroveMenuListAnchorView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: GroveMenuListAnchorView, context: Context) {
        view.theme = theme
        view.rightClick = rightClick
        view.rows = rows
        view.onChoose = onChoose
        view.popUp = popUp
        box.view = view
    }
}

/// An empty, flipped view that opens a Grove menu: at the pointer for a
/// right-click on it (watched with a local monitor while it is in a window,
/// so the SwiftUI views over it keep their clicks), or under itself. For a
/// dropdown (`popUp`) it is also the control VoiceOver reads: a pop-up
/// button with its name and value, which the press and AXShowMenu open,
/// expanded while its list is up.
final class GroveMenuListAnchorView: NSView {
    /// What a dropdown's pop-up button says, and how far under it its list opens.
    struct PopUp: Equatable {
        var label: String
        var value: String
        var gap: CGFloat
    }

    var theme: ThemeColors = .fallback
    var rightClick = false
    var rows: () -> [GroveMenuListRow] = { [] }
    var onChoose: (String) -> Void = { _ in }
    var popUp: PopUp?
    /// This view's menu is up (not another view's). A dropdown tells
    /// VoiceOver when that changes: AppKit has no expanded-changed
    /// notification outside outline rows, so it is the value changing,
    /// after which the expanded state is read again.
    private(set) var menuOpen = false {
        didSet {
            guard menuOpen != oldValue, popUp != nil else { return }
            NSAccessibility.post(element: self, notification: .valueChanged)
            onPost?(.valueChanged)
        }
    }
    /// Each notification posted (for tests).
    var onPost: ((NSAccessibility.Notification) -> Void)?
    /// What the menu is popped up on (tests give one whose panels are never shown).
    var host: GroveMenuListHost = GroveMenuList.host
    // `nonisolated(unsafe)` for `deinit` only, which runs on the main thread
    // when SwiftUI lets the view go.
    private nonisolated(unsafe) var monitor: Any?

    override var isFlipped: Bool { true }
    // Nothing to click or read: the view in front speaks for itself.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { popUp != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { popUp != nil ? .popUpButton : nil }
    override func accessibilityLabel() -> String? { popUp?.label }
    override func accessibilityValue() -> Any? { popUp?.value }
    override func isAccessibilityExpanded() -> Bool { menuOpen }
    override func accessibilityPerformPress() -> Bool { openList() }
    override func accessibilityPerformShowMenu() -> Bool { openList() }

    /// A dropdown's list, opened by VoiceOver.
    private func openList() -> Bool {
        guard popUp != nil, !rows().isEmpty else { return false }
        showUnder()
        return true
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil, rightClick else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let used = MainActor.assumeIsolated { self?.rightClicked(event) ?? false }
            return used ? nil : event
        }
    }

    /// Whether `event` asks for a menu: a right-click, or a ⌃-click.
    static func isMenuClick(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown: true
        case .leftMouseDown: event.modifierFlags.intersection([.command, .option, .shift, .control]) == .control
        default: false
        }
    }

    /// A click of the app's: the menu opens when it asks for one over the
    /// part of this view that can be seen. True: the menu used it up.
    func rightClicked(_ event: NSEvent) -> Bool {
        guard rightClick, Self.isMenuClick(event), let window, event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.intersection(visibleRect).contains(point), !Self.inTextField(window, event.locationInWindow) else { return false }
        let rows = rows()
        guard !rows.isEmpty else { return false }
        open(rows, at: point, opening: event)
        return true
    }

    /// Opens the menu with its top-left corner under this view's
    /// bottom-left, a dropdown's `gap` lower (a dropdown's list, "Show Menu").
    func showUnder() {
        open(rows(), at: NSPoint(x: 0, y: bounds.height + (popUp?.gap ?? 0)), opening: nil)
    }

    private func open(_ rows: [GroveMenuListRow], at point: NSPoint, opening: NSEvent?) {
        host.popUp(rows: rows, at: point, in: self, theme: theme, opening: opening, onChoose: onChoose,
                   onClosed: { [weak self] _ in self?.menuOpen = false })
        // No rows, or no window: closed already.
        menuOpen = host.isOpen
    }

    /// The click is on a text field being typed in (its field editor, a
    /// text view): it keeps its own menu. A field not being edited is the
    /// row's text, and gets the row's menu.
    private static func inTextField(_ window: NSWindow, _ point: NSPoint) -> Bool {
        guard let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return false }
        return hit is NSTextView
    }
}
