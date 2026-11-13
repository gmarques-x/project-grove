import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The Grove Explorer window (spec §5): the header with back and forward
/// and the one-pane/two-pane switch, then the sidebar and the panes to the
/// window's edges with 1 pt lines between. The one Grove window without
/// `GroveWindow.margin`.
struct WindowView: View {
    @ObservedObject var model: AppModel
    /// The file operations: the conflict prompt follows them.
    @ObservedObject var work: FileWork

    init(model: AppModel) {
        self.model = model
        work = model.work
    }

    /// The smallest window: the rail and a pane narrow enough to have only Name and Size.
    static let minimum = CGSize(width: 368, height: 280)
    /// The window as it first opens (AeroSpace tiles it from there).
    static let standard = CGSize(width: 1100, height: 700)
    /// How much of the quiet colour a history arrow that leads nowhere
    /// keeps on a dark scheme.
    private static let disabledArrow = 0.5

    var body: some View {
        content
            .frame(minWidth: Self.minimum.width, minHeight: Self.minimum.height)
            .runsUnderTitleBar()
            .keyboardFocusRing()
            .preferredColorScheme(model.colors.colorScheme)
            // The red button asks the model: a quit that waits keeps the window.
            .background(WindowAccessor { [model] window in model.takeCloseButton(of: window) })
            .sheet(isPresented: Binding(get: { model.showsConnectSheet }, set: { model.showsConnectSheet = $0 })) {
                ConnectSheet(model: model)
                    .environment(\.theme, model.colors)
                    .preferredColorScheme(model.colors.colorScheme)
            }
    }

    /// The window's inside, without what ties it to a real window (a render
    /// draws this in a window that has no title bar to run under).
    var content: some View {
        let theme = model.colors
        return VStack(spacing: 0) {
            GroveWindowHeader("Grove Explorer", middle: { history(theme) }, trailing: { paneSwitch })
            // What the user just did and couldn't first, then the config's own.
            if let problem = model.writeProblem { banner(problem, theme) }
            if let problem = model.config.problem { banner(problem, theme) }
            GeometryReader { geometry in
                parts(width: geometry.size.width)
            }
        }
        // A name is taken where an operation goes: the prompt, over the scrim.
        .overlay {
            if let prompt = work.prompt {
                PromptScrim()
                ConflictPrompt(model: model, state: prompt)
            }
        }
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .environment(\.theme, theme)
    }

    /// The sidebar (full at its chosen width, a rail or away, by the
    /// window's width), then the pane or the two panes with the divider
    /// between them. The full sidebar's line can be dragged.
    private func parts(width: CGFloat) -> some View {
        let chosen = model.sidebarWidth
        let mode = SidebarLayout.mode(
            windowWidth: width, panes: model.sides.count, hidden: model.sidebarHidden, chosen: chosen)
        let panes = SidebarLayout.panesWidth(windowWidth: width, mode: mode, chosen: chosen)
        return HStack(spacing: 0) {
            if mode != .hidden {
                Sidebar(model: model, rail: mode == .rail, width: chosen)
                if mode == .full {
                    SidebarDivider(model: model, windowWidth: width)
                } else {
                    Line(vertical: true)
                }
            }
            HStack(spacing: 0) {
                if model.sides.count == 2 {
                    PaneView(model: model, work: work, side: .left)
                        .frame(width: SidebarLayout.leftPaneWidth(panesWidth: panes, split: model.split))
                    PaneDivider(model: model, panesWidth: panes)
                    PaneView(model: model, work: work, side: .right)
                } else {
                    PaneView(model: model, work: work, side: .left)
                }
            }
            .coordinateSpace(name: PaneDivider.space)
            // A favourite's row dragged out of the sidebar and let go here: it is removed.
            .onDrop(of: [AppModel.favouriteDrag], isTargeted: nil) { _ in model.removeDraggedFavourite() }
        }
        .coordinateSpace(name: SidebarDivider.space)
    }

    /// One pane or two: two icon segments at the header's right.
    private var paneSwitch: some View {
        GroveSegmented(
            "Panes",
            segments: [
                GroveSegment(1, "One pane", icon: .onePane),
                GroveSegment(2, "Two panes", icon: .twoPanes),
            ],
            selection: model.sides.count, style: .outlined
        ) { model.showPanes($0) }
    }

    /// Back and forward for the active pane.
    private func history(_ theme: ThemeColors) -> some View {
        let tab = model.browser.activeTab
        return HStack(spacing: 0) {
            arrow(.back, "Back", enabled: !tab.back.isEmpty, theme) { model.goBack() }
            arrow(.forward, "Forward", enabled: !tab.forward.isEmpty, theme) { model.goForward() }
        }
    }

    private func arrow(
        _ icon: GroveIcon.Name, _ label: String, enabled: Bool, _ theme: ThemeColors, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GroveIcon(icon, size: GroveType.label)
                .foregroundStyle(enabled ? Color(theme.fg) : theme.quiet(dark: Self.disabledArrow))
                .frame(width: GroveSpace.s24, height: GroveSpace.s24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help(label)
    }

    /// The config file couldn't be read (spec §13): the built-in defaults are
    /// in use, and this names the line. Grove's tinted banner, in orange.
    private func banner(_ problem: String, _ theme: ThemeColors) -> some View {
        Text(verbatim: problem)
            .foregroundStyle(theme.ink(theme.orange))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GroveSpace.s12).padding(.vertical, GroveSpace.s8)
            .background(theme.tintFill(theme.orange, .banner), in: RoundedRectangle(cornerRadius: GroveRadius.card))
            .lightOutline(cornerRadius: GroveRadius.card, accent: theme.orange)
            .padding(.horizontal, GroveSpace.s16).padding(.bottom, GroveSpace.s8)
    }
}

/// The line between two panes: it can be dragged, and a double-click makes
/// the panes even again (spec §5).
private struct PaneDivider: View {
    static let space = "panes"
    /// How far one VoiceOver step moves the divider, as a share of the panes' width.
    private static let step = 0.05

    @ObservedObject var model: AppModel
    let panesWidth: CGFloat

    var body: some View {
        Line(vertical: true)
            .overlay {
                DividerHandle(
                    space: Self.space,
                    start: { SidebarLayout.leftPaneWidth(panesWidth: panesWidth, split: model.split) },
                    drag: { start, moved in
                        model.split = SidebarLayout.split(leftWidth: start + moved, panesWidth: panesWidth)
                    },
                    reset: { model.split = 0.5 })
            }
            .zIndex(1)
            .accessibilityElement()
            .accessibilityLabel("Pane divider")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? Self.step : -Self.step
                model.split = SidebarLayout.split(
                    leftWidth: (panesWidth - 1) * (model.split + step), panesWidth: panesWidth)
            }
    }
}

/// The line after the full sidebar (2026-11-13 sidebar spec, B): dragged,
/// the sidebar is 160–360 pt wide (the panes take the rest and keep their
/// split); a double-click makes it 200 again. Caught and dragged as the
/// line between the panes is (`DividerHandle`); VoiceOver meets it as a
/// splitter whose value is the width (`SplitterElement`).
private struct SidebarDivider: View {
    static let space = "window parts"
    /// How far one VoiceOver step moves the line, in points.
    private static let step = 20.0

    @ObservedObject var model: AppModel
    let windowWidth: CGFloat

    var body: some View {
        let widest = SidebarLayout.widestFitting(windowWidth: windowWidth, panes: model.sides.count)
        return Line(vertical: true)
            .overlay {
                DividerHandle(
                    space: Self.space,
                    start: { SidebarLayout.width(of: .full, chosen: model.sidebarWidth) },
                    drag: { start, moved in
                        resize(SidebarLayout.dragged(from: start, by: moved, windowWidth: windowWidth, panes: model.sides.count))
                    },
                    reset: { model.sidebarWidth = SidebarLayout.reset })
            }
            .background {
                SplitterElement(
                    label: "Sidebar width", value: model.sidebarWidth, range: SidebarLayout.narrowest...widest
                ) { wider in
                    resize(SidebarLayout.dragged(
                        to: model.sidebarWidth + (wider ? Self.step : -Self.step), windowWidth: windowWidth,
                        panes: model.sides.count))
                }
            }
            .zIndex(1)
    }

    /// Whether the width changed (at a limit it doesn't).
    @discardableResult private func resize(_ width: Double) -> Bool {
        guard width != model.sidebarWidth else { return false }
        model.sidebarWidth = width
        return true
    }
}

/// The catch area of a line that can be dragged (the panes' and the
/// sidebar's): 8 pt over the 1 pt line. The resize-left-right pointer over
/// it, and for the whole of a drag (also once the line has stopped at a
/// limit and the pointer has gone past it). A drag moves the line by as
/// much as the pointer moved since it began, measured in `space` (which
/// stays put while the line moves), so where in the area it was caught
/// makes no jump. A double-click is `reset`.
private struct DividerHandle: View {
    let space: String
    /// Where the line is as a drag begins, in points.
    let start: () -> Double
    /// A drag: where it began, and how far the pointer has moved since.
    let drag: (_ start: Double, _ moved: Double) -> Void
    let reset: () -> Void
    /// The line's place when the drag under way began; nil between drags.
    /// `State` used directly: no SwiftUI macros here.
    private var began = State<Double?>(initialValue: nil)
    /// The pointer is over the area.
    private var inside = State(initialValue: false)

    init(space: String, start: @escaping () -> Double, drag: @escaping (Double, Double) -> Void, reset: @escaping () -> Void) {
        self.space = space
        self.start = start
        self.drag = drag
        self.reset = reset
    }

    var body: some View {
        Color.clear
            .frame(width: GroveSpace.s8)
            .contentShape(Rectangle())
            .onHover { now in
                inside.wrappedValue = now
                // Set, not pushed: nothing is left on the cursor stack should
                // the line go while the pointer is on it. Not while dragging.
                if began.wrappedValue == nil { (now ? NSCursor.resizeLeftRight : NSCursor.arrow).set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
                    .onChanged { moving in
                        let from = began.wrappedValue ?? start()
                        if began.wrappedValue == nil { began.wrappedValue = from }
                        // Over whatever the pointer is above now, until the drag ends.
                        NSCursor.resizeLeftRight.set()
                        drag(from, moving.translation.width)
                    }
                    .onEnded { _ in
                        began.wrappedValue = nil
                        if !inside.wrappedValue { NSCursor.arrow.set() }
                    }
            )
            .onTapGesture(count: 2, perform: reset)
    }
}

/// A splitter for VoiceOver, with its value and its limits (the role
/// SwiftUI has no modifier for): an AppKit view behind a line that takes
/// no clicks, the pointer's drag staying SwiftUI's. Increment and
/// decrement move it; at a limit they say they did nothing.
private struct SplitterElement: NSViewRepresentable {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    /// A step wider or narrower; whether the value changed.
    let step: (_ wider: Bool) -> Bool

    func makeNSView(context: Context) -> SplitterView { SplitterView() }

    func updateNSView(_ view: SplitterView, context: Context) {
        view.label = label
        view.step = step
        view.range = range
        view.value = value
    }

    final class SplitterView: NSView {
        var label = ""
        var step: (Bool) -> Bool = { _ in false }
        var range: ClosedRange<Double> = 0...0
        var value = 0.0 {
            didSet { if value != oldValue { NSAccessibility.post(element: self, notification: .valueChanged) } }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
        override func accessibilityLabel() -> String? { label }
        override func accessibilityValue() -> Any? { NSNumber(value: value) }
        override func accessibilityValueDescription() -> String? { "\(Int(value)) points" }
        override func accessibilityMinValue() -> Any? { NSNumber(value: range.lowerBound) }
        override func accessibilityMaxValue() -> Any? { NSNumber(value: range.upperBound) }
        override func accessibilityOrientation() -> NSAccessibilityOrientation { .vertical }
        override func accessibilityPerformIncrement() -> Bool { step(true) }
        override func accessibilityPerformDecrement() -> Bool { step(false) }
    }
}
