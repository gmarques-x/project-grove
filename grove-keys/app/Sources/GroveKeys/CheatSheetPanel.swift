import AppKit
import GroveKeysCore
import GroveThemesCore
import SwiftUI

/// The cheat sheet (spec §7, mockup §3): a borderless, non-activating panel
/// over the focused screen with a dimmed backdrop and the Hyper layer drawn
/// read-only. Shown by a Caps Lock hold it ignores the mouse and goes on
/// `hide()`; shown from the menu it goes on the next key press or click.
/// It never takes key focus from the front app.
@MainActor
final class CheatSheetPanel {
    private let model: AppModel
    private var panel: NSPanel?
    private var monitors: [Any] = []

    init(model: AppModel) {
        self.model = model
    }

    /// `untilInput`: the menu item's way, hidden by the next key or click.
    func show(untilInput: Bool) {
        hide()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        // Below the menu bar, as the mockup.
        let full = screen.frame
        let frame = NSRect(x: full.minX, y: full.minY, width: full.width,
                           height: max(0, screen.visibleFrame.maxY - full.minY))
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CheatSheetView(model: model, untilInput: untilInput))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        if untilInput {
            let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }) { monitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.hide()
                return event
            }) { monitors.append(local) }
        }
    }

    func hide() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The card: "Hyper", the modifier line, the Hyper layer's keyboard.
struct CheatSheetView: View {
    @ObservedObject var model: AppModel
    let untilInput: Bool
    static let cardWidth: CGFloat = 820

    var body: some View {
        let theme = model.colors
        let layer = model.layers.first { $0.id == "hyper" } ?? Layer(id: "hyper", title: "Hyper")
        ZStack {
            theme.scrim
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hyper")
                        .font(GroveFont.lockup(17))
                        .foregroundStyle(Color(theme.fg))
                    Spacer()
                    Text(untilInput ? "⌃⌥⇧⌘ · press any key to close" : "⌃⌥⇧⌘ · release Caps Lock to close")
                        .font(GroveFont.mono(12))
                        .foregroundStyle(theme.quiet)
                }
                KeyboardGrid(layer: layer, width: Self.cardWidth - 32, capHeight: 46) { _, name, legend, width, height in
                    KeyCapView(legend: legend, binding: layer.bindings[name], isModifier: false, held: false,
                               focused: false, width: width, height: height)
                }
            }
            .padding(16)
            .frame(width: Self.cardWidth)
            .background(Color(theme.bg0).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: theme.cardShadow, radius: 30, y: 15)
        }
        .font(GroveFont.mono(12))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }
}
