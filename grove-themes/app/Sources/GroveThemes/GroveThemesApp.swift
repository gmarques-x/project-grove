import AppKit
import GroveThemesCore
import SwiftUI

@main
struct GroveThemesApp: App {
    // SwiftUI creates the App once, so plain properties hold the one model and
    // watcher. (`@State` is a macro in this SDK, and the Command Line Tools ship
    // no SwiftUIMacros plugin, so the app avoids it.)
    private let model: ThemesModel
    private let watcher: StateWatcher

    init() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/bin/grove-themes")
        let model = ThemesModel(client: GroveThemesClient(runner: ProcessRunner(path: cli)))
        self.model = model
        watcher = StateWatcher(file: StatePath.url(environment: environment, home: home)) {
            Task { await model.refreshRetryingWhileNotInstalled() }
        }
        // A `.window` MenuBarExtra may keep its view alive, so `.onAppear` alone
        // can miss a reopened dropdown: the dropdown (or the gallery) becoming
        // key, or the app becoming active, re-checks too.
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in await model.refreshRetryingWhileNotInstalled() }
            }
        }
        Task { await model.refreshRetryingWhileNotInstalled() }
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownView()
                .environment(model)
        } label: {
            Image(nsImage: PineShape.menuBarImage(size: 16))
        }
        .menuBarExtraStyle(.window)

        Window("Grove Themes", id: "gallery") {
            GalleryView()
                .environment(model)
        }
        // Seamless, like Ghostty: no title bar or title, the scheme's bg0 up to
        // the top edge, the window buttons over it; sized to fit the cards.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: GalleryView.width, height: GalleryView.height)
    }
}
