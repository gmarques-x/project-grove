import AppKit
import GroveKeysCore

/// The menu bar menu, popped up at the pointer: the Grove bar's key glyph
/// opens `grovekeys://menu` (the native menu bar is hidden behind the bar).
@MainActor
final class PointerMenu: NSObject {
    static let shared = PointerMenu()
    private let model = AppModel.shared

    func show() {
        let menu = NSMenu()
        if !model.permissions.accessibility {
            menu.addItem(item("Grove Keys needs Accessibility — Open Settings") {
                NSWorkspace.shared.open(Permissions.accessibilitySettings)
            })
        }
        if !model.permissions.inputMonitoring {
            menu.addItem(item("Grove Keys needs Input Monitoring — Open Settings") {
                NSWorkspace.shared.open(Permissions.inputMonitoringSettings)
            })
        }
        if let line = model.redLine {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        if model.needsAttention { menu.addItem(.separator()) }
        menu.addItem(item("Open Grove Keys") { [model] in
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        })
        menu.addItem(item("Show cheat sheet") { [model] in model.showCheatSheetFromMenu() })
        menu.addItem(item(model.paused ? "Resume Hyper" : "Pause Hyper") { [model] in model.togglePause() })
        menu.addItem(.separator())
        menu.addItem(item("Quit Grove Keys") { [model] in model.quit() })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func item(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction(action)
        item.target = target
        item.representedObject = target   // keeps the target alive with the item
        return item
    }
}

/// An NSMenuItem target that runs a closure.
@MainActor
private final class MenuAction: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func run() { action() }
}
