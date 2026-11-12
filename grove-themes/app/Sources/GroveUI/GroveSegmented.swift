import GroveThemesCore
import SwiftUI

/// One choice of a `GroveSegmented`.
public struct GroveSegment<Value: Hashable>: Identifiable {
    public var value: Value
    public var title: String
    /// Drawn in the title's place (the title is then what VoiceOver and the
    /// tooltip say): a segment that is a picture, as the one-pane/two-pane switch.
    public var icon: GroveIcon.Name?
    /// A second label after the title, smaller and quieter (a count).
    public var detail: String?
    /// False: drawn at `GroveSegmentedMetrics.disabledOpacity`, skipped by
    /// the arrows, and a click does nothing.
    public var enabled: Bool
    /// The tooltip (why it is disabled).
    public var help: String
    /// With ⌘, chooses this segment from anywhere in the window (the tabs' ⌘1, ⌘2).
    public var shortcut: KeyEquivalent?

    public var id: Value { value }

    public init(_ value: Value, _ title: String, icon: GroveIcon.Name? = nil, detail: String? = nil,
                enabled: Bool = true, help: String = "", shortcut: KeyEquivalent? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
        self.detail = detail
        self.enabled = enabled
        self.help = help
        self.shortcut = shortcut
    }
}

/// What a `GroveSegmented` sits on.
public enum GroveSegmentedStyle: Sendable {
    /// On a pill of its own, in that background: bg1 (`.panel`: the window's
    /// tabs) or bg0 (`.base`: a well in a popover).
    case pill(Surface)
    /// No pill behind the segments (the layer picker).
    case bare
    /// A 1 pt line round the segments and nothing behind them: a small
    /// switch in a window's header, on the window's own background.
    case outlined
}

/// What a `GroveSegmented` is to VoiceOver.
public enum GroveSegmentedRole: Sendable {
    /// Tabs: the segments switch what is shown below.
    case tabs
    /// One value of several (a radio group).
    case choice
}

/// The numbers a `GroveSegmented` is drawn with.
public enum GroveSegmentedMetrics {
    /// A segment that can't be chosen: faded to this.
    public static let disabledOpacity: Double = 0.4
    /// A segment that is an icon: a little wider than a 24 pt control is
    /// tall, and 4 pt less high, so the outlined switch is 24 pt in all.
    public static let iconSegment = CGSize(width: GroveSpace.s24 + GroveSpace.s4, height: GroveSpace.s24 - GroveSpace.s4)
}

/// Which segment ←/→ move to. Pure.
public enum GroveSegmentedStep {
    /// The next enabled segment `step` (−1, 1) from `current`; stops at the
    /// ends (no wrap), and nil when there is none that way. With no current
    /// segment, the first enabled one.
    public static func index(from current: Int?, step: Int, enabled: [Bool]) -> Int? {
        guard let current, enabled.indices.contains(current) else { return enabled.firstIndex(of: true) }
        var i = current + step
        while enabled.indices.contains(i) {
            if enabled[i] { return i }
            i += step
        }
        return nil
    }
}

/// Grove's one segmented control: the window's tabs, the layer picker, the
/// key editor's kind. Segments in a row, the chosen one lit (bg3, outlined in
/// light), a 4 pt segment inside a 6 pt pill so the corners are concentric.
///
/// One Tab stop (with "Keyboard navigation" on, as for any control); with the
/// focus on it ←/→ choose the previous and next segment, and it wears the
/// focus box. A click chooses without taking the keyboard from the view that
/// has it. VoiceOver sees a tab bar or a group, its segments as buttons, the
/// chosen one selected.
///
/// Not `Picker(.segmented)`, on purpose. The native control draws its labels
/// in the system font whatever `.font` says (all Grove text is JetBrains
/// Mono), can't set a second label style inside a segment (the layer's
/// count), can't disable one segment, and makes every segment as wide as the
/// widest. The owner compared renders of both and chose this one; it is
/// built once, here.
public struct GroveSegmented<Value: Hashable>: View {
    let label: String
    let segments: [GroveSegment<Value>]
    let selection: Value?
    let style: GroveSegmentedStyle
    let role: GroveSegmentedRole
    let fillsWidth: Bool
    let onSelect: (Value) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.focusRingShown) private var ringShown
    @FocusState private var focused: Bool

    /// `label`: what VoiceOver calls the group ("Layer"). `fillsWidth`: the
    /// segments share the width equally (the key editor); otherwise each is
    /// as wide as its text.
    public init(_ label: String, segments: [GroveSegment<Value>], selection: Value?,
                style: GroveSegmentedStyle, role: GroveSegmentedRole = .choice, fillsWidth: Bool = false,
                onSelect: @escaping (Value) -> Void) {
        self.label = label
        self.segments = segments
        self.selection = selection
        self.style = style
        self.role = role
        self.fillsWidth = fillsWidth
        self.onSelect = onSelect
    }

    public var body: some View {
        let row = HStack(spacing: fillsWidth || isOutlined ? GroveSpace.s2 : GroveSpace.s4) {
            ForEach(segments) { segment in
                self.segment(segment)
            }
        }
        container(row)
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .focused($focused)
            .focusBox(focused && ringShown, cornerRadius: GroveRadius.control, outset: 3)
            .onKeyPress(phases: [.down, .repeat]) { press in
                // The bare arrows only: ⌘← and the like are someone else's.
                guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                switch press.key {
                case .leftArrow: return move(-1)
                case .rightArrow: return move(1)
                default: return .ignored
                }
            }
            .background { shortcuts }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(role == .tabs ? .isTabBar : [])
    }

    @ViewBuilder
    private func container(_ row: some View) -> some View {
        switch style {
        case .pill(let surface):
            row.padding(GroveSpace.s2)
                .background(Color(surface == .panel ? theme.bg1 : theme.bg0),
                            in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .lightOutline(cornerRadius: GroveRadius.control)
        case .bare:
            row
        case .outlined:
            row.padding(GroveSpace.s2)
                .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
        }
    }

    private var isOutlined: Bool {
        if case .outlined = style { return true }
        return false
    }

    /// A segment's inside: its icon in a fixed cell, or its title (and detail).
    @ViewBuilder
    private func label(_ segment: GroveSegment<Value>, on: Bool) -> some View {
        if let icon = segment.icon {
            GroveIcon(icon, size: GroveType.label)
                .foregroundStyle(on ? Color(theme.fg) : theme.quiet)
                .frame(width: GroveSegmentedMetrics.iconSegment.width, height: GroveSegmentedMetrics.iconSegment.height)
        } else {
            HStack(spacing: GroveSpace.s4) {
                Text(segment.title).foregroundStyle(on ? Color(theme.fg) : theme.quiet)
                if let detail = segment.detail {
                    Text(detail)
                        .font(GroveFont.mono(GroveType.finePrint))
                        .foregroundStyle(theme.quiet(dark: 0.8))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .padding(.horizontal, fillsWidth ? 0 : GroveSpace.s12).padding(.vertical, GroveSpace.s4)
        }
    }

    private func segment(_ segment: GroveSegment<Value>) -> some View {
        let on = segment.value == selection
        return label(segment, on: on)
        // Lit as on a panel wherever it sits: the three sites were tuned at bg3.
        // (The outlined switch sits on the window itself: lit as on bg0.)
        .background(on ? theme.selectedFill(on: isOutlined ? .base : .panel) : .clear,
                    in: RoundedRectangle(cornerRadius: GroveRadius.inline))
        .lightOutline(cornerRadius: GroveRadius.inline, when: on)
        .contentShape(Rectangle())
        .onTapGesture { if segment.enabled { onSelect(segment.value) } }
        .opacity(segment.enabled ? 1 : GroveSegmentedMetrics.disabledOpacity)
        .help(segment.help.isEmpty && segment.icon != nil ? segment.title : segment.help)
        // A trait, not a `Button`: each button would be a Tab stop of its own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.detail.map { "\(segment.title), \($0)" } ?? segment.title)
        .accessibilityHint(segment.help)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if segment.enabled { onSelect(segment.value) } }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let current = segments.firstIndex { $0.value == selection }
        if let next = GroveSegmentedStep.index(from: current, step: step, enabled: segments.map(\.enabled)),
           next != current {
            onSelect(segments[next].value)
        }
        // At an end too: the arrow is the group's, not the view's behind it.
        return .handled
    }

    /// The segments' ⌘ shortcuts: buttons that aren't seen, clicked or
    /// focused, since `.keyboardShortcut` needs a button to hang on.
    private var shortcuts: some View {
        ZStack {
            ForEach(segments) { segment in
                if let key = segment.shortcut {
                    Button("") { if segment.enabled { onSelect(segment.value) } }
                        .keyboardShortcut(key, modifiers: .command)
                        .buttonStyle(.plain)
                        .focusable(false)
                }
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
