import GroveThemesCore
import SwiftUI

/// One value a `GroveSelect` offers.
public struct GroveSelectOption<Value: Hashable>: Identifiable {
    public var value: Value
    public var title: String
    public var id: Value { value }

    public init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// Grove's one select: a label in JetBrains Mono that opens the Grove menu
/// (`GroveMenuList`) of the values under it, the current one ticked. The
/// label is the standard pill, the value and a chevron (`GroveSelectPill`),
/// or the caller's own (a Monitors cell). A plain button: a click opens the
/// list, and so does Space when it has the keyboard focus; in the list the
/// keys are the menu's (↑↓, Return, Esc, a letter). VoiceOver reads a pop-up
/// button named `name` whose value is the current one, expanded while its
/// list is up; its press (VO-Space) and Show Menu open the list. That
/// button is the AppKit view behind the label (`GroveMenuListAnchorView`):
/// SwiftUI has no pop-up role, and a represented `Picker` would open the
/// native menu. The chevron is not read.
///
/// Not `Picker(.menu)` or `Menu`, on purpose: the native pop-up button
/// draws its label in the system font whatever `.font` says, and at its
/// smallest is wider than the 38–40 pt Monitors cells; and a native menu
/// can't take the Grove menu's card, type or rows (spec
/// 2026-11-13-grove-context-menus-design).
public struct GroveSelect<Value: Hashable, Label: View>: View {
    let name: String
    let options: [GroveSelectOption<Value>]
    let selection: Value?
    let valueText: String?
    let onSelect: (Value) -> Void
    let label: Label
    @Environment(\.theme) private var theme
    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private let anchor = State(initialValue: GroveMenuListAnchor.Box())

    /// `selection` nil: nothing is ticked. `valueText`: what VoiceOver reads
    /// as the value, when it isn't the selected option's title.
    public init(_ name: String, options: [GroveSelectOption<Value>], selection: Value?,
                valueText: String? = nil, onSelect: @escaping (Value) -> Void,
                @ViewBuilder label: () -> Label) {
        self.name = name
        self.options = options
        self.selection = selection
        self.valueText = valueText
        self.onSelect = onSelect
        self.label = label()
    }

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    public var body: some View {
        let options = options, selection = selection, onSelect = onSelect
        Button { anchor.wrappedValue.view?.showUnder() } label: { label }
            .buttonStyle(.plain)
            // VoiceOver reads the view behind instead: a pop-up button.
            .accessibilityHidden(true)
            .background(GroveMenuListAnchor(
                box: anchor.wrappedValue, theme: theme, rightClick: false,
                rows: { GroveSelectOption.menuRows(options, selection: selection) },
                onChoose: { id in if let value = GroveSelectOption.value(of: id, in: options) { onSelect(value) } },
                // The list's top-left a little under the label's bottom-left.
                popUp: .init(label: name, value: valueText ?? selectedTitle, gap: GroveSpace.s4)))
    }
}

extension GroveSelectOption {
    /// The options as the list's rows, in order, the selected one ticked. A
    /// row's id is its option's place ("0", "1", …): a value needn't be text.
    public static func menuRows(_ options: [GroveSelectOption], selection: Value?) -> [GroveMenuListRow] {
        options.enumerated().map { index, option in
            GroveMenuListRow(id: String(index), title: option.title, checked: option.value == selection)
        }
    }

    /// The value of the row `id` of `menuRows`; nil for an id it hasn't.
    public static func value(of id: String, in options: [GroveSelectOption]) -> Value? {
        guard let index = Int(id), options.indices.contains(index) else { return nil }
        return options[index].value
    }
}

extension GroveSelect where Label == GroveSelectPill {
    /// With the standard pill: the selected option's title and the chevron.
    public init(_ name: String, options: [GroveSelectOption<Value>], selection: Value?,
                onSelect: @escaping (Value) -> Void) {
        let title = options.first { $0.value == selection }?.title ?? ""
        self.init(name, options: options, selection: selection, onSelect: onSelect) {
            GroveSelectPill(title)
        }
    }
}

/// The standard label of a `GroveSelect`: the value and `GroveIcon`'s menu
/// chevron on a bg0 pill with a `border` outline.
public struct GroveSelectPill: View {
    let text: String
    @Environment(\.theme) private var theme

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        (Text(text + " ") + GroveIcon.text(.menu, size: GroveType.label))
            .font(GroveFont.mono(GroveType.label))
            .foregroundStyle(Color(theme.fg))
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
    }
}
