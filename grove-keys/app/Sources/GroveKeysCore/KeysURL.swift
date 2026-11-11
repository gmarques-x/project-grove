import Foundation

/// The `grovekeys://` links Grove Keys answers. The Grove bar's key glyph
/// opens `grovekeys://menu`; anything else is ignored.
public enum KeysURL: Equatable, Sendable {
    /// Show the menu bar menu at the pointer.
    case menu

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "grovekeys",
              url.host?.lowercased() == "menu",
              url.path.isEmpty || url.path == "/"
        else { return nil }
        self = .menu
    }
}
