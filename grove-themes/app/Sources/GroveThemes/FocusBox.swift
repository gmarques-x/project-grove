import AppKit
import GroveThemesCore
import SwiftUI

/// Keyboard navigation for the dropdown and the gallery (the rules are
/// `KeyboardFocus` / `FocusGrid` in Core): makes the view focusable without the
/// system focus ring, turns arrows and Ctrl+h/j/k/l, Return/Space and Esc into
/// focus commands, and hides the box on a mouse click in the window or when
/// the window opens, closes or stops being key.
struct KeyboardNavigation: ViewModifier {
    let focus: Binding<KeyboardFocus>
    let current: String
    let schemesDisabled: Bool
    let activate: (FocusGrid.Item) -> Void
    @FocusState private var hasKeys: Bool
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var host = State(initialValue: HostWindow())

    init(focus: Binding<KeyboardFocus>, current: String, schemesDisabled: Bool,
         activate: @escaping (FocusGrid.Item) -> Void) {
        self.focus = focus
        self.current = current
        self.schemesDisabled = schemesDisabled
        self.activate = activate
    }

    func body(content: Content) -> some View {
        content
            // `.edit`: focusable for key presses even without "Keyboard
            // navigation" turned on in System Settings.
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($hasKeys)
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard let command = Self.command(press) else { return .ignored }
                switch focus.wrappedValue.handle(command, current: current, schemesDisabled: schemesDisabled) {
                case .handled:
                    return .handled
                case .activate(let item):
                    activate(item)
                    return .handled
                case .close:
                    // Let the dropdown's own Esc handling close it.
                    return .ignored
                }
            }
            .background(WindowAccessor { [focus, host, hasKeysBinding = $hasKeys] window in
                host.wrappedValue.attach(window, onMouseDown: {
                    focus.wrappedValue.hide()
                }, onKeyChange: { isKey in
                    focus.wrappedValue.hide()
                    if isKey { hasKeysBinding.wrappedValue = true }
                })
            })
            .onAppear {
                focus.wrappedValue.hide()
                hasKeys = true
            }
            .onDisappear {
                focus.wrappedValue.hide()
            }
    }

    private static func command(_ press: KeyPress) -> FocusKey.Command? {
        var modifiers: FocusKey.Modifiers = []
        if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        let key: FocusKey
        switch press.key {
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .return: key = .returnKey
        case .space: key = .space
        case .escape: key = .escape
        default: key = .character(press.key.character)
        }
        if let command = key.command(modifiers) { return command }
        // Ctrl+letter may arrive as the letter or as its control character.
        if case .character = key, let typed = press.characters.first {
            return FocusKey.character(typed).command(modifiers)
        }
        return nil
    }
}

extension View {
    func keyboardNavigation(_ focus: Binding<KeyboardFocus>, current: String, schemesDisabled: Bool,
                            activate: @escaping (FocusGrid.Item) -> Void) -> some View {
        modifier(KeyboardNavigation(focus: focus, current: current, schemesDisabled: schemesDisabled,
                                    activate: activate))
    }

    /// The keyboard focus box: a 2 pt rounded outline in the current scheme's
    /// green, `outset` points outside the view (tiles and cards: 5, a 3 pt gap
    /// outside their own 2 pt border; menu rows: 0, on the row's edge).
    func focusBox(_ shown: Bool, cornerRadius: CGFloat, outset: CGFloat) -> some View {
        modifier(FocusBox(shown: shown, cornerRadius: cornerRadius, outset: outset))
    }
}

private struct FocusBox: ViewModifier {
    let shown: Bool
    let cornerRadius: CGFloat
    let outset: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.overlay {
            if shown {
                RoundedRectangle(cornerRadius: cornerRadius + outset)
                    .strokeBorder(Color(theme.green), lineWidth: 2)
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The window a view is in, watched for mouse clicks and key changes.
@MainActor
final class HostWindow {
    private weak var window: NSWindow?
    // `nonisolated(unsafe)` for `deinit` only, which SwiftUI runs on the main
    // thread when the view goes (the gallery window closed).
    private nonisolated(unsafe) var monitor: Any?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func attach(_ window: NSWindow, onMouseDown: @escaping @MainActor () -> Void,
                onKeyChange: @escaping @MainActor (_ isKey: Bool) -> Void) {
        guard window !== self.window else { return }
        detach()
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak window] event in
            if let window, event.window === window {
                MainActor.assumeIsolated { onMouseDown() }
            }
            return event
        }
        let names: [(Notification.Name, Bool)] = [
            (NSWindow.didBecomeKeyNotification, true),
            (NSWindow.didResignKeyNotification, false),
            (NSWindow.willCloseNotification, false),
        ]
        observers = names.map { name, isKey in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { onKeyChange(isKey) }
            }
        }
    }

    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        window = nil
    }
}
