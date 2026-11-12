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
        // A groveexplorer:// link goes to the delegate, not to a new window.
        .handlesExternalEvents(matching: [])
        .commands { MenuBar(model: delegate.model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.standard()
    private var commandW: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GroveIcons.load()
        // Without the icons the list still works (macOS's icons): say why on stderr.
        if let problem = GroveIcons.problem {
            FileHandle.standardError.write(Data((problem + "\n").utf8))
        }
        model.start()
        keepCommandWForTabs()
    }

    /// ⌘W closes a tab and never the window: on a pane's last tab it does
    /// nothing. The system's own Close item has the same key and can't be
    /// taken out of a SwiftUI menu, so the key is caught here, before any
    /// menu sees it. The red button and ⌘Q close and quit as ever.
    private func keepCommandWForTabs() {
        commandW = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only in the Explorer window itself: in the About panel, a
            // sheet (whose keys come with the sheet's own window), an alert
            // or the Quick Look panel the key is theirs. Under the conflict
            // prompt, a card in the window, the command is not enabled.
            guard let window = event.window, window.canBecomeMain, window.attachedSheet == nil,
                window.sheetParent == nil,
                let stroke = CommandTable.stroke(of: event), stroke.key == "W", stroke.modifiers == [.command],
                let self, let command = CommandTable.command("closeTab")
            else { return event }
            if command.isEnabled(self.model) { command.run(self.model) }
            return nil
        }
    }

    /// `groveexplorer://open?path=…` (spec §9): the folder in a new tab of
    /// the active pane, and the window brought forward.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model.open(link: url) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    /// The session is saved a second after each change; this is the last one.
    func applicationWillTerminate(_ notification: Notification) {
        if let commandW { NSEvent.removeMonitor(commandW) }
        commandW = nil
        model.saveSession()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
