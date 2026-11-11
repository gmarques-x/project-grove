import AppKit
import SwiftUI

/// Whether a window shows keyboard focus: not when it opens and not after a
/// mouse click, only once the keyboard is used to move around. Pure.
public struct FocusRing: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// A key went down. `characters` without modifiers, as
        /// `NSEvent.charactersIgnoringModifiers` has them.
        case key(code: UInt16, characters: String, command: Bool, control: Bool, option: Bool)
        case mouseDown
        case windowClosed
    }

    public private(set) var shown = false

    public init() {}

    public mutating func handle(_ event: Event) {
        switch event {
        case .key(let code, let characters, let command, let control, let option):
            if Self.moves(code: code, characters: characters, command: command, control: control, option: option) {
                shown = true
            }
        case .mouseDown, .windowClosed:
            shown = false
        }
    }

    static let tab: UInt16 = 48
    static let arrows: ClosedRange<UInt16> = 123...126

    /// A key that moves the focus: Tab and ⇧Tab, the arrows, and the Grove
    /// apps' Ctrl+H/J/K/L. Not typing, Return, Space or Esc, and nothing with
    /// ⌘ or ⌥ (shortcuts: ⌘1, AeroSpace's ⌥Tab).
    public static func moves(code: UInt16, characters: String, command: Bool, control: Bool, option: Bool) -> Bool {
        guard !command, !option else { return false }
        if code == tab || arrows.contains(code) { return true }
        // Ctrl+letter may arrive as the letter or as its control character.
        return control && ["h", "j", "k", "l", "\u{08}", "\n", "\u{0B}", "\u{0C}"].contains(characters.lowercased())
    }
}

private struct FocusRingShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the window's keyboard focus is hidden (see
    /// `keyboardFocusRing`): a view that draws its own `.focusBox` hides it
    /// too. True where no `keyboardFocusRing` is above.
    public var focusRingShown: Bool {
        get { self[FocusRingShownKey.self] }
        set { self[FocusRingShownKey.self] = newValue }
    }
}

/// See `View.keyboardFocusRing()`.
private struct KeyboardFocusRing: ViewModifier {
    /// `State` used directly: the Command Line Tools ship no SwiftUI macros.
    private var ring = State(initialValue: FocusRing())
    private var host = State(initialValue: HostWindow())

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled(!ring.wrappedValue.shown)
            .environment(\.focusRingShown, ring.wrappedValue.shown)
            .background(WindowAccessor { [ring, host] window in
                host.wrappedValue.attach(window, childWindows: true) { event in
                    var next = ring.wrappedValue
                    switch event {
                    case .mouseDown:
                        next.handle(.mouseDown)
                    case .keyDown(let key):
                        let flags = key.modifierFlags
                        next.handle(.key(code: key.keyCode, characters: key.charactersIgnoringModifiers ?? "",
                                         command: flags.contains(.command), control: flags.contains(.control),
                                         option: flags.contains(.option)))
                    case .willClose:
                        next.handle(.windowClosed)
                    case .becameKey, .resignedKey:
                        break
                    }
                    if next != ring.wrappedValue { ring.wrappedValue = next }
                }
            })
    }
}

extension View {
    /// On a window's root view: keyboard focus (the system's ring on a
    /// control, a view's own `.focusBox`) shows only for someone using the
    /// keyboard. The window opens with none, the first Tab or arrow shows it,
    /// and a mouse click hides it again. Without this, with "Keyboard
    /// navigation" on in System Settings, a window opens with a ring on its
    /// first control.
    public func keyboardFocusRing() -> some View {
        modifier(KeyboardFocusRing())
    }
}
