import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// Hyper key: on/off, what a tap sends, the two timings (spec §5), the launcher's
/// key, and what the right Option key does.
struct HyperGroup: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let h = model.keys.hyper
        BindingsGroup(title: "Hyper key", note: "Caps Lock") {
            setting("Hyper on") {
                toggle("Hyper on", Binding(get: { h.enabled }, set: { on in update { $0.enabled = on } }))
            }
            setting("Tap alone sends") {
                GroveSelect("Tap alone sends",
                            options: [GroveSelectOption(TapAction.escape, "Escape"), GroveSelectOption(.none, "None")],
                            selection: h.tap) { tap in update { $0.tap = tap } }
                    .fixedSize()
            }
            setting("A tap is shorter than") {
                MsField("A tap is shorter than, in milliseconds", value: h.tapMs) { ms in update { $0.tapMs = ms } }.id(h.tapMs)
            }
            setting("Cheat sheet after holding") {
                MsField("Cheat sheet after holding, in milliseconds", value: h.cheatsheetMs) { ms in update { $0.cheatsheetMs = ms } }.id(h.cheatsheetMs)
                    .help("0 = no cheat sheet")
            }
            setting("⌘Space opens the launcher") {
                toggle("⌘Space opens the launcher",
                       Binding(get: { h.launcher == .cmdSpace },
                               set: { on in update { $0.launcher = on ? .cmdSpace : .none } }))
                    .help("On: ⌘Space opens the Grove Launcher, not Spotlight. Off: ⌘Space is macOS's again")
            }
            setting("Right ⌥ types characters") {
                toggle("Right Option types characters",
                       Binding(get: { h.rightOption == .characters },
                               set: { on in update { $0.rightOption = on ? .characters : .shortcuts } }))
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

    /// A row's switch. The title is the row's own text again, hidden: it is
    /// what VoiceOver calls the switch.
    private func toggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Color(theme.green))
            .labelsHidden()
    }

    // Rows laid by hand, not a `Form`: a grouped form brings the system's row
    // chrome and fonts into a group drawn like the Bindings groups beside it.
    private func setting<V: View>(_ title: String, @ViewBuilder _ control: () -> V) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .font(GroveFont.mono(GroveType.label))
        .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
    }
}

/// "200 ms": a whole number ≥ 0; written on Return or when focus leaves,
/// otherwise put back. A bad value turns the border red and isn't written.
///
/// Text parsed by hand, not `TextField(value:format:)`, on purpose: a
/// formatted field hands over nothing until it is committed and puts a bad
/// entry back itself, so the border could not turn red while it is typed.
private struct MsField: View {
    /// What VoiceOver calls the field (the row's text).
    let title: String
    let value: Int
    let onCommit: (Int) -> Void
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    private var text: State<String>

    init(_ title: String, value: Int, onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.value = value
        self.onCommit = onCommit
        text = State(initialValue: String(value))
    }

    var body: some View {
        let valid = HyperSettings.milliseconds(text.wrappedValue) != nil
        HStack(spacing: GroveSpace.s4) {
            TextField("", text: text.projectedValue)
                .textFieldStyle(.plain)
                .accessibilityLabel(title)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .focused($focused)
                .onSubmit(commit)
            Text("ms").foregroundStyle(theme.quiet)
        }
        .font(GroveFont.mono(GroveType.label))
        .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
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
