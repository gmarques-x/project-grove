import AppKit
import GroveThemesCore
import SwiftUI

/// The key glyph: orange while a permission is missing or a red line is up.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.glyph(tint: model.needsAttention ? NSColor(model.colors.orange) : nil))
            .onAppear {
                model.openMainWindow = { openWindow(id: MenuBarView.windowID) }
            }
    }

    static func glyph(tint: NSColor?) -> NSImage {
        let base = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Grove Keys") ?? NSImage()
        guard let tint else {
            base.isTemplate = true
            return base
        }
        let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint])) ?? base
        image.isTemplate = false
        return image
    }
}

/// Spec §7: permission lines, the red line, then the four items.
struct MenuBarView: View {
    static let windowID = "main"

    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !model.permissions.accessibility {
            Text("Grove Keys needs Accessibility")
            Button("Open Settings") { NSWorkspace.shared.open(Permissions.accessibilitySettings) }
        }
        if !model.permissions.inputMonitoring {
            Text("Grove Keys needs Input Monitoring")
            Button("Open Settings") { NSWorkspace.shared.open(Permissions.inputMonitoringSettings) }
        }
        if let line = model.redLine {
            Text(line)
        }
        if model.needsAttention {
            Divider()
        }
        Button("Open Grove Keys") {
            openWindow(id: Self.windowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Show cheat sheet") { model.showCheatSheetFromMenu() }
        Button(model.paused ? "Resume Hyper" : "Pause Hyper") { model.togglePause() }
        Divider()
        Button("Quit Grove Keys") { model.quit() }
            .keyboardShortcut("q")
    }
}
