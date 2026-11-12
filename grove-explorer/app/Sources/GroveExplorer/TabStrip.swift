import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The measures the window's bars share.
enum BarMetrics {
    /// The tab strip and the path bar: 32 pt each.
    static let strip: CGFloat = 32
    /// A tab, a field, a sidebar row: 24 pt.
    static let control = GroveSpace.s24
}

/// A pane's tabs (spec §5): the current one is a pill in the selected fill,
/// a tab under the pointer shows its close mark at its left, in room kept
/// for it, and "+" adds a tab on the same folder.
struct TabStrip: View {
    @ObservedObject var model: AppModel
    let side: Side
    @Environment(\.theme) private var theme
    /// The tab under the pointer. `State` used directly: the Command Line
    /// Tools ship no SwiftUI macros.
    private var hovered = State<UUID?>(initialValue: nil)

    init(model: AppModel, side: Side) {
        self.model = model
        self.side = side
    }

    var body: some View {
        // A body can be asked for once more while two panes become one:
        // a pane that is no longer there has no tabs to draw.
        let panes = model.browser.panes
        let pane = panes.indices.contains(side.rawValue) ? panes[side.rawValue] : nil
        let tabs = pane?.tabs ?? []
        HStack(spacing: GroveSpace.s4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                self.tab(tab, at: index, current: index == pane?.current, closes: tabs.count > 1)
            }
            Button { model.newTab(in: side) } label: {
                GroveIcon(.add, size: GroveType.label)
                    .foregroundStyle(theme.quiet)
                    .frame(width: BarMetrics.control, height: BarMetrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New tab")
            .help("New tab")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GroveSpace.s8)
        .frame(height: BarMetrics.strip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private func tab(_ tab: GroveExplorerCore.Tab, at index: Int, current: Bool, closes: Bool) -> some View {
        let pointed = hovered.wrappedValue == tab.id || model.tabPointerStandIn[side] == index
        return Text(verbatim: tab.title)
            .font(GroveFont.mono(GroveType.label))
            .foregroundStyle(current ? Color(theme.fg) : theme.quiet)
            .lineLimit(1).truncationMode(.middle)
            // The close mark's room is kept at the left whether it shows or not.
            .padding(.leading, GroveSpace.s24).padding(.trailing, GroveSpace.s16)
            .frame(height: BarMetrics.control)
            .background(
                current ? theme.selectedFill(on: .base) : pointed ? theme.hoverFill(on: .base) : .clear,
                in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control, when: current)
            .contentShape(Rectangle())
            .onTapGesture { model.showTab(index, in: side) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.showTab(index, in: side) }
            .overlay(alignment: .leading) {
                if pointed, closes {
                    Button { model.closeTab(index, in: side) } label: {
                        GroveIcon(.close, size: GroveType.finePrint)
                            .foregroundStyle(Color(theme.fg))
                            .frame(width: GroveSpace.s24, height: BarMetrics.control)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close \(tab.title)")
                    .help("Close tab")
                }
            }
            .onHover { inside in
                if inside { hovered.wrappedValue = tab.id } else if hovered.wrappedValue == tab.id { hovered.wrappedValue = nil }
            }
            .help(tab.folder.path)
    }
}
