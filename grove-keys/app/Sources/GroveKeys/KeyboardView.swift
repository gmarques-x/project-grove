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
/// and the legend. Arrows or Ctrl+H/J/K/L move between keys, Return opens the
/// editor, Esc closes the editor, then the window.
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
        .padding(.top, GroveSpace.s8)
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
        let rows = layer.bindings.values.filter { !KeyboardLayout.names.contains($0.key) }.sorted { $0.key < $1.key }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: GroveSpace.s8) {
                    Text("NOT ON THE KEYBOARD")
                        .font(GroveFont.mono(GroveType.finePrint)).tracking(1)
                        .foregroundStyle(theme.quiet)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GroveSpace.s8, alignment: .leading), count: 4),
                              alignment: .leading, spacing: GroveSpace.s4) {
                        ForEach(rows, id: \.key) { binding in
                            extraRow(binding, layer: layer)
                        }
                    }
                }
            }
        }
    }

    private func extraRow(_ binding: KeyBinding, layer: Layer) -> some View {
        let shortcut: String
        switch binding.source {
        case .aerospace(_, let key): shortcut = key
        case .launcher: shortcut = KeyboardLayout.shortcut(layerID: layer.id, key: binding.key)
        }
        let target = EditTarget(layerID: layer.id, shortcut: shortcut)
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
        if press.key == .return {
            guard let name = focused.wrappedValue, let layer = current else { return .ignored }
            editing.wrappedValue = EditTarget(layerID: layer.id,
                                              shortcut: KeyboardLayout.shortcut(layerID: layer.id, key: name))
            return .handled
        }
        guard let direction = Self.direction(press) else { return .ignored }
        if showFocus.wrappedValue, let name = focused.wrappedValue {
            if let next = KeyboardLayout.neighbor(of: name, direction) { focused.wrappedValue = next }
        } else {
            // The first press shows the box where it is (or on 1).
            if focused.wrappedValue == nil { focused.wrappedValue = KeyboardLayout.firstKey }
            showFocus.wrappedValue = true
        }
        return .handled
    }

    private static func direction(_ press: KeyPress) -> KeyboardLayout.Direction? {
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
