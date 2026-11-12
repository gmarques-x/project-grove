import AppKit
import GroveExplorerCore
import SwiftUI

/// Started from main.swift, after the `--render` check. An ordinary app: one
/// window, in ⌘Tab, nothing in the menu bar; closing the window quits it.
struct ExplorerApp: App {
    // `@State` is a macro and the Command Line Tools ship no SwiftUIMacros
    // plugin: the one model is made here and kept by the delegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Seamless, as the other Grove windows: no title bar, bg0 to the top
        // edge with the window's buttons over it. Resizable: AeroSpace tiles it.
        Window("Grove Explorer", id: "explorer") {
            WindowView(model: delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.standard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        GroveIcons.load()
        // Without the icons the list still works (macOS's icons): say why on stderr.
        if let problem = GroveIcons.problem {
            FileHandle.standardError.write(Data((problem + "\n").utf8))
        }
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
