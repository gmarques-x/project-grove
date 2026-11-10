import GroveThemesCore
import SwiftUI

// Placeholder so the executable target builds; Task 3 replaces it.
@main
struct GroveThemesApp: App {
    var body: some Scene {
        MenuBarExtra("Grove Themes", systemImage: "leaf") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grove Themes")
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
