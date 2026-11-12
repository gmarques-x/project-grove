import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The key editor (spec §7, mockup §1): Launcher (Hyper layer only) ·
/// AeroSpace (the command list or free text) · None. Every change goes through
/// `AppModel.edit`, which refuses while keys.toml is unread or has an error.
/// It works from the keyboard: the pane's field has it on opening, ↑/↓ walk
/// the list, Return picks, Esc closes; Tab reaches the segments (←/→).
struct KeyEditorPopover: View {
    @ObservedObject var model: AppModel
    let target: EditTarget
    let layerTitle: String
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    enum Kind { case launcher, aerospace, none }

    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private var kind: State<Kind>
    private var text: State<String>
    private var search = State(initialValue: "")
    private var apps = State<[InstalledApps.App]>(initialValue: [])
    /// The app list's selected row (↑/↓ from the search field).
    private var appSelection = State(initialValue: KeyPanelSelection<String>())
    /// A segment was chosen since the editor opened: the pane then shown
    /// leaves the keyboard where it is (on the segments, when ←/→ chose it).
    private var switched = State(initialValue: false)
    /// Goes up when "Custom command…" is clicked: the command field takes the keyboard.
    private var fieldFocus = State(initialValue: 0)

    init(model: AppModel, target: EditTarget, layerTitle: String) {
        self.model = model
        self.target = target
        self.layerTitle = layerTitle
        let action = model.keys.action(layerID: target.layerID, shortcut: target.shortcut)
        switch action {
        case .launcher:
            kind = State(initialValue: .launcher)
            text = State(initialValue: "")
        case .aerospace(let command):
            kind = State(initialValue: .aerospace)
            text = State(initialValue: command)
        case .none:
            kind = State(initialValue: target.layerID == "hyper" ? .launcher : .aerospace)
            text = State(initialValue: "")
        }
    }

    private var isHyper: Bool { target.layerID == "hyper" }
    private var mode: String { KeyboardLayout.mode(layerID: target.layerID) }
    private var key: String { Shortcut(aerospace: target.shortcut)?.key ?? target.shortcut }
    /// On Hyper, choosing the other kind removes what the key does now.
    private var replacedText: String? {
        let byLauncher: Bool
        switch kind.wrappedValue {
        case .launcher: byLauncher = true
        case .aerospace: byLauncher = false
        case .none: return nil
        }
        switch model.keys.replaced(byLauncher: byLauncher, layerID: target.layerID, shortcut: target.shortcut) {
        case .aerospace(let command): return "Choosing an app replaces \(command)"
        case .launcher(let id): return "A command replaces \(Launcher.appName(bundleID: id) ?? id)"
        case .some(.none), nil: return nil
        }
    }

    /// A main-mode key without ⌃, ⌥ or ⌘ takes no AeroSpace command (as on the Bindings tab).
    private var commandAllowed: Bool {
        KeysFile.canAssignCommand(layerID: target.layerID, shortcut: target.shortcut)
    }

    private var action: KeyAction { model.keys.action(layerID: target.layerID, shortcut: target.shortcut) }

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Shortcut(aerospace: target.shortcut)?.symbols ?? target.shortcut)
                    .font(GroveFont.mono(GroveType.heading, .semibold))
                Spacer()
                Text("\(layerTitle) layer · \(kind.wrappedValue == .launcher ? "launch" : "aerospace.\(mode)")")
                    .font(GroveFont.mono(GroveType.body))
                    .foregroundStyle(theme.quiet)
            }
            segments
            if !model.canEdit {
                theme.marked(model.redLine ?? "keys.toml isn't loaded yet", theme.red, size: GroveType.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                switch kind.wrappedValue {
                case .launcher: launcher
                case .aerospace: aerospace
                case .none:
                    Text("\(Shortcut(aerospace: target.shortcut)?.symbols ?? target.shortcut) does nothing in this layer.")
                        .foregroundStyle(theme.quiet)
                }
            }
            .disabled(!model.canEdit)
            if let replaced = replacedText {
                theme.marked(replaced, theme.orange)
                    .font(GroveFont.mono(GroveType.body))
                    .lineLimit(1)
            }
            HStack {
                if let line = model.keys.savedLine(layerID: target.layerID, shortcut: target.shortcut) {
                    Text("Saved as ") + Text(line).foregroundColor(Color(theme.fg))
                } else {
                    Text("Not set")
                }
                Spacer()
                Text("esc").foregroundColor(Color(theme.fg)) + Text(" close")
            }
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(theme.quiet)
            .lineLimit(1)
        }
        .padding(GroveSpace.s12)
        .frame(width: 330)
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg1))
    }

    // MARK: Segments

    private var segments: some View {
        GroveSegmented("What the key does", segments: [
            GroveSegment(Kind.launcher, "Launcher", enabled: isHyper,
                         help: isHyper ? "" : "Launchers live on the Hyper layer"),
            GroveSegment(Kind.aerospace, "AeroSpace"),
            GroveSegment(Kind.none, "None", enabled: model.canEdit),
        ], selection: kind.wrappedValue, style: .pill(.base), fillsWidth: true) { value in
            switched.wrappedValue = true
            kind.wrappedValue = value
            if value == .none { set(.none) }
        }
    }

    // MARK: Launcher

    private var currentApp: String? {
        if case .launcher(let id) = action { id } else { nil }
    }

    private var shownApps: [InstalledApps.App] {
        let query = search.wrappedValue.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps.wrappedValue
            : apps.wrappedValue.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// The list as now filtered: its first row selected, or, with nothing
    /// typed, the key's current app.
    private func showApps() {
        appSelection.wrappedValue.show(shownApps.map(\.id))
        if search.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, let currentApp {
            appSelection.wrappedValue.select(currentApp)
        }
    }

    /// The search field has the keyboard when the editor opens; ↑/↓ walk the
    /// list from it and Return picks the selected app (GroveUI's `FilterField`
    /// and `KeyPanelList`, as the launcher).
    private var launcher: some View {
        let current = currentApp
        let shown = shownApps
        return VStack(alignment: .leading, spacing: GroveSpace.s8) {
            FilterField(text: search.wrappedValue, placeholder: "Search apps", theme: theme, size: GroveType.label,
                        takesFocus: !switched.wrappedValue,
                        onChange: { search.wrappedValue = $0; showApps() },
                        onMove: { appSelection.wrappedValue.move($0) },
                        onReturn: {
                            if let id = appSelection.wrappedValue.selected { set(.launcher(bundleID: id)) }
                        },
                        onEscape: { dismiss() })
                .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s8)
                .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
            Group {
                if shown.isEmpty {
                    Text(apps.wrappedValue.isEmpty ? "Looking for apps…" : "No app matches")
                        .foregroundStyle(theme.quiet)
                        .padding(.horizontal, GroveSpace.s12).padding(.vertical, GroveSpace.s8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    KeyPanelList(shown, selection: appSelection.wrappedValue.selected, rowHeight: Self.rowHeight,
                                 rowSpacing: GroveSpace.s2, insets: Self.listInsets,
                                 label: { $0.name + ($0.bundleID == current ? ", current" : "") },
                                 onClick: { set(.launcher(bundleID: $0.bundleID)) }) { app, _ in
                        option(app.name, detail: app.bundleID == current ? "current" : "")
                    }
                }
            }
            .frame(height: 180)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control)
        }
        .task {
            // Once per popover: the list stays while switching segments.
            guard apps.wrappedValue.isEmpty else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser
            apps.wrappedValue = await Task.detached {
                InstalledApps.scan(folders: InstalledApps.standardFolders(home: home))
            }.value
            showApps()
        }
    }

    // MARK: AeroSpace

    private var aerospace: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            if !commandAllowed {
                theme.marked("Main-mode shortcuts need ⌃, ⌥ or ⌘", theme.orange)
                    .font(GroveFont.mono(GroveType.body))
            }
            Group { commandList }.disabled(!commandAllowed)
        }
    }

    /// The command field has the keyboard when the editor opens. ↑/↓ walk
    /// the list from it and put the selected row's command in the field;
    /// Return saves what the field says, typed or picked.
    private var commandList: some View {
        let current: String? = if case .aerospace(let c) = action { c } else { nil }
        let rows = CommandCatalog.rows(key: key)
        // What the field says is where the selection is.
        let selected = CommandCatalog.rowID(for: text.wrappedValue, in: rows)
        return VStack(alignment: .leading, spacing: GroveSpace.s8) {
            KeyPanelList(rows, selection: selected, rowHeight: Self.rowHeight, rowSpacing: GroveSpace.s2,
                         insets: Self.listInsets,
                         label: { $0.title + ($0.command == current ? ", current" : "") },
                         onClick: { row in
                             guard let command = row.command else {
                                 // "Custom command…": type it.
                                 fieldFocus.wrappedValue += 1
                                 return
                             }
                             text.wrappedValue = command
                             set(.aerospace(command: command))
                         }) { row, _ in
                option(row.title, detail: [row.number, row.command == current ? "current" : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
            }
            .frame(height: 170)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control)
            HStack {
                FilterField(text: text.wrappedValue, placeholder: "workspace 1", theme: theme, size: GroveType.label,
                            takesFocus: !switched.wrappedValue && commandAllowed, focus: fieldFocus.wrappedValue,
                            onChange: { text.wrappedValue = $0 },
                            onMove: { step in
                                // The rows that write a command; ↓ past the last stays there.
                                let commands = rows.compactMap(\.command)
                                let at = commands.firstIndex(of: text.wrappedValue.trimmingCharacters(in: .whitespaces))
                                let next = at.map { min(max($0 + step, 0), commands.count - 1) } ?? (step > 0 ? 0 : commands.count - 1)
                                text.wrappedValue = commands[next]
                            },
                            onReturn: {
                                guard commandAllowed, model.canEdit else { return }
                                set(.aerospace(command: text.wrappedValue))
                            },
                            onEscape: { dismiss() })
                (Text("AeroSpace syntax · ") + GroveIcon.text(.run, size: GroveType.body) + Text(" saves"))
                    .foregroundStyle(theme.quiet).font(GroveFont.mono(GroveType.body))
                    .fixedSize()
            }
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s8)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
        }
    }

    // MARK: Parts

    /// A list row's height (the label's line and 4 above and below) and the
    /// list's inset in its well.
    private static let rowHeight: CGFloat = 24
    private static let listInsets = EdgeInsets(top: GroveSpace.s4, leading: GroveSpace.s4,
                                               bottom: GroveSpace.s4, trailing: GroveSpace.s4)

    /// What is in a row: its title, and on the right what marks it (a
    /// template's digit, "current").
    private func option(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            Text(detail).foregroundStyle(theme.quiet).lineLimit(1)
        }
    }

    private func set(_ action: KeyAction) {
        let target = target
        model.edit { $0.assign(action, layerID: target.layerID, shortcut: target.shortcut) }
    }
}
