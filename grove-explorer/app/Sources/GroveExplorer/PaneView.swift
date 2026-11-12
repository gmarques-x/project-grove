import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// A 1 pt line between the window's parts: `theme.line`, or the colour given.
struct Line: View {
    var vertical = false
    var color: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle().fill(color ?? theme.line).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// One pane (spec §5): the line over it (green on the pane that has the
/// keys), the tab strip, the path bar, the column titles, the list, the
/// status bar. Its columns follow its own width.
struct PaneView: View {
    @ObservedObject var model: AppModel
    /// The file operations: the status bar and the rename field follow them.
    @ObservedObject var work: FileWork
    let side: Side
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let columns = ListColumns(paneWidth: geometry.size.width)
            let active = model.browser.active == side
            let listing = model.listing(for: side)
            // Nothing to list: no column titles, since there is nothing under them.
            let bare = listing.map { $0.problem != nil || $0.shown.isEmpty } ?? false
            VStack(spacing: 0) {
                Line(color: active ? Color(theme.green) : nil)
                TabStrip(model: model, side: side)
                Line()
                if let field = model.pathField, field.side == side {
                    PathField(model: model, state: field, showsHint: columns.showsDate)
                } else {
                    PathBarView(model: model, side: side)
                }
                Line()
                if !bare {
                    ColumnHeader(columns: columns, sort: model.browser.tab(side)?.sort ?? .byName) {
                        model.sort(by: $0, in: side)
                    }
                    Line()
                }
                // The list is always there, even with no rows: it is what
                // holds the keyboard for the pane.
                FileList(model: model, work: work, side: side, columns: columns)
                    .overlay { if let listing, bare { note(listing) } }
                    .overlay(alignment: .bottomLeading) { failures }
                Line()
                StatusBar(
                    text: model.status(for: side), notice: model.notices[side], status: work.statuses[side],
                    free: listing?.free, showsFree: columns.showsKind, failuresShown: work.failuresShown == side,
                    onCancel: { model.cancelRun() },
                    onFailures: { work.failuresShown = work.failuresShown == side ? nil : side })
            }
        }
        .background(Color(theme.bg0))
    }

    /// The items the pane's last operation could not do, over the foot of
    /// the list while the status bar's line was clicked.
    @ViewBuilder private var failures: some View {
        if work.failuresShown == side, case let .failed(_, summary, items, _)? = work.statuses[side] {
            FailureList(summary: summary, items: items) { work.failuresShown = nil }
        }
    }

    /// In the list's place: "This folder is empty", or why the folder
    /// can't be read, with the way to Privacy Settings when that helps.
    @ViewBuilder private func note(_ listing: Listing) -> some View {
        VStack(spacing: GroveSpace.s12) {
            if let problem = listing.problem {
                theme.marked(problem, theme.orange, size: GroveType.label)
                    .font(GroveFont.mono(GroveType.label))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if listing.needsPermission {
                    Text(verbatim: "macOS asks once per folder. Allow it there, then open the folder again.")
                        .font(GroveFont.mono(GroveType.body))
                        .foregroundStyle(theme.quiet)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    PanelButton("Open Privacy Settings…") { model.openPrivacySettings() }
                }
            } else {
                Text(verbatim: "This folder is empty")
                    .font(GroveFont.mono(GroveType.label))
                    .foregroundStyle(theme.quiet)
            }
        }
        .padding(GroveSpace.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(theme.bg0))
        // It covers the list: a click here is a click in the pane.
        .contentShape(Rectangle())
        .onTapGesture {
            model.activate(side)
            model.focusList()
        }
    }
}

/// The header row above the list: each column's name, a click sorts by it
/// and a second click reverses. Drawn here, not by the table, and laid out
/// from the same `ListColumns` as the rows.
private struct ColumnHeader: View {
    let columns: ListColumns
    let sort: GroveExplorerCore.SortOrder
    let onSort: (SortColumn) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            title("Name", .name).frame(width: columns.name, alignment: .leading)
            title("Size", .size).frame(width: ListColumns.size, alignment: .trailing)
            if columns.showsDate {
                title(columns.shortDate ? "Modified" : "Date Modified", .modified)
                    .frame(width: columns.date, alignment: .leading).padding(.leading, ListColumns.gap)
            }
            if columns.showsKind {
                title("Kind", .kind).frame(width: ListColumns.kind, alignment: .leading).padding(.leading, ListColumns.gap)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, ListColumns.edge)
        .frame(height: ListMetrics.row)
    }

    private func title(_ name: String, _ column: SortColumn) -> some View {
        let sorted = sort.column == column
        return Button { onSort(column) } label: {
            HStack(spacing: GroveSpace.s4) {
                Text(verbatim: name)
                if sorted {
                    GroveIcon(.sorted, size: GroveType.finePrint).rotationEffect(.degrees(sort.ascending ? 0 : 180))
                }
            }
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(sorted ? Color(theme.fg) : theme.quiet)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(name)")
        .accessibilityValue(sorted ? (sort.ascending ? "ascending" : "descending") : "")
    }
}
