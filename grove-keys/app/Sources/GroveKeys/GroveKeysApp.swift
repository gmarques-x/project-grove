import AppKit
import GroveKeysCore
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
        // grovekeys:// links are answered by AppDelegate; without this SwiftUI
        // also opens this window for every link (and the window closes the menu).
        .handlesExternalEvents(matching: [])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, as LSUIElement in the bundle (also when run bare from .build).
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
        MainActor.assumeIsolated { PointerMenu.shared.start() }
    }

    /// The `grovekeys://` links (see `KeysURL`); anything else is ignored.
    func application(_ application: NSApplication, open urls: [URL]) {
        for link in urls.compactMap(KeysURL.init) {
            MainActor.assumeIsolated { Links.answer(link) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}

/// What each `grovekeys://` link does. The Grove bar's pine and app name
/// send `grove-menu` and `app-menu`, AeroSpace's hotkeys `palette` and
/// `cheatsheet`; an `open` row of the Grove menu naming one of these links is
/// answered here too, without going round through macOS.
@MainActor
enum Links {
    static func answer(_ link: KeysURL) {
        switch link {
        case .menu: PointerMenu.shared.show()
        case .row(let id): PointerMenu.shared.showRow(id: id)
        case .groveMenu: PointerMenu.shared.showGroveMenu()
        case .appMenu: PointerMenu.shared.showAppMenu()
        case .palette: PalettePanel.shared.toggle()
        case .cheatSheet:
            PointerMenu.shared.handBackAfterLink()
            AppModel.shared.toggleCheatSheet()
        }
    }
}
