import Foundation

/// The `grovekeys://` links Grove Keys answers. The Grove bar opens two:
/// `grove-menu` (the pine: the Grove menu) and `app-menu` (the app name: the
/// front app's menus). AeroSpace opens `palette` and `cheatsheet` for their
/// hotkeys. `menu` alone is no longer opened by the bar (its ⌘ glyph is gone)
/// but still answered, e.g. from a terminal. Anything else is ignored.
public enum KeysURL: Equatable, Sendable {
    /// Grove Keys' own menu at the pointer (the pine's Grove Keys ▸ submenu).
    case menu
    /// `menu/<id>`: one row of the Grove menu, run if it is a leaf, popped up
    /// at the pointer if it is a submenu.
    case row(id: String)
    /// The pine's dropdown: the Grove menu.
    case groveMenu
    /// The front app's menus, directly.
    case appMenu
    /// The Grove menu's rows in a type-to-filter panel.
    case palette
    /// The cheat sheet, shown or put away.
    case cheatSheet

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "grovekeys" else { return nil }
        let host = url.host?.lowercased()
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if host == "menu", parts.count == 1, let id = parts.first, !id.isEmpty {
            self = .row(id: String(id))
            return
        }
        guard url.path.isEmpty || url.path == "/" else { return nil }
        switch host {
        case "menu": self = .menu
        case "grove-menu": self = .groveMenu
        case "app-menu": self = .appMenu
        case "palette": self = .palette
        case "cheatsheet": self = .cheatSheet
        default: return nil
        }
    }
}
