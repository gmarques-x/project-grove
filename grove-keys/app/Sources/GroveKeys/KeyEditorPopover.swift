import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The key editor (spec §7, mockup §1): Launcher (Hyper layer only) ·
/// AeroSpace (the command list or free text) · None. Every change goes through
/// `AppModel.edit`, which refuses while keys.toml is unread or has an error.
struct KeyEditorPopover: View {
    @ObservedObject var model: AppModel
    let target: EditTarget
    let layerTitle: String
    @Environment(\.theme) private var theme
    @FocusState private var fieldFocused: Bool

    enum Kind { case launcher, aerospace, none }

    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private var kind: State<Kind>
    private var text: State<String>
    private var search = State(initialValue: "")
    private var apps = State<[InstalledApps.App]>(initialValue: [])

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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Shortcut(aerospace: target.shortcut)?.symbols ?? target.shortcut)
                    .font(GroveFont.mono(13, .semibold))
                Spacer()
                Text("\(layerTitle) layer · \(kind.wrappedValue == .launcher ? "launch" : "aerospace.\(mode)")")
                    .font(GroveFont.mono(11))
                    .foregroundStyle(theme.quiet)
            }
            segments
            if !model.canEdit {
                theme.marked(model.redLine ?? "keys.toml isn't loaded yet", theme.red)
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
                    .font(GroveFont.mono(11))
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
            .font(GroveFont.mono(11))
            .foregroundStyle(theme.quiet)
            .lineLimit(1)
        }
        .padding(14)
        .frame(width: 330)
        .font(GroveFont.mono(12))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg1))
    }

    // MARK: Segments

    private var segments: some View {
        HStack(spacing: 3) {
            segment("Launcher", .launcher, enabled: isHyper)
                .help(isHyper ? "" : "Launchers live on the Hyper layer")
            segment("AeroSpace", .aerospace, enabled: true)
            segment("None", .none, enabled: model.canEdit)
        }
        .padding(3)
        .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
        .lightOutline(cornerRadius: GroveRadius.control)
    }

    private func segment(_ title: String, _ value: Kind, enabled: Bool) -> some View {
        let on = kind.wrappedValue == value
        return Button {
            kind.wrappedValue = value
            if value == .none { set(.none) }
        } label: {
            Text(title)
                .foregroundStyle(on ? Color(theme.fg) : theme.quiet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, GroveSpace.s4)
                .background(on ? Color(theme.bg3) : .clear, in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .lightOutline(cornerRadius: GroveRadius.control, when: on)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: Launcher

    private var launcher: some View {
        let current: String? = if case .launcher(let id) = action { id } else { nil }
        let query = search.wrappedValue.trimmingCharacters(in: .whitespaces)
        let shown = query.isEmpty ? apps.wrappedValue
            : apps.wrappedValue.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return VStack(alignment: .leading, spacing: 6) {
            TextField("Search apps", text: search.projectedValue)
                .textFieldStyle(.plain)
                .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s8)
                .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GroveSpace.s2) {
                    ForEach(shown) { app in
                        option(app.name, detail: app.bundleID == current ? "current" : "",
                               on: app.bundleID == current) {
                            set(.launcher(bundleID: app.bundleID))
                        }
                    }
                    if shown.isEmpty {
                        Text(apps.wrappedValue.isEmpty ? "Looking for apps…" : "No app matches")
                            .foregroundStyle(theme.quiet)
                            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
                    }
                }
                .padding(GroveSpace.s4)
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
        }
    }

    // MARK: AeroSpace

    private var aerospace: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            if !commandAllowed {
                theme.marked("Main-mode shortcuts need ⌃, ⌥ or ⌘", theme.orange)
                    .font(GroveFont.mono(11))
            }
            Group { commandList }.disabled(!commandAllowed)
        }
    }

    private var commandList: some View {
        let current: String? = if case .aerospace(let c) = action { c } else { nil }
        return VStack(alignment: .leading, spacing: GroveSpace.s8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GroveSpace.s2) {
                    ForEach(CommandCatalog.entries, id: \.template) { entry in
                        let command = CommandCatalog.command(template: entry.template, key: key)
                        option(entry.title, detail: entry.template.hasSuffix(" N") ? String(command.split(separator: " ").last ?? "") : "",
                               on: command == current) {
                            text.wrappedValue = command
                            set(.aerospace(command: command))
                        }
                    }
                    option("Custom command…", detail: "", on: false) { fieldFocused = true }
                }
                .padding(GroveSpace.s4)
            }
            .frame(height: 170)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control)
            HStack {
                TextField("workspace 1", text: text.projectedValue)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { set(.aerospace(command: text.wrappedValue)) }
                Text("AeroSpace syntax · ↩ saves").foregroundStyle(theme.quiet).font(GroveFont.mono(11))
            }
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s8)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(theme.line, lineWidth: 1))
        }
    }

    // MARK: Parts

    private func option(_ title: String, detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text(detail).foregroundStyle(theme.quiet).lineLimit(1)
            }
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
            .background(on ? Color(theme.bg2) : .clear, in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control, when: on)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func set(_ action: KeyAction) {
        let target = target
        model.edit { $0.assign(action, layerID: target.layerID, shortcut: target.shortcut) }
    }
}
