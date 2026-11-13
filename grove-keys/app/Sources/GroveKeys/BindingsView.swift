import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The Bindings tab (spec §7, mockup §2): keys.toml as grouped rows. Left:
/// Hyper key, Launchers, Monitors; right: one group per AeroSpace mode. Rows
/// are recorder · action · remove; runs of 1…9 fold until "Show all". Every
/// change goes through `AppModel.edit` (refused, and the controls disabled,
/// while keys.toml is unread or has an error).
///
/// One row can be selected: a click selects, ↑/↓ (Ctrl+K/J) move within and
/// across the groups, Return starts recording the row's shortcut, Delete
/// removes it as "−" does (at once), and a right click offers both. The
/// selection is drawn as in every Grove list (`selectedFill`), not in the
/// system's accent. While a row records, the recorder has every key; while a
/// text field is being typed in, the field has them.
///
/// Not a `Table`, on purpose: each row is edited in place (a recorder, a
/// command field, an app picker), runs of 1…9 fold into one row, a clash
/// prompt opens under its row, and there are several small groups side by
/// side. A `Table` gives one flat list of text columns. The owner compared
/// renders of both and chose these rows.
struct BindingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    @StateObject private var recorder = ShortcutRecorder()
    @FocusState private var draftFocused: Bool
    /// The tab has the keyboard (not a text field in it): ↑/↓, Return, Delete.
    @FocusState private var hasKeys: Bool

    /// A recording that hit a shortcut already in use, waiting for Replace / Cancel.
    struct PendingClash {
        var row: String
        /// Nil for a new row (the draft).
        var from: BindingSlot?
        var to: BindingSlot
        var clashes: [BindingSlot]
    }

    /// A row being added: its group ("launch" or a mode) and, once recorded, its slot.
    struct Draft {
        var group: String
        var slot: BindingSlot?
        var replacing: [BindingSlot] = []
        var text = ""
    }

    /// The app picker (the Keyboard tab's editor on a Hyper key), and the row it opens on.
    struct AppPick: Identifiable {
        var anchor: String
        var target: EditTarget
        var id: String { anchor }
    }

    // `State` used directly: no SwiftUI macros with the Command Line Tools.
    private var expanded = State<Set<String>>(initialValue: [])
    private var clash = State<PendingClash?>(initialValue: nil)
    /// The row whose last press was a bare or shift-only key in main (still recording).
    private var unsafeRow = State<String?>(initialValue: nil)
    private var draft = State<Draft?>(initialValue: nil)
    private var appPick = State<AppPick?>(initialValue: nil)
    /// The selected row's id ("launch:t", "mode:main:alt-h"); nil at first.
    private var selected = State<String?>(initialValue: nil)

    /// A row the keyboard can act on: what Return and Delete do to it.
    struct RowRef {
        var id: String
        var recordable: Bool
        var record: () -> Void
        var remove: () -> Void
    }

    static let height: CGFloat = 620

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s12) {
            if !model.canEdit, model.redLine == nil {
                Text("keys.toml isn't loaded yet")
                    .foregroundStyle(theme.quiet)
                    .padding(.horizontal, GroveSpace.s24)
            }
            ScrollViewReader { scroll in
            ScrollView {
                HStack(alignment: .top, spacing: GroveSpace.s16) {
                    VStack(spacing: GroveSpace.s16) {
                        HyperGroup(model: model)
                        launchers
                        MonitorsView(model: model)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: GroveSpace.s16) {
                        ForEach(model.keys.modes.map(\.name), id: \.self) { mode in
                            modeGroup(mode)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .disabled(!model.canEdit)
                .padding(.horizontal, GroveSpace.s24)
                .padding(.top, GroveWindow.contentGap)
                .padding(.bottom, GroveSpace.s24)
            }
            .onChange(of: selected.wrappedValue) { _, row in
                if let row { scroll.scrollTo(row) }
            }
            }
        }
        .frame(height: Self.height)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($hasKeys)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onAppear { hasKeys = true }
        .onDisappear { recorder.cancel() }
        .onChange(of: model.canEdit) { _, can in
            if !can { recorder.cancel(); clash.wrappedValue = nil }
        }
    }

    // MARK: Launchers

    private var launchers: some View {
        let keys = model.keys
        let conflicts = Layers.conflictingLaunchKeys(keys)
        let hyper = model.layers.first { $0.id == "hyper" }
        return BindingsGroup(title: "Launchers", note: "Hyper + key") {
            VStack(spacing: GroveSpace.s2) {
                ForEach(keys.launch.map(\.key), id: \.self) { key in
                    let row = "launch:" + key
                    let binding = hyper?.bindings[key]
                    let missing = binding?.missingApp ?? false
                    let slot = BindingSlot.launcher(key: key)
                    RowView(
                        shortcut: Self.launcherSymbols(key, model.legends), recording: recorder.recording == row,
                        recordable: true, conflict: conflicts.contains(key) ? "Also a ⌃⌥⇧⌘ AeroSpace binding · the launcher wins" : nil,
                        selected: selected.wrappedValue == row, onSelect: { select(row) },
                        onRecord: { record(row: row, from: slot, launcher: true, mode: "main") },
                        onRemove: { remove(row) { $0.remove([slot]) } }
                    ) {
                        Button { pickApp(anchor: row, key: key) } label: {
                            HStack(spacing: GroveSpace.s8) {
                                Text(binding?.label ?? key)
                                    .strikethrough(missing)
                                    .foregroundStyle(missing ? theme.quiet : Color(theme.fg))
                                if missing {
                                    Text("not installed").font(GroveFont.mono(GroveType.body)).foregroundStyle(theme.quiet)
                                }
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(missing ? "\(binding?.label ?? key) is not installed" : "Choose another app")
                        .popover(item: pickBinding(row), arrowEdge: .bottom) { popover($0) }
                    }
                    .id(row)
                    clashLine(row)
                }
                if let d = draft.wrappedValue, d.group == "launch" {
                    let row = "draft:launch"
                    RowView(shortcut: "record", recording: recorder.recording == row, recordable: true, conflict: nil,
                            selected: false, onSelect: nil,
                            onRecord: { record(row: row, from: nil, launcher: true, mode: "main") },
                            onRemove: { cancelDraft() }) {
                        Text("choose an app").foregroundStyle(theme.quiet)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    clashLine(row)
                }
            }
            addButton("Add launcher", group: "launch")
                .popover(item: pickBinding("add:launch"), arrowEdge: .bottom) { popover($0) }
        }
    }

    private static func launcherSymbols(_ key: String, _ legends: Legends) -> String {
        Shortcut(modifiers: Set(Modifier.allCases), key: key).symbols(using: legends)
    }

    private func pickApp(anchor: String, key: String) {
        appPick.wrappedValue = AppPick(anchor: anchor, target: EditTarget(layerID: "hyper", shortcut: "hyper-" + key))
    }

    private func pickBinding(_ anchor: String) -> Binding<AppPick?> {
        Binding(
            get: { appPick.wrappedValue?.anchor == anchor ? appPick.wrappedValue : nil },
            set: { if $0 == nil, appPick.wrappedValue?.anchor == anchor { appPick.wrappedValue = nil } })
    }

    private func popover(_ pick: AppPick) -> some View {
        KeyEditorPopover(model: model, target: pick.target, layerTitle: "Hyper")
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
    }

    // MARK: Modes

    private func modeGroup(_ mode: String) -> some View {
        let bindings = model.keys.modes.first { $0.name == mode }?.bindings ?? []
        let open = expanded.wrappedValue.contains(mode)
        let rows = BindingRows.rows(mode: bindings, folded: !open, legends: model.legends)
        let canFold = BindingRows.rows(mode: bindings, folded: true).count < bindings.count
        let conflicts = mode == "main" ? Layers.conflictingAerospaceKeys(model.keys) : []
        return BindingsGroup(title: "AeroSpace · \(mode)", note: bindings.count == 1 ? "1 binding" : "\(bindings.count) bindings") {
            VStack(spacing: GroveSpace.s2) {
                ForEach(rows, id: \.keys) { r in
                    let row = "mode:\(mode):" + r.keys[0]
                    let slot = BindingSlot.binding(mode: mode, key: r.keys[0])
                    RowView(
                        shortcut: r.shortcuts, recording: recorder.recording == row, recordable: r.count == 1,
                        conflict: r.keys.contains(where: conflicts.contains) ? "Hyper + this key opens a launcher, so this binding never fires" : nil,
                        selected: selected.wrappedValue == row, onSelect: { select(row) },
                        onRecord: { record(row: row, from: slot, launcher: false, mode: mode) },
                        onRemove: { remove(row) { $0.remove(r.keys.map { .binding(mode: mode, key: $0) }) } }
                    ) {
                        if r.count > 1 {
                            HStack(spacing: GroveSpace.s8) {
                                Text(r.action).lineLimit(1)
                                Text("\(r.count) rows").font(GroveFont.mono(GroveType.body)).foregroundStyle(theme.quiet)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help("Show all to change one of them; − removes all \(r.count)")
                        } else {
                            CommandField(text: r.action) { text in
                                model.edit { $0.setCommand(slot, text) }
                            }
                            .id(r.action)
                        }
                    }
                    .id(row)
                    clashLine(row)
                }
                if let d = draft.wrappedValue, d.group == mode {
                    draftRow(d, mode: mode)
                }
            }
            if canFold || open {
                Button {
                    if open { expanded.wrappedValue.remove(mode) } else { expanded.wrappedValue.insert(mode) }
                } label: {
                    Text(open ? "Fold runs of 1…9" : "Show all \(bindings.count) · runs of 1…9 fold into one row")
                        .font(GroveFont.mono(GroveType.label))
                        .foregroundStyle(theme.quiet)
                        .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            addButton("Add binding", group: mode)
        }
    }

    private func draftRow(_ d: Draft, mode: String) -> some View {
        let row = "draft:" + mode
        let shortcut: String = if case .binding(_, let key) = d.slot {
            Shortcut(aerospace: key)?.symbols(using: model.legends) ?? key
        } else { "" }
        return VStack(spacing: GroveSpace.s2) {
            RowView(shortcut: shortcut.isEmpty ? "record" : shortcut, recording: recorder.recording == row,
                    recordable: true, conflict: nil, selected: false, onSelect: nil,
                    onRecord: { record(row: row, from: nil, launcher: false, mode: mode) },
                    onRemove: { cancelDraft() }) {
                TextField(mode == "main" ? "command, e.g. workspace 1" : "command, mode main", text: Binding(
                    get: { draft.wrappedValue?.text ?? "" },
                    set: { draft.wrappedValue?.text = $0 }))
                    .textFieldStyle(.plain)
                    .focused($draftFocused)
                    .onSubmit { saveDraft() }
            }
            clashLine(row)
            if d.slot == nil, recorder.recording != row, clash.wrappedValue?.row != row {
                hint("Click the first box and press the shortcut")
            } else if d.slot != nil {
                hint(GroveIcon.text(.run, size: GroveType.body) + Text(" saves · a, b runs both"))
            }
        }
    }

    // MARK: Selection and keys

    /// Every row that can be selected, in the order ↑/↓ walk them: the
    /// launchers, then each mode's rows as now shown (folded or not). A row
    /// being added is not one of them.
    private var rowRefs: [RowRef] {
        var refs: [RowRef] = []
        for key in model.keys.launch.map(\.key) {
            let row = "launch:" + key, slot = BindingSlot.launcher(key: key)
            refs.append(RowRef(id: row, recordable: true,
                               record: { record(row: row, from: slot, launcher: true, mode: "main") },
                               remove: { remove(row) { $0.remove([slot]) } }))
        }
        for mode in model.keys.modes {
            let name = mode.name
            for r in BindingRows.rows(mode: mode.bindings, folded: !expanded.wrappedValue.contains(name)) {
                let row = "mode:\(name):" + r.keys[0], slot = BindingSlot.binding(mode: name, key: r.keys[0])
                refs.append(RowRef(id: row, recordable: r.count == 1,
                                   record: { record(row: row, from: slot, launcher: false, mode: name) },
                                   remove: { remove(row) { $0.remove(r.keys.map { .binding(mode: name, key: $0) }) } }))
            }
        }
        return refs
    }

    /// A click on a row. The tab takes the keyboard for it, unless the click
    /// went into a text field (which then has it).
    private func select(_ row: String) {
        selected.wrappedValue = row
        DispatchQueue.main.async {
            if !(NSApp.keyWindow?.firstResponder is NSText) { hasKeys = true }
        }
    }

    /// Removes a row as "−" does (at once, no prompt); if it was the
    /// selected one, its neighbour is selected.
    private func remove(_ row: String, _ change: @escaping (inout KeysFile) -> Void) {
        if selected.wrappedValue == row {
            selected.wrappedValue = BindingRows.neighbor(ofRemoved: row, in: rowRefs.map(\.id))
        }
        model.edit(change)
    }

    /// ↑/↓ (Ctrl+K/J), Return and Delete, when the tab has the keyboard.
    /// None of them arrives while a row is recording (the recorder swallows
    /// the key first) or while a text field is typed in (the field takes it).
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard model.canEdit, recorder.recording == nil else { return .ignored }
        let refs = rowRefs
        if let direction = KeyboardView.direction(press) {
            guard direction == .up || direction == .down else { return .ignored }
            selected.wrappedValue = BindingRows.step(from: selected.wrappedValue, by: direction == .up ? -1 : 1,
                                                     in: refs.map(\.id))
            return .handled
        }
        guard let ref = refs.first(where: { $0.id == selected.wrappedValue }) else { return .ignored }
        switch press.key {
        case .return:
            // A clash prompt takes Return itself (Replace).
            guard clash.wrappedValue == nil, ref.recordable else { return .ignored }
            ref.record()
            return .handled
        case .delete, .deleteForward:
            ref.remove()
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: Recording

    private func record(row: String, from: BindingSlot?, launcher: Bool, mode: String) {
        clash.wrappedValue = nil
        unsafeRow.wrappedValue = nil
        if recorder.recording == row { recorder.cancel(); return }
        recorder.start(row, onRecord: { shortcut in
            let to = BindingSlot.recorded(shortcut, launcher: launcher, mode: mode)
            // A main-mode key without ⌃, ⌥ or ⌘ would be taken from every app:
            // ignore the press and keep recording.
            guard to.isSafe else {
                record(row: row, from: from, launcher: launcher, mode: mode)
                unsafeRow.wrappedValue = row
                return
            }
            let clashes = model.keys.clashes(to, except: from)
            if clashes.isEmpty {
                commit(from: from, to: to, replacing: [])
            } else {
                clash.wrappedValue = PendingClash(row: row, from: from, to: to, clashes: clashes)
            }
        }, onCancel: {
            // Esc (or another row starting) on this new row with nothing
            // recorded drops it.
            if from == nil, let d = draft.wrappedValue, "draft:" + d.group == row, d.slot == nil {
                draft.wrappedValue = nil
            }
        })
    }

    private func commit(from: BindingSlot?, to: BindingSlot, replacing: [BindingSlot]) {
        clash.wrappedValue = nil
        if let from {
            model.edit { $0.move(from, to: to, replacing: replacing) }
            return
        }
        switch to {
        case .launcher(let key):
            // The app picker writes it with `assign(.launcher)`, which removes
            // the clashing hyper- binding (spelled out or not) and overwrites a
            // launcher on the key: `replacing` is applied there (tested in
            // BindingsEditTests.launcherReplaceRemovesTheHyperBinding). Closing
            // the picker without an app changes nothing.
            draft.wrappedValue = nil
            pickApp(anchor: "add:launch", key: key)
        case .binding:
            draft.wrappedValue?.slot = to
            draft.wrappedValue?.replacing = replacing
            draftFocused = true
            if let d = draft.wrappedValue, BindingRows.value(fromText: d.text) != nil { saveDraft() }
        }
    }

    private func saveDraft() {
        guard let d = draft.wrappedValue, let slot = d.slot, BindingRows.value(fromText: d.text) != nil else { return }
        model.edit { $0.add(slot, command: d.text, replacing: d.replacing) }
        draft.wrappedValue = nil
    }

    private func cancelDraft() {
        if recorder.recording?.hasPrefix("draft:") == true { recorder.cancel() }
        if clash.wrappedValue?.row.hasPrefix("draft:") == true { clash.wrappedValue = nil }
        draft.wrappedValue = nil
    }

    private func addButton(_ title: String, group: String) -> some View {
        Button {
            let row = "draft:" + group
            // Cancel first, so the old recording's cancel can't drop the new draft.
            recorder.cancel()
            draft.wrappedValue = Draft(group: group)
            record(row: row, from: nil, launcher: group == "launch", mode: group == "launch" ? "main" : group)
        } label: {
            // The plus and "Add …": all green in dark; in light the plus keeps the green.
            (GroveIcon.text(.add, size: GroveType.label).foregroundStyle(Color(theme.green)) + Text(" " + title).foregroundStyle(theme.ink(theme.green)))
                .font(GroveFont.mono(GroveType.label))
                .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: Clash prompt

    @ViewBuilder
    private func clashLine(_ row: String) -> some View {
        if unsafeRow.wrappedValue == row, recorder.recording == row {
            // A warning: orange in dark; in light a dot carries it and the words are fg.
            theme.marked("Main-mode shortcuts need ⌃, ⌥ or ⌘", theme.orange)
                .font(GroveFont.mono(GroveType.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GroveSpace.s8)
        }
        if let c = clash.wrappedValue, c.row == row {
            HStack(spacing: GroveSpace.s12) {
                theme.marked("\(describe(c.to)) already: " + c.clashes.map(action).joined(separator: "; "), theme.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Return replaces, Esc cancels. The prompt only shows once the
                // recording is over; while one runs the two are off all the same.
                small("Replace", primary: true) { commit(from: c.from, to: c.to, replacing: c.clashes) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(recorder.recording != nil)
                small("Cancel", primary: false) { clash.wrappedValue = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(recorder.recording != nil)
            }
            .font(GroveFont.mono(GroveType.body))
            .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
        }
    }

    private func describe(_ slot: BindingSlot) -> String {
        switch slot {
        case .launcher(let key): return Self.launcherSymbols(key, model.legends)
        case .binding(_, let key): return Shortcut(aerospace: key)?.symbols(using: model.legends) ?? key
        }
    }

    /// What a clashing entry does now: "workspace 1", "opens Ghostty".
    private func action(_ slot: BindingSlot) -> String {
        switch slot {
        case .launcher(let key):
            let id = model.keys.launch.first { $0.key == key }?.bundleID ?? key
            return "opens " + (Launcher.appName(bundleID: id) ?? id)
        case .binding(let mode, let key):
            let entries = (model.keys.modes.first { $0.name == mode }?.bindings ?? []).filter { $0.key == key }
            return BindingRows.rows(mode: entries, folded: false).first?.action ?? key
        }
    }

    private func small(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GroveFont.mono(GroveType.label, .semibold))
                .foregroundStyle(Color(primary ? theme.onAccent : theme.fg))
                .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
                .background(Color(primary ? theme.orange : theme.bg3), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .lightOutline(cornerRadius: GroveRadius.control, when: !primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hint(_ text: String) -> some View { hint(Text(text)) }

    private func hint(_ text: Text) -> some View {
        text
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(theme.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GroveSpace.s8)
    }
}

/// A rounded bg1 group with a small-caps title and a note on the right.
struct BindingsGroup<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(GroveFont.mono(GroveType.body, .semibold))
                    .tracking(1.1)
                    .foregroundStyle(theme.quiet)
                Spacer()
                Text(note).font(GroveFont.mono(GroveType.body)).foregroundStyle(theme.quiet(dark: 0.8))
            }
            content
        }
        .padding(.horizontal, GroveSpace.s12).padding(.vertical, GroveSpace.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(theme.bg1), in: RoundedRectangle(cornerRadius: GroveRadius.card))
        .lightOutline(cornerRadius: GroveRadius.card)
    }
}

/// One row: recorder pill (128 pt) · action · conflict mark · remove.
private struct RowView<Action: View>: View {
    let shortcut: String
    let recording: Bool
    let recordable: Bool
    /// The orange mark's tooltip, when the row is in a launcher/Hyper clash.
    let conflict: String?
    /// The selected row: lit as the selected row of every Grove list.
    let selected: Bool
    /// A click anywhere in the row; nil for a row that can't be selected (one being added).
    let onSelect: (() -> Void)?
    let onRecord: () -> Void
    let onRemove: () -> Void
    @ViewBuilder let action: Action
    @Environment(\.theme) private var theme
    private var hover = State(initialValue: false)

    init(shortcut: String, recording: Bool, recordable: Bool, conflict: String?, selected: Bool,
         onSelect: (() -> Void)?, onRecord: @escaping () -> Void, onRemove: @escaping () -> Void,
         @ViewBuilder action: () -> Action) {
        self.shortcut = shortcut
        self.recording = recording
        self.recordable = recordable
        self.conflict = conflict
        self.selected = selected
        self.onSelect = onSelect
        self.onRecord = onRecord
        self.onRemove = onRemove
        self.action = action()
    }

    var body: some View {
        HStack(spacing: GroveSpace.s12) {
            RecorderPill(text: shortcut, recording: recording, enabled: recordable, action: onRecord)
                .help(recordable ? "Click, then press the new shortcut · esc cancels" : "Show all to change one of them")
                .frame(width: 128, alignment: .leading)
            action
                .font(GroveFont.mono(GroveType.label))
            if let conflict {
                Circle().fill(Color(theme.orange)).frame(width: 7, height: 7).help(conflict)
            }
            Button(action: onRemove) {
                // 18 pt wide whatever the symbol's own width, so the column stays put.
                GroveIcon(.remove, size: GroveType.label).foregroundStyle(theme.quiet)
                    .frame(width: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
            .accessibilityLabel("Remove")
        }
        .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
        // On a bg1 group: bg3 selected, bg2 under the pointer or recording.
        .background(selected ? theme.selectedFill(on: .panel)
                        : (hover.wrappedValue || recording ? theme.hoverFill(on: .panel) : Color.clear),
                    in: RoundedRectangle(cornerRadius: GroveRadius.control))
        .lightOutline(cornerRadius: GroveRadius.control, when: selected)
        .contentShape(Rectangle())
        .onHover { hover.wrappedValue = $0 }
        // With the row's own controls, not instead of them: a click on the
        // recorder or the field selects the row too.
        .simultaneousGesture(TapGesture().onEnded { onSelect?() })
        .contextMenu {
            if onSelect != nil {
                Button("Record shortcut", action: onRecord).disabled(!recordable)
                Button("Remove", action: onRemove)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row's action as editable text: written on Return or when focus leaves,
/// only if changed; blank is put back.
private struct CommandField: View {
    let text: String
    let onCommit: (String) -> Void
    @FocusState private var focused: Bool
    private var draft: State<String>

    init(text: String, onCommit: @escaping (String) -> Void) {
        self.text = text
        self.onCommit = onCommit
        draft = State(initialValue: text)
    }

    var body: some View {
        TextField("command", text: draft.projectedValue)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .help("AeroSpace syntax · a, b runs both · ↩ saves")
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, now in if !now { commit() } }
    }

    private func commit() {
        let typed = draft.wrappedValue
        guard typed != text else { return }
        if BindingRows.value(fromText: typed) == nil {
            draft.wrappedValue = text
        } else {
            onCommit(typed)
        }
    }
}
