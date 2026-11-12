import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The line at the bottom of a pane: what it holds and what is selected at
/// the left, the volume's free room at the right (left out in a narrow
/// pane). In their place, while there is something to say:
/// - an operation going to this pane: its words, a meter, and Cancel;
/// - for a few seconds, what happened to the pane's folder ("x is no longer
///   there") or why a command was refused, in the marked style;
/// - what the last operation did, with "⌘Z to undo", for a few seconds; or
///   how many items could not be done, which a click lists.
struct StatusBar: View {
    let text: String
    /// What to say in the text's place for now; nil most of the time.
    var notice: String?
    /// The operation this pane tells of, running or just over.
    var status: PaneStatus?
    /// Free room on the folder's volume, in bytes; nil when it isn't known.
    let free: Int64?
    /// Whether the pane is wide enough for the free room (640 pt, as Kind).
    let showsFree: Bool
    var failuresShown = false
    var onCancel: () -> Void = {}
    var onFailures: () -> Void = {}
    @Environment(\.theme) private var theme

    /// The meter's length in a wide pane and in a narrow one (the mock-up's).
    private static let meter: (wide: CGFloat, narrow: CGFloat) = (160, 96)

    var body: some View {
        HStack(spacing: GroveSpace.s8) {
            // A notice first, for its few seconds: a refusal said while
            // another operation's meter runs is otherwise never seen.
            if let notice {
                theme.marked(notice, theme.orange).truncationMode(.middle)
                // Over a running operation only its words and its bar give
                // way: how far it is and the way to stop it stay.
                if case let .running(_, _, _, percent)? = status { percentAndCancel(percent) }
            } else if case let .running(_, words, fraction, percent)? = status {
                running(words, fraction, percent)
            } else if case let .done(summary, changed, hint)? = status {
                if changed { theme.marked(summary, theme.green) } else { Text(verbatim: summary) }
                if hint { Text(verbatim: "· " + OperationStatus.undoHint).fixedSize() }
            } else if case let .failed(line, _, _, changed)? = status {
                Button(action: onFailures) {
                    theme.marked(line, theme.red).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show which, and why")
                .accessibilityHint("Shows which, and why")
                .accessibilityValue(failuresShown ? "list shown" : "")
                if changed { Text(verbatim: "· " + OperationStatus.undoHint).fixedSize() }
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

    @ViewBuilder private func running(_ words: String, _ fraction: Double, _ percent: String) -> some View {
        let length = showsFree ? Self.meter.wide : Self.meter.narrow
        Text(verbatim: words).foregroundStyle(Color(theme.fg)).truncationMode(.middle).layoutPriority(1)
        ZStack(alignment: .leading) {
            Capsule().fill(theme.line)
            Capsule().fill(Color(theme.green)).frame(width: length * fraction)
        }
        .frame(width: length, height: PanelMetrics.sliderTrack)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(percent)
        percentAndCancel(percent)
    }

    @ViewBuilder private func percentAndCancel(_ percent: String) -> some View {
        Text(verbatim: percent).fixedSize()
        // Never cut short: it is the one way to stop the run.
        PanelButton("Cancel", icon: .close, action: onCancel)
            .fixedSize()
            .help("Stop after the file it is on")
            .accessibilityLabel("Cancel the operation")
    }
}

/// The items an operation could not do, each with its reason, under what
/// it did all the same: a card over the foot of the pane's list, opened by
/// a click on the status bar's line and closed by another, by its button
/// or by Escape.
struct FailureList: View {
    let summary: String
    let items: [String]
    /// The item at the top of a list longer than the card: the scroll
    /// view writes it as it scrolls, and ↑ ↓ set it (`AppModel.failuresKey`).
    var top: Binding<Int?> = .constant(nil)
    let onClose: () -> Void
    @Environment(\.theme) private var theme

    /// No taller than this many rows: the rest scrolls.
    static let rows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
                Text(verbatim: summary)
                    .font(GroveFont.mono(GroveType.label, .semibold))
                    .foregroundStyle(Color(theme.fg))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: GroveSpace.s8)
                PanelButton("Close", action: onClose)
            }
            let list = VStack(alignment: .leading, spacing: GroveSpace.s4) {
                ForEach(Array(items.enumerated()), id: \.offset) { item in
                    Text(verbatim: item.element)
                        .font(GroveFont.mono(GroveType.body))
                        .foregroundStyle(Color(theme.fg))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .id(item.offset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if items.count > Self.rows {
                // By item, not by a count of lines: an item may wrap, and
                // the last one is reached whatever the others' heights.
                ScrollView { list.scrollTargetLayout() }
                    .scrollPosition(id: top, anchor: .top)
                    .frame(height: CGFloat(Self.rows) * ListMetrics.row)
            } else {
                list
            }
        }
        .padding(GroveSpace.s12)
        .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.card))
        .overlay(RoundedRectangle(cornerRadius: GroveRadius.card).strokeBorder(theme.line, lineWidth: 1))
        .padding(GroveSpace.s8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Items that could not be done")
    }
}
