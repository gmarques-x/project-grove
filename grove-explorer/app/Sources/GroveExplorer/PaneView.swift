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

/// One pane: the line over it (green on the pane that has the keys), the
/// header row, the list, the status bar. Its columns follow its own width.
struct PaneView: View {
    @ObservedObject var model: AppModel
    let side: Side
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let columns = ListColumns(paneWidth: geometry.size.width)
            let active = model.browser.active == side
            VStack(spacing: 0) {
                Line(color: active ? Color(theme.green) : nil)
                ColumnHeader(columns: columns, sort: model.browser.tab(side)?.sort ?? .byName) {
                    model.sort(by: $0, in: side)
                }
                Line()
                content(columns)
                Line()
                StatusBar(
                    text: model.status(for: side), free: model.listing(for: side)?.free, showsFree: columns.showsKind)
            }
        }
        .background(Color(theme.bg0))
    }

    @ViewBuilder private func content(_ columns: ListColumns) -> some View {
        let listing = model.listing(for: side)
        if let problem = listing?.problem {
            note(Self.sentence(for: problem, folder: listing?.folder.lastPathComponent ?? ""))
        } else if let listing, listing.shown.isEmpty {
            note("This folder is empty")
        } else {
            FileList(model: model, side: side, columns: columns)
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(GroveFont.mono(GroveType.label))
            .foregroundStyle(theme.quiet)
            .multilineTextAlignment(.center)
            .padding(GroveSpace.s24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func sentence(for problem: FolderReadError, folder: String) -> String {
        switch problem {
        case .noPermission: "Grove Explorer needs permission to open \(folder)"
        case .missing: "\(folder) is no longer there"
        case .notAFolder: "\(folder) is not a folder"
        case .other(let words): words
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
