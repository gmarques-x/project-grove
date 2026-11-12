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

/// Grove's one select: a label in JetBrains Mono that opens a native menu
/// of the values, the current one ticked by the system (an inline `Picker`
/// inside the `Menu`). The label is the standard pill, the value and a
/// chevron (`GroveSelectPill`), or the caller's own (a Monitors cell).
/// VoiceOver reads a pop-up button named `name` whose value is the current
/// one; the chevron is not read.
///
/// Not `Picker(.menu)`, on purpose: the native pop-up button draws its label
/// in the system font whatever `.font` says, and at its smallest is wider
/// than the 38–40 pt Monitors cells. The menu itself is the system's.
public struct GroveSelect<Value: Hashable, Label: View>: View {
    let name: String
    let options: [GroveSelectOption<Value>]
    let selection: Value?
    let valueText: String?
    let onSelect: (Value) -> Void
    let label: Label

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
        Menu {
            Picker(name, selection: Binding(get: { selection }, set: { if let value = $0 { onSelect(value) } })) {
                ForEach(options) { option in
                    Text(option.title).tag(Optional(option.value))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(name)
        .accessibilityValue(valueText ?? selectedTitle)
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
