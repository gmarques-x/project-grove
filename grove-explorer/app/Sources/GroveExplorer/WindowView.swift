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

    /// The smallest window: the rail and a pane narrow enough to have only Name and Size.
    static let minimum = CGSize(width: 368, height: 280)

    var body: some View {
        content
            .frame(minWidth: Self.minimum.width, minHeight: Self.minimum.height)
            .runsUnderTitleBar()
            .keyboardFocusRing()
            .preferredColorScheme(model.colors.colorScheme)
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
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .environment(\.theme, theme)
    }

    /// The sidebar (full, a rail or away, by the window's width), then the
    /// pane or the two panes with the divider between them.
    private func parts(width: CGFloat) -> some View {
        let mode = SidebarLayout.mode(windowWidth: width, panes: model.sides.count, hidden: model.sidebarHidden)
        let panes = SidebarLayout.panesWidth(windowWidth: width, mode: mode)
        return HStack(spacing: 0) {
            if mode != .hidden {
                Sidebar(model: model, rail: mode == .rail)
                Line(vertical: true)
            }
            HStack(spacing: 0) {
                if model.sides.count == 2 {
                    PaneView(model: model, side: .left)
                        .frame(width: SidebarLayout.leftPaneWidth(panesWidth: panes, split: model.split))
                    PaneDivider(model: model, panesWidth: panes)
                    PaneView(model: model, side: .right)
                } else {
                    PaneView(model: model, side: .left)
                }
            }
            .coordinateSpace(name: PaneDivider.space)
        }
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
                .foregroundStyle(enabled ? Color(theme.fg) : theme.quiet(dark: 0.5))
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

    @ObservedObject var model: AppModel
    let panesWidth: CGFloat

    var body: some View {
        Line(vertical: true)
            .overlay {
                // Wider than the line it moves, so it can be caught.
                Color.clear
                    .frame(width: GroveSpace.s8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        // Set, not pushed: nothing is left on the cursor
                        // stack should the divider go while the pointer is on it.
                        (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space)).onChanged { drag in
                            model.split = SidebarLayout.split(leftWidth: drag.location.x, panesWidth: panesWidth)
                        }
                    )
                    .onTapGesture(count: 2) { model.split = 0.5 }
            }
            .zIndex(1)
            .accessibilityElement()
            .accessibilityLabel("Divider between the panes")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.05 : -0.05
                model.split = SidebarLayout.split(
                    leftWidth: (panesWidth - 1) * (model.split + step), panesWidth: panesWidth)
            }
    }
}
