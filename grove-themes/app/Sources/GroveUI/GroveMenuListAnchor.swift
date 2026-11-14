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
    /// `rows()` at the pointer, and VoiceOver's "Show Menu" action opens them
    /// under the view. `rows` is asked at each opening; when it gives none
    /// there is no menu and the click goes on, as with an empty
    /// `.contextMenu`, and a disabled view has none. A click in a text field
    /// keeps the field's own menu (Cut, Copy, Paste).
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
        return content
            .background(GroveMenuListAnchor(box: anchor.wrappedValue, theme: theme, rightClick: true,
                                            rows: rows, onChoose: onChoose))
            .accessibilityAction(named: "Show Menu") { anchor.wrappedValue.view?.showUnder() }
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
        box.view = view
    }
}

/// An empty, flipped view that opens a Grove menu: at the pointer for a
/// right-click on it (watched with a local monitor while it is in a window,
/// so the SwiftUI views over it keep their clicks), or under itself.
final class GroveMenuListAnchorView: NSView {
    var theme: ThemeColors = .fallback
    var rightClick = false
    var rows: () -> [GroveMenuListRow] = { [] }
    var onChoose: (String) -> Void = { _ in }
    /// What the menu is popped up on (tests give one whose panels are never shown).
    var host: GroveMenuListHost = GroveMenuList.host
    // `nonisolated(unsafe)` for `deinit` only, which runs on the main thread
    // when SwiftUI lets the view go.
    private nonisolated(unsafe) var monitor: Any?

    override var isFlipped: Bool { true }
    // Nothing to click or read: the view in front speaks for itself.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

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
        host.popUp(rows: rows, at: point, in: self, theme: theme, opening: event, onChoose: onChoose, onClose: {})
        return true
    }

    /// Opens the menu with its top-left corner `gap` under this view's
    /// bottom-left (a dropdown's list, VoiceOver's "Show Menu").
    func showUnder(gap: CGFloat = 0, rows: [GroveMenuListRow]? = nil, onChoose: ((String) -> Void)? = nil) {
        host.popUp(rows: rows ?? self.rows(), at: NSPoint(x: 0, y: bounds.height + gap), in: self, theme: theme,
                   opening: nil, onChoose: onChoose ?? self.onChoose, onClose: {})
    }

    /// The click is on a text field being typed in, or one that can be.
    private static func inTextField(_ window: NSWindow, _ point: NSPoint) -> Bool {
        guard let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return false }
        if hit is NSTextView { return true }
        if let field = hit as? NSTextField { return field.isEditable }
        return false
    }
}
