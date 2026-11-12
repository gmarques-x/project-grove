import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The conflict prompt (spec §8): a card over the scrimmed window that asks
/// about one name that exists where an item is going. Skip, Replace or Keep
/// Both (the button Return takes: it loses nothing), for this name or with
/// the box for all the names after it; Cancel gives up the whole operation.
///
/// Keys: Return takes the button in the focus box, Escape is Cancel, Tab
/// and ← → move the box, Space ticks "Apply to all".
struct ConflictPrompt: View {
    let model: AppModel
    let state: ConflictPromptState
    @Environment(\.theme) private var theme

    /// The mock-up's measures: the card's width and the column of the two labels.
    private static let width: CGFloat = 460
    private static let labels: CGFloat = 96

    var body: some View {
        let question = state.question
        VStack(alignment: .leading, spacing: GroveSpace.s16) {
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                Text(verbatim: ConflictWords.title(for: question.existing))
                    .font(GroveFont.mono(GroveType.heading, .semibold))
                    .foregroundStyle(Color(theme.fg))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: GroveSpace.s4) {
                    pair(ConflictWords.thereLabel(for: question.existing), question.existingSize, question.existingDate)
                    pair(state.comingLabel, question.incomingSize, question.incomingDate)
                }
            }
            if question.remaining > 0 {
                Toggle(isOn: Binding(get: { state.applyToAll }, set: { model.work.prompt?.applyToAll = $0 })) {
                    Text(verbatim: ConflictWords.applyToAll(remaining: question.remaining))
                        .font(GroveFont.mono(GroveType.label))
                        .foregroundStyle(Color(theme.fg))
                }
                .toggleStyle(.checkbox)
                .tint(Color(theme.green))
            }
            HStack(spacing: GroveSpace.s8) {
                button(.cancel)
                Spacer()
                button(.skip)
                button(.replace)
                button(.keepBoth)
            }
        }
        .padding(GroveSpace.s16)
        .frame(width: Self.width)
        // Opaque, a 1 pt line, no shadow (spec §8).
        .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.card))
        .overlay(RoundedRectangle(cornerRadius: GroveRadius.card).strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("A name is taken")
    }

    private func pair(_ label: String, _ size: Int64?, _ date: Date?) -> some View {
        let clock = model.clock
        let written = date.map {
            Formatting.date($0, now: clock.now(), calendar: clock.calendar, locale: clock.locale, short: false)
        }
        return HStack(spacing: GroveSpace.s12) {
            Text(verbatim: label).foregroundStyle(theme.quiet).frame(width: Self.labels, alignment: .leading)
            Text(verbatim: ConflictWords.detail(size: size, date: written)).foregroundStyle(Color(theme.fg))
        }
        .font(GroveFont.mono(GroveType.body))
        .lineLimit(1)
    }

    private func button(_ button: ConflictButton) -> some View {
        PanelButton(button.title) { model.answerPrompt(button) }
            // The mock-up's outset, as a key cap's in Grove Keys.
            .focusBox(state.focus == button, cornerRadius: GroveRadius.control, outset: 3)
            .accessibilityAddTraits(state.focus == button ? .isSelected : [])
    }
}

/// The scrim under the prompt: the window behind takes no click.
struct PromptScrim: View {
    @Environment(\.theme) private var theme

    var body: some View {
        theme.scrim
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)
    }
}

extension AppModel {
    /// While the prompt is up, the keys of the Explorer window are the
    /// prompt's, whatever has the keyboard under the scrim (a list, the
    /// path field): caught before anything else sees them.
    func watchPromptKeys() {
        guard live, work.promptKeys == nil else { return }
        work.promptKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.work.prompt != nil, let window = event.window, window.canBecomeMain,
                window.sheetParent == nil, let stroke = CommandTable.stroke(of: event)
            else { return event }
            // Quitting, hiding and minimising stay the app's.
            if stroke.modifiers == [.command], ["Q", "H", "M"].contains(stroke.key) { return event }
            self.promptKey(stroke.key, shift: stroke.modifiers == [.shift], plain: stroke.modifiers.isEmpty)
            return nil
        }
    }

    func stopWatchingPromptKeys() {
        if let monitor = work.promptKeys { NSEvent.removeMonitor(monitor) }
        work.promptKeys = nil
    }

    private func promptKey(_ key: String, shift: Bool, plain: Bool) {
        guard let prompt = work.prompt, plain || (shift && key == "Tab") else { return }
        switch key {
        case "Return": answerPrompt(prompt.focus)
        case "Escape": answerPrompt(.cancel)
        case "Tab": work.prompt?.focus = shift ? prompt.focus.previous : prompt.focus.next
        case "→": work.prompt?.focus = prompt.focus.next
        case "←": work.prompt?.focus = prompt.focus.previous
        case "Space": if prompt.question.remaining > 0 { work.prompt?.applyToAll.toggle() }
        default: break
        }
    }
}
