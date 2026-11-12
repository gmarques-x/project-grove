import AppKit
import GroveThemesCore
import SwiftUI

/// The panel a key panel (the launcher, the searchable cheat sheet) is drawn
/// in: over the focused screen, below the menu bar, non-activating and able
/// to be key, so it takes the keyboard without its app coming forward.
///
/// `open` may bring the app forward all the same, so on closing the app that
/// was in front is given the keyboard back, unless the caller says not to
/// (the row run brings a window forward itself) or the panel closed because
/// the keyboard went elsewhere.
@MainActor
public final class KeyPanelHost {
    private let previousApp: @MainActor () -> pid_t?
    private var panel: KeyablePanel?
    private var handBackTo: pid_t?
    private var observers: [NSObjectProtocol] = []
    /// When the keyboard going elsewhere last closed the panel.
    private var lostKeyboard: Date?

    /// `previousApp`: the app to give the keyboard back to, asked each time
    /// the panel opens (the last app in front that isn't this one).
    public init(previousApp: @escaping @MainActor () -> pid_t?) {
        self.previousApp = previousApp
    }

    public var isOpen: Bool { panel != nil }

    /// False when there is no screen to show it on.
    public func open(_ content: some View) -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        // The app's own window in front: nothing to hand back. In front
        // without one (a menu of its has just closed), there is.
        handBackTo = NSApp.isActive && NSApp.mainWindow != nil ? nil : previousApp()
        lostKeyboard = nil

        let full = screen.frame
        let frame = NSRect(x: full.minX, y: full.minY, width: full.width,
                           height: max(0, screen.visibleFrame.maxY - full.minY))
        let panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: content)
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        // Another window or app took the keyboard (a click elsewhere, ⌘Tab):
        // the panel goes, and the keyboard stays where it went.
        let center = NotificationCenter.default
        for (name, object) in [(NSWindow.didResignKeyNotification, panel as Any?),
                               (NSApplication.didResignActiveNotification, nil)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    self.close(handBack: false)
                    self.lostKeyboard = Date()
                }
            })
        }
        // If macOS didn't give a background app's panel the keyboard, the
        // app comes forward for it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            guard self.panel === panel, !panel.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
        return true
    }

    public func close(handBack: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        panel.orderOut(nil)
        if handBack { self.handBack() }
    }

    /// A hotkey's link can close the panel before it arrives: `open` brings
    /// the app's window forward, and the keyboard goes to it. True within
    /// half a second of that: the link is that same "put away", not a new
    /// "show", and the app that was in front gets the keyboard back.
    public func closedByItsOwnLink() -> Bool {
        guard let lostKeyboard, Date().timeIntervalSince(lostKeyboard) < 0.5 else { return false }
        self.lostKeyboard = nil
        if NSApp.isActive { handBack() }
        return true
    }

    private func handBack() {
        guard let handBackTo else { return }
        NSRunningApplication(processIdentifier: handBackTo)?.activate()
    }
}

/// A borderless panel can't be key unless it says so.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The field of a key panel. AppKit's, so that it is the panel's first
/// responder from the start and ↑/↓, Return and Escape reach the panel's
/// owner while the typing stays in the field.
public struct FilterField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let theme: ThemeColors
    let onChange: @MainActor (String) -> Void
    /// −1 for ↑, 1 for ↓.
    let onMove: @MainActor (Int) -> Void
    let onReturn: @MainActor () -> Void
    let onEscape: @MainActor () -> Void

    public init(text: String, placeholder: String, theme: ThemeColors,
                onChange: @escaping @MainActor (String) -> Void, onMove: @escaping @MainActor (Int) -> Void,
                onReturn: @escaping @MainActor () -> Void, onEscape: @escaping @MainActor () -> Void) {
        self.text = text
        self.placeholder = placeholder
        self.theme = theme
        self.onChange = onChange
        self.onMove = onMove
        self.onReturn = onReturn
        self.onEscape = onEscape
    }

    public func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    public func makeNSView(context: Context) -> NSTextField {
        let field = FirstResponderField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = GroveFont.monoNS(GroveType.title)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        return field
    }

    public func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.field = self
        if field.stringValue != text { field.stringValue = text }
        field.textColor = NSColor(theme.fg)
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor(theme.dim), .font: GroveFont.monoNS(GroveType.title),
        ])
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: FilterField
        init(field: FilterField) { self.field = field }

        public func controlTextDidChange(_ note: Notification) {
            guard let text = (note.object as? NSTextField)?.stringValue else { return }
            field.onChange(text)
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): field.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): field.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): field.onReturn()
            case #selector(NSResponder.cancelOperation(_:)): field.onEscape()
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
