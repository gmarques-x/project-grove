import GroveThemesCore
import SwiftUI

// The frame and the parts every dropdown of the Grove bar is built from
// (spec: grove-dotfiles/docs/specs/2026-11-12-bar-panels-design.md). A panel
// is a `BarPanel` holding sections separated by `PanelRule`s; the drawings
// (charts, meters) are in PanelCharts.swift. Shown by Grove Keys' panel host.

// MARK: Metrics

/// Sizes of the panels' parts and drawings, on the spacing scale where they
/// are layout, measured where they stand in for a system control.
public enum PanelMetrics {
    /// The panel's inner padding and the gap between its sections.
    public static let inset = GroveSpace.s12
    /// A history chart's height.
    public static let chart = GroveSpace.s24
    /// A chart line's width: a quarter over a point, so it holds against the
    /// 1 pt baseline under it.
    public static let chartLine: CGFloat = 1.25
    /// A meter's thickness (charge, memory, progress).
    public static let meter = GroveSpace.s8
    /// One core's bar.
    public static let coreBar = CGSize(width: GroveSpace.s8, height: GroveSpace.s24)
    /// An icon column, so rows of icons and words line up.
    public static let iconColumn = GroveSpace.s16
    /// The mini switch as AppKit draws it, for the stand-in (`PanelSwitch`).
    public static let switchSize = CGSize(width: 26, height: 15)
    /// The small slider's knob and track as AppKit draws them (`PanelSlider`).
    public static let sliderKnob: CGFloat = 14
    public static let sliderTrack = GroveSpace.s4
}

// MARK: Environment

/// Which of a panel's top corners follow a window border's corner instead of
/// the card radius. Set by the host when it places the panel on the tiled
/// windows' border lines; a panel never sets it.
public struct BarPanelShape: Equatable, Sendable {
    public var topLeading: CGFloat
    public var topTrailing: CGFloat

    public init(topLeading: CGFloat = GroveRadius.card, topTrailing: CGFloat = GroveRadius.card) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
    }

    /// Every corner the card's.
    public static let card = BarPanelShape()
}

private struct BarPanelShapeKey: EnvironmentKey { static let defaultValue = BarPanelShape.card }
private struct PanelSurfaceKey: EnvironmentKey { static let defaultValue = Surface.base }
private struct PanelStandInsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The corners of the `BarPanel` under here (the host's to set).
    public var barPanelShape: BarPanelShape {
        get { self[BarPanelShapeKey.self] }
        set { self[BarPanelShapeKey.self] = newValue }
    }

    /// What a panel's rows sit on, for `hoverFill(on:)`: `.base`, the panel's
    /// bg0.
    public var panelSurface: Surface {
        get { self[PanelSurfaceKey.self] }
        set { self[PanelSurfaceKey.self] = newValue }
    }

    /// True while a panel is drawn to an image and not shown (Grove Keys'
    /// `--render-panel`): AppKit draws a switch and a slider without their
    /// tint in a window that is not on screen, so `PanelSwitch` and
    /// `PanelSlider` draw a stand-in with the same measures.
    public var panelStandIns: Bool {
        get { self[PanelStandInsKey.self] }
        set { self[PanelStandInsKey.self] = newValue }
    }
}

// MARK: The frame

/// A dropdown of the Grove bar: bg0, the pills' orange 1 pt outline
/// (`panelOutline`), the card radius, 12 pt inside, its sections 12 pt
/// apart. A fixed width, as tall as its content. Body text and fg are set
/// for everything inside.
///
///     BarPanel(width: 248) {
///         PanelHeader(.battery, accent: theme.yellow, title: "Battery") { PanelValue("78%") }
///         PanelMeter(share: 0.78, accent: theme.yellow)
///         PanelRule()
///         PanelFooter("Battery Settings…") { … }
///     }
public struct BarPanel<Content: View>: View {
    let width: CGFloat
    let content: Content
    @Environment(\.theme) private var theme
    @Environment(\.barPanelShape) private var shape

    public init(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    private var outline: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: shape.topLeading, bottomLeadingRadius: GroveRadius.card,
                               bottomTrailingRadius: GroveRadius.card, topTrailingRadius: shape.topTrailing)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.inset) { content }
            .padding(PanelMetrics.inset)
            .frame(width: width, alignment: .topLeading)
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(Color(theme.fg))
            .background(Color(theme.bg0), in: outline)
            .overlay(outline.strokeBorder(theme.panelOutline, lineWidth: 1).allowsHitTesting(false))
            .environment(\.panelSurface, .base)
    }
}

/// A panel's first row: the item's symbol in its bar colour, the title, and
/// the headline (a `PanelValue`, a switch, a pair of chevrons) at the right.
public struct PanelHeader<Trailing: View>: View {
    let icon: GroveIcon.Name?
    let accent: RGB?
    let title: String
    let trailing: Trailing
    @Environment(\.theme) private var theme

    /// `icon` nil: the title alone (the clock's month). `accent`: the
    /// symbol's colour, fg when nil.
    public init(_ icon: GroveIcon.Name? = nil, accent: RGB? = nil, title: String,
                @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.accent = accent
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
            if let icon {
                GroveIcon(icon, size: GroveType.heading)
                    .foregroundStyle(Color(accent ?? theme.fg))
                    .frame(width: PanelMetrics.iconColumn, alignment: .leading)
            }
            Text(title).font(GroveWindow.nameFont).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: GroveSpace.s8)
            trailing
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    /// A header with nothing at the right.
    public init(_ icon: GroveIcon.Name? = nil, accent: RGB? = nil, title: String) {
        self.init(icon, accent: accent, title: title) { EmptyView() }
    }
}

/// A headline number ("14%"): title size, semibold, fg unless an accent
/// carries a state (through `theme.ink`, so it stays readable in light).
public struct PanelValue: View {
    let text: String
    let accent: RGB?
    @Environment(\.theme) private var theme

    public init(_ text: String, accent: RGB? = nil) {
        self.text = text
        self.accent = accent
    }

    public var body: some View {
        Text(text).font(GroveFont.mono(GroveType.title, .semibold))
            .foregroundStyle(accent.map { theme.ink($0) } ?? Color(theme.fg))
            .contentTransition(.numericText())
    }
}

/// The 1 pt line between a panel's sections.
public struct PanelRule: View {
    @Environment(\.theme) private var theme
    public init() {}
    public var body: some View { Rectangle().fill(theme.line).frame(height: 1).accessibilityHidden(true) }
}

/// A quiet caption over or under a group ("Output", "Performance", "last 60 s").
public struct PanelCaption: View {
    let text: String
    @Environment(\.theme) private var theme

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).font(GroveFont.mono(GroveType.finePrint)).foregroundStyle(theme.quiet).lineLimit(1).fixedSize()
    }
}

/// "Label    value": the label quiet at the left, the value in fg at the
/// right, one line.
public struct PanelDetail<Value: View>: View {
    let label: String
    let value: Value
    @Environment(\.theme) private var theme

    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
            Text(label).foregroundStyle(theme.quiet)
            Spacer(minLength: GroveSpace.s8)
            value
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

extension PanelDetail where Value == Text {
    /// A text value.
    public init(_ label: String, _ value: String) {
        self.init(label) { Text(value) }
    }
}

/// A state as a dot and a word: the dot carries the colour (green normal,
/// yellow or orange a warning, red critical), the word stays fg. How a panel
/// says "warning": never with an outline.
public struct PanelStatus: View {
    let text: String
    let accent: RGB

    public init(_ text: String, accent: RGB) {
        self.text = text
        self.accent = accent
    }

    public var body: some View {
        GroveIcon.text(.dot, size: GroveType.finePrint).foregroundColor(Color(accent)) + Text(verbatim: " " + text)
    }
}

// MARK: Rows

/// A row that does something on a click (a menu row, a device, a value that
/// copies): its content on the panel's 12 pt inset, and under the pointer a
/// `hoverFill` that reaches 4 pt from the outline (8 across by 4 down inside
/// it), as `KeyPanelList`'s rows. A button to the keyboard and VoiceOver.
/// Put rows in `PanelRows`.
public struct PanelRow<Content: View>: View {
    let action: () -> Void
    let content: Content
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface
    @Environment(\.isEnabled) private var isEnabled
    // The `@State` macro needs a plugin the Command Line Tools don't ship.
    private var hovering = State(initialValue: false)

    public init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    public var body: some View {
        let lit = hovering.wrappedValue && isEnabled
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) { content }
                .lineLimit(1)
                .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(lit ? theme.hoverFill(on: surface) : .clear,
                            in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .lightOutline(cornerRadius: GroveRadius.control, when: lit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -GroveSpace.s8)
        .onHover { hovering.wrappedValue = $0 }
    }
}

/// Rows stacked without gaps (their own 4 pt padding spaces them), pulled up
/// and down by that padding so the first and last row's text sit on the
/// section's edge like any other content.
public struct PanelRows<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }.padding(.vertical, -GroveSpace.s4)
    }
}

/// A panel's last row: a link to the matching app or Settings pane
/// ("Battery Settings…"), label size, with an optional quiet note at the
/// right (the uptime beside "Activity Monitor…").
public struct PanelFooter: View {
    let title: String
    let note: String?
    let action: () -> Void
    @Environment(\.theme) private var theme

    public init(_ title: String, note: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.note = note
        self.action = action
    }

    public var body: some View {
        PanelRows {
            PanelRow(action: action) {
                Text(title).font(GroveFont.mono(GroveType.label))
                if let note {
                    Spacer(minLength: GroveSpace.s8)
                    Text(note).font(GroveFont.mono(GroveType.finePrint)).foregroundStyle(theme.quiet)
                }
            }
        }
    }
}

/// A name and its value, one a line (the busiest processes): the name in fg,
/// cut at the tail, the value quiet at the right. Not clickable.
public struct PanelPairs: View {
    let rows: [(name: String, value: String)]
    @Environment(\.theme) private var theme

    public init(_ rows: [(name: String, value: String)]) { self.rows = rows }

    public var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
                    Text(row.name).truncationMode(.tail)
                    Spacer(minLength: GroveSpace.s4)
                    Text(row.value).foregroundStyle(theme.quiet)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: Controls

/// A button in a panel ("Run speed test", "Cancel"): `GroveSelectPill`'s
/// shape without the chevron, an optional icon before the title.
public struct PanelButton: View {
    let title: String
    let icon: GroveIcon.Name?
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, icon: GroveIcon.Name? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: GroveSpace.s4) {
                if let icon { GroveIcon(icon, size: GroveType.label) }
                Text(title)
            }
            .font(GroveFont.mono(GroveType.label))
            .foregroundStyle(isEnabled ? Color(theme.fg) : theme.quiet)
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
            .background(theme.hoverFill(on: surface), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// On/off in a panel: the system's switch, mini, tinted green, without its
/// label (the row beside it says what it is; `label` is for VoiceOver).
public struct PanelSwitch: View {
    let label: String
    let isOn: Binding<Bool>
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface
    @Environment(\.panelStandIns) private var standIn

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self.isOn = isOn
    }

    public var body: some View {
        if standIn {
            // Offscreen AppKit leaves the tint out: the same measures, drawn.
            let on = isOn.wrappedValue
            Capsule().fill(on ? Color(theme.green) : theme.selectedFill(on: surface))
                .frame(width: PanelMetrics.switchSize.width, height: PanelMetrics.switchSize.height)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(Color(theme.isDark ? theme.fg : theme.bg0)).padding(1)
                }
                .overlay { if theme.isLight, !on { Capsule().strokeBorder(theme.line, lineWidth: 1) } }
        } else {
            Toggle(label, isOn: isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .tint(Color(theme.green))
        }
    }
}

/// A level in a panel (the volume): the system's slider, small, tinted
/// green; `label` is for VoiceOver.
public struct PanelSlider: View {
    let label: String
    let value: Binding<Double>
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface
    @Environment(\.panelStandIns) private var standIn
    @Environment(\.isEnabled) private var isEnabled

    /// `value`: 0...1.
    public init(_ label: String, value: Binding<Double>) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        if standIn {
            GeometryReader { geo in
                let knob = PanelMetrics.sliderKnob
                let x = (geo.size.width - knob) * MeterGeometry.fraction(value.wrappedValue)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.selectedFill(on: surface)).frame(height: PanelMetrics.sliderTrack)
                        .overlay { if theme.isLight { Capsule().strokeBorder(theme.line, lineWidth: 1) } }
                    Capsule().fill(isEnabled ? Color(theme.green) : theme.quiet)
                        .frame(width: x + knob / 2, height: PanelMetrics.sliderTrack)
                    Circle().fill(Color(theme.isDark ? theme.fg : theme.bg0)).frame(width: knob, height: knob)
                        .overlay { if theme.isLight { Circle().strokeBorder(theme.line, lineWidth: 1) } }
                        .offset(x: x)
                }
                .frame(height: geo.size.height)
            }
            .frame(height: PanelMetrics.sliderKnob)
        } else {
            Slider(value: value, in: 0...1).controlSize(.small).tint(Color(theme.green))
                .accessibilityLabel(label)
        }
    }
}
