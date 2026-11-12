import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The line at the bottom of a pane: what it holds and what is selected at
/// the left, the volume's free room at the right (left out in a narrow
/// pane). For a few seconds it says instead what happened to the pane's
/// folder ("x is no longer there"), in the marked style.
struct StatusBar: View {
    let text: String
    /// What to say in the text's place for now; nil most of the time.
    var notice: String?
    /// Free room on the folder's volume, in bytes; nil when it isn't known.
    let free: Int64?
    /// Whether the pane is wide enough for the free room (640 pt, as Kind).
    let showsFree: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: GroveSpace.s8) {
            if let notice {
                theme.marked(notice, theme.orange).truncationMode(.middle)
            } else {
                Text(verbatim: text)
            }
            Spacer(minLength: GroveSpace.s8)
            if showsFree, let free {
                Text(verbatim: Formatting.size(free) + " free").fixedSize()
            }
        }
        .font(GroveFont.mono(GroveType.body))
        .foregroundStyle(theme.quiet)
        .lineLimit(1)
        .padding(.horizontal, ListColumns.edge)
        .frame(height: ListMetrics.row)
    }
}
