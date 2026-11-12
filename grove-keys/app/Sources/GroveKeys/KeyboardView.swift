import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// One key the editor is open on.
struct EditTarget: Equatable, Identifiable {
    var layerID: String
    /// The AeroSpace key text in the layer's mode ("alt-1", "hyper-t", "r", "alt-shift-h").
    var shortcut: String
    var id: String { layerID + " " + shortcut }
}

/// The Keyboard tab (spec §7, mockup §1): the layer picker with binding
/// counts, the MacBook keyboard for that layer, bindings that have no cap,
/// and the legend. Arrows or Ctrl+H/J/K/L move between keys and, past the
/// bottom row, the bindings listed under the keyboard; Return or Space opens
/// the editor; Esc closes the editor, then the window.
///
/// ⌘← and ⌘→ show the previous and next layer. Those two because nothing
/// else has them here: the tabs are ⌘1 and ⌘2, AeroSpace's bindings are on
/// ⌥ (⌥←/→ would be its to take), the recorder is on the other tab, and
/// unlike ⌘[ and ⌘] they are the same keys on every keyboard layout.
struct KeyboardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var hasKeys: Bool
    /// False until the keyboard is used to move, and after a click (`keyboardFocusRing`).
    @Environment(\.focusRingShown) private var ringShown

    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private var layerID = State<String?>(initialValue: nil)
    private var focused = State<String?>(initialValue: nil)
    private var showFocus = State(initialValue: false)
    private var editing = State<EditTarget?>(initialValue: nil)
    private var host = State(initialValue: HostWindow())
    /// The keys were taken for this opening of the window.
    private var tookKeys = State(initialValue: false)

    /// Inside the window margins; the grid takes its own padding out of this.
    static let keyboardWidth: CGFloat = WindowView.width - 2 * GroveSpace.s24
    static let capHeight: CGFloat = 54

    init(model: AppModel) {
        self.model = model
    }

    /// The "No modifier" layer only when it has bindings.
    private var layers: [Layer] {
        model.layers.filter { $0.id != "none" || !$0.bindings.isEmpty }
    }

    private var current: Layer? {
        let all = layers
        if let id = layerID.wrappedValue, let l = all.first(where: { $0.id == id }) { return l }
        // At first: the first layer with bindings (Option on the shipped file).
        return all.first { !$0.bindings.isEmpty } ?? all.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s16) {
            layerPicker
            if let layer = current {
                keyboard(layer)
                extras(layer)
            }
            legend
        }
        .padding(.horizontal, GroveSpace.s24)
        .padding(.top, GroveWindow.contentGap)
        .padding(.bottom, GroveSpace.s24)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($hasKeys)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onAppear { hasKeys = true }
        // A click anywhere in the window hides the box, as it hides the focus ring.
        .onChange(of: ringShown) { _, shown in
            if !shown { showFocus.wrappedValue = false }
        }
        // `onAppear` is too early in a window that is still opening: with
        // "Keyboard navigation" on, macOS then gives the keys to the first
        // tab button and the arrows do nothing. Taken again once the window
        // is key, once for each opening.
        .background(WindowAccessor { [host, tookKeys, keys = $hasKeys] window in
            host.wrappedValue.attach(window) { event in
                switch event {
                case .becameKey:
                    guard !tookKeys.wrappedValue else { return }
                    tookKeys.wrappedValue = true
                    DispatchQueue.main.async { keys.wrappedValue = true }
                case .willClose:
                    tookKeys.wrappedValue = false
                case .mouseDown, .keyDown, .resignedKey:
                    break
                }
            }
        })
        .onChange(of: model.layers) { _, _ in
            // A key that no longer exists (an edit elsewhere) closes its editor.
            if let target = editing.wrappedValue, !layers.contains(where: { $0.id == target.layerID }) {
                editing.wrappedValue = nil
            }
        }
    }

    // MARK: Layer picker

    private var layerPicker: some View {
        HStack(spacing: GroveSpace.s4) {
            Text("LAYER")
                .font(GroveFont.mono(GroveType.finePrint))
                .tracking(1)
                .foregroundStyle(theme.quiet)
                .padding(.trailing, GroveSpace.s8)
                .accessibilityHidden(true)
            GroveSegmented("Layer", segments: layers.map {
                GroveSegment($0.id, $0.title, detail: String($0.bindings.count))
            }, selection: current?.id, style: .bare) { show(layer: $0) }
        }
    }

    private func show(layer id: String) {
        layerID.wrappedValue = id
        editing.wrappedValue = nil
    }

    // MARK: Keyboard

    private func keyboard(_ layer: Layer) -> some View {
        KeyboardGrid(layer: layer, width: Self.keyboardWidth, capHeight: Self.capHeight) { _, name, legend, width, height in
            let target = EditTarget(layerID: layer.id,
                                    shortcut: KeyboardLayout.shortcut(layerID: layer.id, key: name))
            KeyCapView(legend: legend, binding: layer.bindings[name], isModifier: false, held: false,
                       focused: showFocus.wrappedValue && focused.wrappedValue == name,
                       width: width, height: height)
                .contentShape(Rectangle())
                .onTapGesture {
                    focused.wrappedValue = name
                    showFocus.wrappedValue = false
                    editing.wrappedValue = target
                }
                // A trait, not a `Button`: a button could take the keyboard
                // from this view, and with it the arrows.
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { editing.wrappedValue = target }
                .popover(isPresented: presented(target), arrowEdge: .bottom) {
                    editor(target, layer: layer)
                }
        }
    }

    private func presented(_ target: EditTarget) -> Binding<Bool> {
        Binding(get: { editing.wrappedValue == target },
                set: { if !$0, editing.wrappedValue == target { editing.wrappedValue = nil } })
    }

    private func editor(_ target: EditTarget, layer: Layer) -> some View {
        KeyEditorPopover(model: model, target: target, layerTitle: layer.title)
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
    }

    // MARK: Bindings without a cap

    /// Escape (the function row) and, in a mode, keys with modifiers
    /// ("alt-shift-h"): listed under the keyboard, not drawn on caps.
    private func extras(_ layer: Layer) -> some View {
        let rows = Self.extraBindings(layer)
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: GroveSpace.s8) {
                    Text("NOT ON THE KEYBOARD")
                        .font(GroveFont.mono(GroveType.finePrint)).tracking(1)
                        .foregroundStyle(theme.quiet)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GroveSpace.s8, alignment: .leading),
                                             count: KeyboardLayout.extraColumns),
                              alignment: .leading, spacing: GroveSpace.s4) {
                        ForEach(rows, id: \.key) { binding in
                            extraRow(binding, layer: layer)
                        }
                    }
                }
            }
        }
    }

    /// The layer's bindings that have no cap, in the order they are listed
    /// (and the arrows walk them).
    private static func extraBindings(_ layer: Layer) -> [KeyBinding] {
        layer.bindings.values.filter { !KeyboardLayout.names.contains($0.key) }.sorted { $0.key < $1.key }
    }

    /// What the editor opens on for a cap's name or a listed binding's key.
    private static func target(_ name: String, layer: Layer) -> EditTarget {
        if !KeyboardLayout.names.contains(name), case .aerospace(_, let key) = layer.bindings[name]?.source {
            return EditTarget(layerID: layer.id, shortcut: key)
        }
        return EditTarget(layerID: layer.id, shortcut: KeyboardLayout.shortcut(layerID: layer.id, key: name))
    }

    private func extraRow(_ binding: KeyBinding, layer: Layer) -> some View {
        let target = Self.target(binding.key, layer: layer)
        let shortcut = target.shortcut
        let tint = theme.named(binding.kind.tint)
        return Button { editing.wrappedValue = target } label: {
            HStack(spacing: GroveSpace.s8) {
                Text(Shortcut(aerospace: shortcut)?.symbols ?? shortcut)
                    .font(GroveFont.mono(GroveType.body))
                    .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
                    .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
                // The kind's colour: on the label in dark; in light, where it
                // can't be read as text, on a legend swatch before an fg label.
                if theme.isLight {
                    swatch(tint, binding.label).lineLimit(1)
                } else {
                    Text(binding.label)
                        .foregroundStyle(Color(tint))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusBox(showFocus.wrappedValue && focused.wrappedValue == binding.key,
                  cornerRadius: GroveRadius.control, outset: 3)
        .help(binding.words)
        .accessibilityLabel((Shortcut(aerospace: shortcut)?.symbols ?? shortcut) + ", "
                            + (binding.words.isEmpty ? binding.label : binding.words))
        .popover(isPresented: presented(target), arrowEdge: .bottom) {
            editor(target, layer: layer)
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: GroveSpace.s16) {
            swatch(theme.green, "workspace")
            swatch(theme.aqua, "focus · move")
            swatch(theme.blue, "launcher")
            swatch(theme.yellow, "layout · resize")
            swatch(theme.orange, "mode · service")
            swatch(theme.bg2, "free", outlined: true)
        }
        .font(GroveFont.mono(GroveType.body))
        .foregroundStyle(theme.quiet)
    }

    /// `outlined`: a background colour's swatch, which needs its outline in light.
    private func swatch(_ color: RGB, _ text: String, outlined: Bool = false) -> some View {
        HStack(spacing: GroveSpace.s8) {
            RoundedRectangle(cornerRadius: GroveRadius.inline).fill(Color(color)).frame(width: 10, height: 10)
                .lightOutline(cornerRadius: GroveRadius.inline, when: outlined)
            Text(text)
        }
    }

    // MARK: Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            if editing.wrappedValue != nil {
                editing.wrappedValue = nil
            } else {
                dismissWindow(id: MenuBarView.windowID)
            }
            return .handled
        }
        // ⌘← and ⌘→: the previous and the next layer (no wrap).
        if press.modifiers.contains(.command) {
            guard press.key == .leftArrow || press.key == .rightArrow else { return .ignored }
            let all = layers
            let at = all.firstIndex { $0.id == current?.id }
            if let next = GroveSegmentedStep.index(from: at, step: press.key == .leftArrow ? -1 : 1,
                                                   enabled: all.map { _ in true }) {
                show(layer: all[next].id)
            }
            return .handled
        }
        let extras = current.map { Self.extraBindings($0).map(\.key) } ?? []
        // The key the box is on, if this layer still has it (a listed
        // binding is the layer's own).
        let here = focused.wrappedValue.flatMap { KeyboardLayout.names.contains($0) || extras.contains($0) ? $0 : nil }
        if press.key == .return || press.key == .space {
            guard let name = here, let layer = current else { return .ignored }
            editing.wrappedValue = Self.target(name, layer: layer)
            return .handled
        }
        guard let direction = Self.direction(press) else { return .ignored }
        if showFocus.wrappedValue, let name = here {
            if let next = KeyboardLayout.neighbor(of: name, direction, extras: extras) { focused.wrappedValue = next }
        } else {
            // The first press shows the box where it is (or on 1).
            if here == nil { focused.wrappedValue = KeyboardLayout.firstKey }
            showFocus.wrappedValue = true
        }
        return .handled
    }

    /// An arrow or Ctrl+H/J/K/L as a direction (the Bindings tab uses it too).
    static func direction(_ press: KeyPress) -> KeyboardLayout.Direction? {
        switch press.key {
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .upArrow: return .up
        case .downArrow: return .down
        default: break
        }
        guard press.modifiers.contains(.control) else { return nil }
        // Ctrl+letter may arrive as the letter or as its control character.
        switch press.characters.lowercased().first ?? press.key.character {
        case "h", "\u{08}": return .left
        case "j", "\u{0A}": return .down
        case "k", "\u{0B}": return .up
        case "l", "\u{0C}": return .right
        default: return nil
        }
    }
}
