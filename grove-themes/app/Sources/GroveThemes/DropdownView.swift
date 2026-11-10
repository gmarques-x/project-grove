import AppKit
import GroveThemesCore
import SwiftUI

/// The menu bar dropdown, worn in the current scheme.
struct DropdownView: View {
    @Environment(ThemesModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let theme = model.currentColors
        VStack(alignment: .leading, spacing: 12) {
            header(theme)
            if let error = model.error {
                Text(error.message)
                    .font(GroveFont.mono(11.5))
                    .foregroundStyle(Color(theme.red))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                row("DARK", model.schemes(dark: true), theme)
                row("LIGHT", model.schemes(dark: false), theme)
            }
            if let entry = model.log.first {
                StatusLine(entry: entry)
            }
            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Open Grove Themes…") {
                    openWindow(id: "gallery")
                    NSApp.activate()
                }
                MenuRow(title: "Quit") { NSApp.terminate(nil) }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(theme.fg).opacity(0.18)).frame(height: 1)
            }
        }
        .padding(14)
        .frame(width: 320)
        .font(GroveFont.mono(13))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { Task { await model.refresh() } }
    }

    private func header(_ theme: ThemeColors) -> some View {
        HStack(spacing: 10) {
            PineShape()
                .fill(Color(theme.green))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Grove Themes").font(GroveFont.mono(15, .bold))
                if let list = model.list {
                    Text(StatusText.displayName(list.current)).modifier(SchemeNameStyle())
                }
            }
        }
    }

    private func row(_ label: String, _ schemes: [String], _ theme: ThemeColors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(GroveFont.mono(10))
                .tracking(0.8)
                .foregroundStyle(Color(theme.grey1))
            HStack(spacing: 8) {
                ForEach(schemes, id: \.self) { scheme in
                    if let colors = model.colors(for: scheme) {
                        SchemeTile(scheme: scheme, colors: colors,
                                   isCurrent: scheme == model.list?.current,
                                   isBusy: model.busyScheme == scheme) {
                            Task { await model.switchTo(scheme) }
                        }
                        .disabled(model.switchingDisabled)
                    }
                }
            }
        }
    }
}

/// The last switch in words; a step that needs you or failed is named in red,
/// with its message under the line.
private struct StatusLine: View {
    let entry: LogEntry
    @Environment(\.theme) private var theme

    var body: some View {
        let line = StatusText.line(for: entry, now: Date(), calendar: .current)
        let problems = StatusText.chips(for: entry).filter { $0.kind == .needsYou || $0.kind == .failed }
        // The line ends with " · <problems>" exactly when there are problems.
        var parts = line.components(separatedBy: " · ")
        let problemPart = problems.isEmpty ? nil : parts.popLast()
        let red = Color(theme.red)
        VStack(alignment: .leading, spacing: 4) {
            if let problemPart {
                Text("\(parts.joined(separator: " · ")) · \(Text(problemPart).foregroundStyle(red))")
            } else {
                Text(line)
            }
            ForEach(Array(problems.enumerated()), id: \.offset) { _, chip in
                Text(chip.message.isEmpty ? chip.text : "\(chip.text) — \(chip.message)")
                    .foregroundStyle(red)
            }
        }
        .font(GroveFont.mono(11.5))
        .lineSpacing(2)
        .opacity(0.85)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Open Grove Themes…" and "Quit": menu-like rows that light up in bg2 on hover.
private struct MenuRow: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var hovering = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(hovering.wrappedValue ? Color(theme.bg2) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.wrappedValue = $0 }
    }
}
