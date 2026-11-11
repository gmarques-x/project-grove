import AppKit
import GroveThemesCore
import SwiftUI

/// Opens the gallery from outside SwiftUI (the Grove bar's Themes… item opens
/// grovethemes://gallery). SwiftUI's openWindow comes from the menu bar
/// label, which is always alive; a link that arrives before it (Grove Themes
/// just launched for it) opens the gallery once it does.
@MainActor
final class GalleryOpener {
    static let shared = GalleryOpener()
    private var openWindow: OpenWindowAction?
    private var pending = false

    func attach(_ action: OpenWindowAction) {
        openWindow = action
        if pending {
            pending = false
            open()
        }
    }

    func open() {
        guard let openWindow else {
            pending = true
            return
        }
        openWindow(id: "gallery")
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class ThemesAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where ThemesURL(url) == .gallery {
            MainActor.assumeIsolated { GalleryOpener.shared.open() }
        }
    }
}

/// The menu bar pine, which also hands its openWindow to the GalleryOpener.
struct MenuBarPine: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: PineShape.menuBarImage(size: 16))
            .onAppear { GalleryOpener.shared.attach(openWindow) }
    }
}
