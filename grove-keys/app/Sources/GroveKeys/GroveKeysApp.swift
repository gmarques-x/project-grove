import AppKit
import SwiftUI

/// Started from main.swift, after the `--render-aerospace` check.
struct GroveKeysApp: App {
    // `@State` is a macro and the Command Line Tools ship no SwiftUIMacros
    // plugin; the one model lives in `AppModel.shared`.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }

        // Seamless, as Grove Themes: no title bar, the scheme's bg0 up to the
        // top edge with the window buttons over it; sized to its content.
        Window("Grove Keys", id: MenuBarView.windowID) {
            WindowView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, as LSUIElement in the bundle (also when run bare from .build).
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
