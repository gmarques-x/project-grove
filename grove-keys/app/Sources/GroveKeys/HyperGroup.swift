import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// Hyper key: on/off, what a tap sends, the two timings (spec §5), and what
/// the right Option key does.
struct HyperGroup: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let h = model.keys.hyper
        BindingsGroup(title: "Hyper key", note: "Caps Lock") {
            setting("Hyper on") {
                Toggle("", isOn: Binding(get: { h.enabled }, set: { on in update { $0.enabled = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color(theme.green))
                    .labelsHidden()
            }
            setting("Tap alone sends") {
                Menu {
                    Button("Escape") { update { $0.tap = .escape } }
                    Button("None") { update { $0.tap = .none } }
                } label: {
                    pill(h.tap == .escape ? "Escape ▾" : "None ▾")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            setting("A tap is shorter than") {
                MsField(value: h.tapMs) { ms in update { $0.tapMs = ms } }.id(h.tapMs)
            }
            setting("Cheat sheet after holding") {
                MsField(value: h.cheatsheetMs) { ms in update { $0.cheatsheetMs = ms } }.id(h.cheatsheetMs)
                    .help("0 = no cheat sheet")
            }
            setting("Right ⌥ types characters") {
                Toggle("", isOn: Binding(get: { h.rightOption == .characters },
                                         set: { on in update { $0.rightOption = on ? .characters : .shortcuts } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color(theme.green))
                    .labelsHidden()
                    .help("On: the right ⌥ types @ € and the layout's other characters, and only the left ⌥ runs shortcuts. Off: both ⌥ keys run shortcuts")
            }
        }
    }

    private func update(_ change: @escaping (inout HyperSettings) -> Void) {
        model.edit { keys in
            var h = keys.hyper
            change(&h)
            keys.setHyper(h)
        }
    }

    private func setting<V: View>(_ title: String, @ViewBuilder _ control: () -> V) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .font(GroveFont.mono(12))
        .padding(.horizontal, 6).padding(.vertical, GroveSpace.s4)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(GroveFont.mono(11.5))
            .foregroundStyle(Color(theme.fg))
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, 3)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
    }
}

/// "200 ms": a whole number ≥ 0; written on Return or when focus leaves,
/// otherwise put back. A bad value turns the border red and isn't written.
private struct MsField: View {
    let value: Int
    let onCommit: (Int) -> Void
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    private var text: State<String>

    init(value: Int, onCommit: @escaping (Int) -> Void) {
        self.value = value
        self.onCommit = onCommit
        text = State(initialValue: String(value))
    }

    var body: some View {
        let valid = HyperSettings.milliseconds(text.wrappedValue) != nil
        HStack(spacing: GroveSpace.s4) {
            TextField("", text: text.projectedValue)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .focused($focused)
                .onSubmit(commit)
            Text("ms").foregroundStyle(theme.quiet)
        }
        .font(GroveFont.mono(11.5))
        .padding(.horizontal, GroveSpace.s8).padding(.vertical, 3)
        .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
        .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(valid ? theme.line : Color(theme.red), lineWidth: 1))
        .help(valid ? "Milliseconds · ↩ saves" : "A whole number of milliseconds, 0 or more")
        .onChange(of: focused) { _, now in if !now { commit() } }
    }

    private func commit() {
        if let ms = HyperSettings.milliseconds(text.wrappedValue) {
            if ms != value { onCommit(ms) } else { text.wrappedValue = String(value) }
        } else {
            text.wrappedValue = String(value)
        }
    }
}
