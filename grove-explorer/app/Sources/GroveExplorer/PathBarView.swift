import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// A pane's path bar (spec §5): the folders from Home or the volume down to
/// the one showing, each a click. ⌘L turns it into `PathField`.
struct PathBarView: View {
    @ObservedObject var model: AppModel
    let side: Side
    @Environment(\.theme) private var theme
    /// The part under the pointer. `State` used directly: no SwiftUI macros here.
    private var hovered = State<URL?>(initialValue: nil)

    init(model: AppModel, side: Side) {
        self.model = model
        self.side = side
    }

    var body: some View {
        let parts = model.pathParts(for: side)
        HStack(spacing: GroveSpace.s4) {
            FolderIcon(mark: parts.first?.title == "Home" ? .home : .none)
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                let last = index == parts.count - 1
                self.part(part, last: last)
                    // The folder showing keeps its whole name longest.
                    .layoutPriority(last ? 1 : 0)
                if !last {
                    Text(verbatim: "›").foregroundStyle(theme.quiet).accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
        .font(GroveFont.mono(GroveType.label))
        .padding(.horizontal, GroveSpace.s16)
        .frame(height: BarMetrics.strip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }

    private func part(_ part: PathBar.Part, last: Bool) -> some View {
        Button {
            model.activate(side)
            model.go(to: part.url)
            model.focusList()
        } label: {
            Text(verbatim: part.title)
                .foregroundStyle(last ? Color(theme.fg) : theme.quiet)
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, GroveSpace.s4)
                .frame(height: BarMetrics.control - GroveSpace.s4)
                .background(
                    hovered.wrappedValue == part.url ? theme.hoverFill(on: .base) : .clear,
                    in: RoundedRectangle(cornerRadius: GroveRadius.inline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered.wrappedValue = part.url } else if hovered.wrappedValue == part.url { hovered.wrappedValue = nil }
        }
        .accessibilityLabel(part.title)
        // The folder showing is the current one of the path.
        .accessibilityAddTraits(last ? .isSelected : [])
    }
}

/// The path bar as a text field (⌘L, ⌘⇧G): the full path, selected. Return
/// goes, Escape cancels, Tab completes a folder's name. It takes a 1 pt
/// green line, not the focus box; a path that isn't there turns the line
/// red and the field stays.
struct PathField: View {
    @ObservedObject var model: AppModel
    let state: PathFieldState
    /// The pane is wide enough for the hint.
    let showsHint: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: GroveSpace.s8) {
            PathTextField(model: model, text: state.text, theme: theme)
                .accessibilityLabel(state.missing ? "Path, there is no such folder" : "Path")
            if showsHint {
                (GroveIcon.text(.run, size: GroveType.finePrint) + Text(verbatim: " go · esc cancel · tab completes"))
                    .font(GroveFont.mono(GroveType.finePrint))
                    .foregroundStyle(theme.quiet)
                    .lineLimit(1).fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, GroveSpace.s8)
        .frame(height: BarMetrics.control)
        .overlay(
            RoundedRectangle(cornerRadius: GroveRadius.control)
                .strokeBorder(Color(state.missing ? theme.red : theme.green), lineWidth: 1))
        .padding(.horizontal, GroveSpace.s8)
        .frame(height: BarMetrics.strip)
        .help(state.missing ? "There is no such folder" : "")
    }
}

/// The field itself: AppKit's, for what SwiftUI's can't do on macOS 14
/// (start with its text selected; tell Return, Escape and Tab apart).
private struct PathTextField: NSViewRepresentable {
    let model: AppModel
    let text: String
    let theme: ThemeColors

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FirstResponderField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = GroveFont.monoNS(GroveType.label)
        field.lineBreakMode = .byTruncatingHead
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Path")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.textColor = NSColor(theme.fg)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private weak var model: AppModel?
        /// Return or Escape already closed the field: its end of editing is not a cancel.
        private var done = false

        init(model: AppModel) {
            self.model = model
        }

        func controlTextDidChange(_ notification: Notification) {
            model?.pathFieldEdited()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                model?.commitPathField(textView.string)
                // Still there: the path was missing and the field stays.
                done = model?.pathField == nil
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                done = true
                model?.cancelPathField()
                return true
            case #selector(NSResponder.insertTab(_:)):
                let typed = textView.string
                model?.completePath(typed) { [weak self, weak textView] completed in
                    // Typed on meanwhile: the answer is for a text that is gone.
                    guard let completed, let textView, textView.string == typed else { return }
                    textView.string = completed
                    textView.setSelectedRange(NSRange(location: (completed as NSString).length, length: 0))
                    self?.model?.pathFieldEdited()
                }
                return true
            default:
                return false
            }
        }

        /// The keyboard went elsewhere (a click in a list): the field closes.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard !done else { return }
            done = true
            // After the turn: this can come while SwiftUI is updating its views.
            DispatchQueue.main.async { [weak model] in model?.cancelPathField() }
        }
    }
}

/// A text field that takes the keyboard, with its text selected, as soon as
/// it is in a window that can have the keyboard (a render's can't).
private final class FirstResponderField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.canBecomeKey else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self)
            self.selectText(nil)
        }
    }
}
