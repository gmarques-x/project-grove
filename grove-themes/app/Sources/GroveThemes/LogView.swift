import GroveThemesCore
import SwiftUI

/// The last five switches: when, which scheme, and a chip per kind of result.
struct LogView: View {
    let entries: [LogEntry]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("No switches yet.").foregroundStyle(Color(theme.grey1))
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.when(entry.time))
                        .foregroundStyle(Color(theme.grey1))
                        .frame(width: 92, alignment: .leading)
                    Text(StatusText.displayName(entry.scheme)).fontWeight(.bold)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(StatusText.chips(for: entry).enumerated()), id: \.offset) { _, chip in
                            ChipView(chip: chip)
                        }
                    }
                }
            }
        }
        .font(GroveFont.mono(12))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(theme.bg1), in: RoundedRectangle(cornerRadius: 10))
    }

    /// "13:10" today, "9 Nov 13:10" on another day.
    static func when(_ time: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(time, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: time)
    }
}

/// A log chip; clicking it shows the step's message (in red for a step that
/// needs you or failed).
private struct ChipView: View {
    let chip: Chip
    @Environment(\.theme) private var theme
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var showing = State(initialValue: false)

    private var color: Color {
        switch chip.kind {
        case .live: Color(theme.green)
        case .nextPrompt, .nextLaunch: Color(theme.yellow)
        case .needsYou, .failed: Color(theme.red)
        }
    }

    var body: some View {
        Button { showing.wrappedValue.toggle() } label: {
            Text(chip.text)
                .font(GroveFont.mono(11))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(theme.bg2), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: showing.projectedValue, arrowEdge: .bottom) {
            let problem = chip.kind == .needsYou || chip.kind == .failed
            Text(chip.message.isEmpty ? chip.text : chip.message)
                .font(GroveFont.mono(11.5))
                .foregroundStyle(problem ? Color(theme.red) : Color(theme.fg))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(12)
                .background(Color(theme.bg1))
        }
    }
}

/// Lays chips out in rows, wrapping when a row is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
