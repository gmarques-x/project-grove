import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The cheat sheet shown while Caps Lock is held (spec §7, mockup §3): a
/// borderless, non-activating panel over the focused screen with a dimmed
/// backdrop and the Hyper layer drawn read-only. It ignores the mouse, never
/// takes key focus from the front app, and goes on `hide()`. (The sheet to
/// search in is `CheatSearchPanel`.)
@MainActor
final class CheatSheetPanel {
    private let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
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
        panel.contentView = NSHostingView(rootView: CheatSheetView(model: model))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The card: "Hyper", the modifier line, the Hyper layer's keyboard.
struct CheatSheetView: View {
    @ObservedObject var model: AppModel
    static let cardWidth: CGFloat = 820

    var body: some View {
        let theme = model.colors
        let layer = model.layers.first { $0.id == "hyper" } ?? Layer(id: "hyper", title: "Hyper")
        ZStack {
            theme.scrim
            VStack(alignment: .leading, spacing: GroveSpace.s12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hyper")
                        .font(GroveFont.lockup(17))
                        .foregroundStyle(Color(theme.fg))
                    Spacer()
                    Text("⌃⌥⇧⌘ · release Caps Lock to close")
                        .font(GroveFont.mono(GroveType.label))
                        .foregroundStyle(theme.quiet)
                }
                KeyboardGrid(layer: layer, width: Self.cardWidth - 32, capHeight: 46) { _, name, legend, width, height in
                    KeyCapView(legend: legend, binding: layer.bindings[name], isModifier: false, held: false,
                               focused: false, width: width, height: height)
                }
            }
            .padding(GroveSpace.s16)
            .frame(width: Self.cardWidth)
            .sheetCard(theme)
        }
        .font(GroveFont.mono(GroveType.label))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }
}

extension View {
    /// The card of the cheat sheets and the launcher, on the scrim: bg0 a
    /// little see-through, a `border` outline, a shadow.
    func sheetCard(_ theme: ThemeColors) -> some View {
        background(Color(theme.bg0).opacity(0.94), in: RoundedRectangle(cornerRadius: GroveRadius.window))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.window).strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: theme.cardShadow, radius: 30, y: 15)
    }
}
