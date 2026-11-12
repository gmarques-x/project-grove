import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The Grove Explorer window (spec §5): the header with back and forward,
/// then the panes to the window's edges with 1 pt lines between. The one
/// Grove window without `GroveWindow.margin`.
struct WindowView: View {
    @ObservedObject var model: AppModel

    /// The smallest window: a pane narrow enough to have only Name and Size.
    static let minimum = CGSize(width: 320, height: 240)

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
            GroveWindowHeader("Grove Explorer", middle: { history(theme) }, trailing: { EmptyView() })
            if let problem = model.config.problem { banner(problem, theme) }
            HStack(spacing: 0) {
                ForEach(model.sides, id: \.self) { side in
                    if side == .right { Line(vertical: true) }
                    PaneView(model: model, side: side)
                }
            }
        }
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .environment(\.theme, theme)
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
