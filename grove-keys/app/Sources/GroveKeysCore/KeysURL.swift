import Foundation

/// The `grovekeys://` links Grove Keys answers, from the Grove bar: `menu`
/// (the ⌘ glyph), `grove-menu` (the pine: Grove Themes, Grove Keys and Global Menu) and
/// `app-menu` (the app name: the front app's menus). Anything else is ignored.
public enum KeysURL: Equatable, Sendable {
    /// Grove Keys' own menu at the pointer.
    case menu
    /// The pine's dropdown: Grove Themes, Grove Keys and Global Menu ▸.
    case groveMenu
    /// The front app's menus, directly.
    case appMenu

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "grovekeys", url.path.isEmpty || url.path == "/" else { return nil }
        switch url.host?.lowercased() {
        case "menu": self = .menu
        case "grove-menu": self = .groveMenu
        case "app-menu": self = .appMenu
        default: return nil
        }
    }
}
