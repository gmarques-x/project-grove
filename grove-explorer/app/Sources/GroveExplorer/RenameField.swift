import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The rename field of a list (spec §6): where the row's name was, the name
/// without its extension selected, a 1 pt green line; red, with one line of
/// reason beneath, when the name typed can't be used. Return commits,
/// Escape cancels, and the keyboard going elsewhere (a click in the list)
/// commits as Finder does.
///
/// The list's coordinator owns one and calls `update` whenever it brings
/// the table in line with the model. The field lies over the row, scrolls
/// with it and outlives a reload of the rows.
@MainActor
final class RenameEditor: NSObject, NSTextFieldDelegate {
    private let model: AppModel
    private var box: RenameBox?
    private var note: NSHostingView<RenameNote>?
    /// The rename the field is for, and the reason it last showed.
    private var shown: UUID?
    private var reason: String?
    private weak var table: NSTableView?
    private var row = 0
    /// The field is being taken away, or Return or Escape was pressed: the
    /// end of its editing is not the keyboard leaving it.
    private var done = false

    /// The field is at least this wide when the column has the room (the mock-up's).
    private static let least: CGFloat = 220

    init(model: AppModel) {
        self.model = model
    }

    /// Shows the field for `state` over `row`, or takes it away (`state`
    /// nil). A rename whose row is no longer listed is given up.
    func update(_ state: RenameState?, row: Int?, in table: NSTableView, theme: ThemeColors) {
        guard let state, let row, row < table.numberOfRows else {
            remove()
            if let state {
                // After the turn: this runs while SwiftUI is updating its views.
                DispatchQueue.main.async { [model] in model.cancelRename(state.id) }
            }
            return
        }
        if state.id != shown {
            remove()
            let box = RenameBox(text: state.standIn ?? state.name, selecting: FileCommands.renameSelectionLength(
                of: state.name, isFolder: state.isFolder))
            box.field.delegate = self
            self.box = box
            shown = state.id
            done = false
        }
        guard let box, let clip = table.superview else { return }
        self.table = table
        self.row = row
        // Beside the table in its clip view, not in it: the table puts its
        // row views over anything of its own, and takes them out on a
        // reload. Laid out in the table's measures, so it scrolls with the row.
        if box.superview !== clip { clip.addSubview(box, positioned: .above, relativeTo: table) }
        if let list = table as? FileTableView, list.renameField !== box.field {
            list.renameField = box.field
            box.field.setAccessibilityParent(table)
        }
        box.frame = clip.convert(frame(for: box.field.stringValue, row: row, in: table), from: table)
        box.show(theme: theme, invalid: state.reason != nil)

        if state.reason != reason || (note != nil && note?.superview !== clip) {
            if state.reason != nil, state.reason != reason { refused(box) }
            reason = state.reason
            // The reason beneath is the field's to say.
            box.say(state.reason.map { "Name, " + $0 } ?? "Name")
            note?.removeFromSuperview()
            note = nil
            if let reason = state.reason {
                let view = NSHostingView(rootView: RenameNote(text: reason, theme: theme))
                clip.addSubview(view, positioned: .above, relativeTo: box)
                note = view
            }
        }
        if let note {
            let size = note.fittingSize
            note.frame = NSRect(x: box.frame.minX, y: box.frame.maxY + GroveSpace.s2, width: size.width, height: size.height)
        }
    }

    /// Where the name is drawn in its row (`NameCellView`), a field's
    /// padding further out, as wide as the name needs and the column allows.
    private func frame(for text: String, row: Int, in table: NSTableView) -> NSRect {
        let rowRect = table.rect(ofRow: row)
        let column = table.tableColumns.first?.width ?? rowRect.width
        let start = ListColumns.edge + IconMetrics.cell + ListMetrics.iconGap - RenameBox.padding
        let room = max(column - start - ListMetrics.nameTrailing, 0)
        let needed = CGFloat((text as NSString).length + 2) * ListMetrics.nameAdvance + 2 * RenameBox.padding
        return NSRect(
            x: start, y: rowRect.minY + GroveSpace.s2, width: min(max(needed, Self.least), room),
            height: rowRect.height - GroveSpace.s4)
    }

    /// The name was refused: the field is the place to put it right. Its
    /// editing may have ended meanwhile (a click elsewhere while the rename
    /// waited for its turn): it counts again, and the field takes the
    /// keyboard back, or no key would reach it and no command could run.
    private func refused(_ box: RenameBox) {
        done = false
        DispatchQueue.main.async { [weak box] in
            guard let box, let window = box.window, box.field.currentEditor() == nil else { return }
            window.makeFirstResponder(box.field)
        }
    }

    private func remove() {
        done = true
        box?.removeFromSuperview()
        box = nil
        note?.removeFromSuperview()
        note = nil
        shown = nil
        reason = nil
    }

    // MARK: The field

    func controlTextDidChange(_ notification: Notification) {
        model.renameEdited()
        // The field grows with the name.
        if let box, let table, let clip = table.superview, row < table.numberOfRows {
            box.frame = clip.convert(frame(for: box.field.stringValue, row: row, in: table), from: table)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)),
            #selector(NSResponder.insertBacktab(_:)):
            // The field stays until the rename is done: a name that can't
            // be used turns it red.
            model.commitRename(textView.string)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            done = true
            model.cancelRename()
            return true
        default:
            return false
        }
    }

    /// The keyboard went elsewhere (a click in a list).
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !done, let id = shown, let typed = box?.field.stringValue else { return }
        done = true
        // After the turn: this can come while SwiftUI is updating its views.
        DispatchQueue.main.async { [model] in
            guard model.work.rename?.id == id else { return }
            model.commitRename(typed, clickedAway: true)
        }
    }
}

/// The field and its outline: an opaque ground over the row, a 1 pt line
/// in green, or in red while the name can't be used.
private final class RenameBox: NSView {
    /// From the line to the text, as the mock-up's field.
    static let padding = GroveSpace.s4

    let field: RenameTextField

    init(text: String, selecting length: Int) {
        field = RenameTextField(string: text)
        field.selecting = length
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = GroveRadius.inline
        layer?.borderWidth = 1
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = ListMetrics.nameFont
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        addSubview(field)
        say("Name")
    }

    /// What VoiceOver calls the field. Its cell is the element VoiceOver
    /// meets, and has no words of the field's unless told too.
    func say(_ label: String) {
        field.setAccessibilityLabel(label)
        field.cell?.setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        // The cell keeps 2 pt of its own before its text.
        let inset = Self.padding - 2
        let height = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(
            x: inset, y: ((bounds.height - height) / 2).rounded(), width: max(bounds.width - 2 * inset, 0), height: height)
    }

    func show(theme: ThemeColors, invalid: Bool) {
        layer?.backgroundColor = NSColor(theme.bg0).cgColor
        layer?.borderColor = NSColor(invalid ? theme.red : theme.green).cgColor
        field.textColor = NSColor(theme.fg)
        needsLayout = true
    }
}

/// A text field that takes the keyboard as soon as it is in a window that
/// can have it (a render's can't), with the first `selecting` UTF-16 units
/// of its text selected.
private final class RenameTextField: NSTextField {
    var selecting = 0
    private var taken = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !taken, let window, window.canBecomeKey else { return }
        taken = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectedRange = NSRange(location: 0, length: self.selecting)
        }
    }
}

/// The one line of reason under a red field.
private struct RenameNote: View {
    let text: String
    let theme: ThemeColors

    var body: some View {
        theme.marked(text, theme.red)
            .font(GroveFont.mono(GroveType.body))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, GroveSpace.s4).padding(.vertical, GroveSpace.s2)
            .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.inline))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.inline).strokeBorder(theme.line, lineWidth: 1))
    }
}
