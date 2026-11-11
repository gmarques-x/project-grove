import AppKit

@MainActor
enum Displays {
    /// The displays connected now, main (the menu bar's) first.
    static func current() -> [String] {
        NSScreen.screens.map(\.localizedName)
    }
}
