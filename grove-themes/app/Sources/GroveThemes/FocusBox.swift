import AppKit
import GroveThemesCore
import GroveUI
import SwiftUI

/// Keyboard navigation for the dropdown and the gallery (the rules are
/// `KeyboardFocus` / `FocusGrid` in Core): makes the view focusable without the
/// system focus ring, turns arrows and Ctrl+h/j/k/l, Return/Space and Esc into
/// focus commands, and hides the box on a mouse click in the window or when
/// the window opens, closes or stops being key.
struct KeyboardNavigation: ViewModifier {
    let focus: Binding<KeyboardFocus>
    let current: String
    /// The logo and wallpaper rows as shown (empty while there's no list).
    let logos: [String]
    let wallpapers: [String]
    let schemesDisabled: Bool
    let activate: (FocusGrid.Item) -> Void
    @FocusState private var hasKeys: Bool
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var host = State(initialValue: HostWindow())

    init(focus: Binding<KeyboardFocus>, current: String, logos: [String], wallpapers: [String],
         schemesDisabled: Bool, activate: @escaping (FocusGrid.Item) -> Void) {
        self.focus = focus
        self.current = current
        self.logos = logos
        self.wallpapers = wallpapers
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
                switch focus.wrappedValue.handle(command, current: current, logos: logos, wallpapers: wallpapers,
                                                 schemesDisabled: schemesDisabled) {
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
                host.wrappedValue.attach(window) { event in
                    switch event {
                    case .keyDown:
                        break
                    case .mouseDown, .resignedKey, .willClose:
                        focus.wrappedValue.hide()
                    case .becameKey:
                        focus.wrappedValue.hide()
                        hasKeysBinding.wrappedValue = true
                    }
                }
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
    func keyboardNavigation(_ focus: Binding<KeyboardFocus>, list: SchemeList?, schemesDisabled: Bool,
                            activate: @escaping (FocusGrid.Item) -> Void) -> some View {
        modifier(KeyboardNavigation(focus: focus, current: list?.current ?? "", logos: list?.logos ?? [],
                                    wallpapers: list?.wallpapers ?? [], schemesDisabled: schemesDisabled,
                                    activate: activate))
    }
}
