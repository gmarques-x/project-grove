import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The Monitors group (spec §7, §10, mockup §2): this Mac's monitors.toml,
/// a menu per workspace 1–9.
struct MonitorsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private var displays = State(initialValue: Displays.current())

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        let saved = model.monitors.assignments
        let targets = Dictionary(saved.map { ($0.workspace, $0.target) }, uniquingKeysWith: { a, _ in a })
        let choices = Monitors.choices(displays: displays.wrappedValue, current: saved.map(\.target))
        BindingsGroup(title: "Monitors", note: "this Mac") {
            HStack(spacing: GroveSpace.s8) {
                Circle().fill(Color(theme.green)).frame(width: 7, height: 7)
                Text(connected)
            }
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(theme.quiet)
            .padding(.horizontal, GroveSpace.s8)
            if saved.isEmpty { note("Not set for this Mac yet") }
            HStack(spacing: GroveSpace.s4) {
                ForEach(1...9, id: \.self) { n in
                    cell(n, target: targets[String(n)], choices: choices)
                }
            }
            .disabled(!model.canEditMonitors)
            note("Each workspace: main · secondary · built-in · a display name. Saved only for this Mac, in monitors.toml.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays.wrappedValue = Displays.current()
        }
    }

    private var connected: String {
        let names = displays.wrappedValue
        guard let first = names.first else { return "Connected now: none" }
        return "Connected now: " + ([first + " (main)"] + names.dropFirst()).joined(separator: ", ")
    }

    private func cell(_ n: Int, target: String?, choices: [String]) -> some View {
        GroveSelect("Workspace \(n)'s monitor", options: choices.map { GroveSelectOption($0, $0) }, selection: target,
                    valueText: target ?? "not set, main screen") { choice in
            model.editMonitors { $0.set(workspace: String(n), target: choice) }
        } label: {
            VStack(spacing: GroveSpace.s4) {
                Text(String(n)).font(GroveFont.mono(GroveType.heading, .semibold)).foregroundStyle(theme.ink(theme.green))
                (Text((target ?? "main") + " ") + GroveIcon.text(.menu, size: GroveType.finePrint))
                    .font(GroveFont.mono(GroveType.finePrint))
                    .foregroundStyle(theme.quiet)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GroveSpace.s4).padding(.horizontal, GroveSpace.s2)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control)
            .contentShape(Rectangle())
        }
        .help(target.map { "Workspace \(n) → \($0)" } ?? "Workspace \(n): not set (main screen)")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(theme.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
    }
}
