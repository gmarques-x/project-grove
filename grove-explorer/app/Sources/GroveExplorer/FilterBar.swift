import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The ⌘F filters of the window: each tab's own, while its field is open.
struct FilterState: Equatable {
    /// What each tab's field says, by the tab's id; "" when just opened.
    var texts: [UUID: String] = [:]
    /// The pane whose filter field has the keyboard: the list's commands
    /// are not for it, as with the rename and path fields.
    var focused: Side?
    /// The pane whose field should take the keyboard when it appears, and
    /// a count per pane that goes up to hand it to a field already there.
    var asked: Side?
    var asks: [Side: Int] = [:]
}

/// The filter field above a pane's list (spec §6): the list keeps the names
/// that contain every word typed. ↑ and ↓ move the list's selection and
/// Return opens it, so one can type, arrow to a row and open it; Escape
/// clears the filter and gives the keyboard back to the list. A 1 pt green
/// line while it has the keyboard, as the path and rename fields.
struct FilterBar: View {
    @ObservedObject var model: AppModel
    let side: Side
    let text: String
    /// The pane is wide enough for the hint.
    let showsHint: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let focused = model.filter.focused == side
        HStack(spacing: GroveSpace.s8) {
            GroveIcon(.search, size: GroveType.label).foregroundStyle(theme.quiet)
            FilterField(
                text: text, placeholder: "Filter by name", theme: theme, size: GroveType.label,
                // A render's window gives no field the keyboard.
                takesFocus: model.live && model.filter.asked == side, focus: model.filter.asks[side] ?? 0,
                onChange: { model.setFilter($0, in: side) },
                onMove: { model.filterMoved(by: $0, in: side) },
                onReturn: { model.filterReturn(in: side) },
                onEscape: { model.clearFilter(in: side) },
                // After the turn: the field can take or lose the keyboard
                // while SwiftUI is updating its views.
                onFocus: { has in DispatchQueue.main.async { model.filterFocusChanged(has, in: side) } }
            )
            .accessibilityLabel("Filter")
            if showsHint {
                Text(verbatim: "esc clears")
                    .font(GroveFont.mono(GroveType.finePrint))
                    .foregroundStyle(theme.quiet)
                    .lineLimit(1).fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, GroveSpace.s8)
        .frame(height: BarMetrics.control)
        .overlay(
            RoundedRectangle(cornerRadius: GroveRadius.control)
                .strokeBorder(focused ? Color(theme.green) : theme.line, lineWidth: 1))
        .padding(.horizontal, GroveSpace.s8)
        .frame(height: BarMetrics.strip)
    }
}

extension AppModel {
    /// What the pane's filter field says; nil while it has none.
    func filterText(for side: Side) -> String? {
        browser.tab(side).flatMap { filter.texts[$0.id] }
    }

    /// ⌘F: the active pane's tab gets its filter field, which takes the keyboard.
    func beginFilter() {
        let side = browser.active
        guard let tab = browser.tab(side) else { return }
        sidebarCursor = nil
        if pathField != nil { pathField = nil }
        if filter.texts[tab.id] == nil { filter.texts[tab.id] = "" }
        filter.asked = side
        filter.asks[side, default: 0] += 1
    }

    /// The field's text changed: the list shows the names that match.
    func setFilter(_ text: String, in side: Side) {
        guard let tab = browser.tab(side), filter.texts[tab.id] != nil, filter.texts[tab.id] != text else { return }
        filter.texts[tab.id] = text
        arrange(side)
    }

    /// Escape: the filter goes, the list shows the whole folder again and
    /// has the keyboard.
    func clearFilter(in side: Side) {
        guard let tab = browser.tab(side), filter.texts[tab.id] != nil else { return }
        filter.texts[tab.id] = nil
        filterFieldWent(in: side)
        arrange(side)
        if browser.active == side { focusList() }
    }

    /// ↑ (−1) and ↓ (1) in the field: the list's selection moves.
    func filterMoved(by step: Int, in side: Side) {
        guard let url = Filter.moved(from: selection(for: side), by: step, in: entries(for: side)) else { return }
        select([url], in: side)
        reveal(url, in: side)
    }

    /// Return in the field: what is selected opens. (Not a rename: the
    /// keyboard is in the field, to find a thing and go to it.)
    func filterReturn(in side: Side) {
        guard work.prompt == nil, work.rename == nil, sides.contains(side) else { return }
        activate(side)
        guard hasSelection else { return }
        openSelection()
    }

    /// The field took the keyboard, or gave it up.
    func filterFocusChanged(_ has: Bool, in side: Side) {
        if has {
            // A field that went meanwhile has no keyboard to speak of.
            guard filterText(for: side) != nil else { return }
            if filter.asked == side { filter.asked = nil }
            if filter.focused != side { filter.focused = side }
            sidebarCursor = nil
            activate(side)
        } else if filter.focused == side {
            filter.focused = nil
        }
    }

    /// The pane's field is no longer there: it has the keyboard no more.
    private func filterFieldWent(in side: Side) {
        if filter.focused == side { filter.focused = nil }
        if filter.asked == side { filter.asked = nil }
    }

    /// A list has the keyboard: no filter field has it.
    func listHasKeyboard() {
        if filter.focused != nil { filter.focused = nil }
    }

    /// The browser changed: a tab that shows another folder now has no
    /// filter (it was for the folder it left), nor has a tab that closed.
    func filtersFollow(_ was: Browser, _ now: Browser) {
        if !filter.texts.isEmpty {
            var folders: [UUID: URL] = [:]
            for tab in was.panes.flatMap(\.tabs) { folders[tab.id] = tab.folder }
            var kept = filter.texts
            let tabs = now.panes.flatMap(\.tabs)
            for tab in tabs where folders[tab.id] != tab.folder { kept[tab.id] = nil }
            kept = kept.filter { id, _ in tabs.contains { $0.id == id } }
            if kept != filter.texts { filter.texts = kept }
        }
        // A pane that shows no field now (its filter went, or its other
        // tab has none): the field has the keyboard no more, and the list
        // of the pane that has the keys takes it.
        for side in [Side.left, .right] where filterText(for: side) == nil {
            if filter.focused == side, now.active == side { listFocus += 1 }
            filterFieldWent(in: side)
        }
    }
}
