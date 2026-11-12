import AppKit
import Combine
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// Records one shortcut for one row (spec §7): the next key-down in the app,
/// caught with a local `NSEvent` monitor and swallowed. All four modifiers
/// make `hyper-`; Esc cancels; a key with no AeroSpace name is ignored and
/// recording goes on. One row records at a time.
@MainActor
final class ShortcutRecorder: ObservableObject {
    /// The row that is recording now.
    @Published private(set) var recording: String?
    private var monitor: Any?
    private var onRecord: ((Shortcut) -> Void)?
    private var onCancel: (() -> Void)?

    /// A recording already running on another row is cancelled (its
    /// `onCancel` runs), so an empty new row doesn't linger.
    func start(_ row: String, onRecord: @escaping (Shortcut) -> Void, onCancel: @escaping () -> Void = {}) {
        if recording != nil { cancel() }
        recording = row
        self.onRecord = onRecord
        self.onCancel = onCancel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
    }

    /// Stops without recording (Esc, another row, the tab going away).
    func cancel() {
        let callback = onCancel
        stop()
        callback?()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.intersection([.command, .control, .option, .shift]).isEmpty {
            cancel()
            return
        }
        guard let shortcut = Shortcut(keyCode: event.keyCode, flags: UInt(flags.rawValue)) else { return }
        let callback = onRecord
        stop()
        callback?(shortcut)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        onRecord = nil
        onCancel = nil
    }
}

/// The recorder pill at the start of a row: the shortcut, or "press keys…"
/// with a green border while recording.
struct RecorderPill: View {
    let text: String
    let recording: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(recording ? "press keys…" : text)
                .font(GroveFont.mono(GroveType.label))
                .foregroundStyle(recording ? theme.ink(theme.green) : Color(theme.fg))
                .lineLimit(1)
                .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
                .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .overlay(RoundedRectangle(cornerRadius: GroveRadius.control)
                    .strokeBorder(recording ? Color(theme.green) : theme.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
