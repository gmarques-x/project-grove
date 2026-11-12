import Foundation

/// The `grovekeys://` links Grove Keys answers. The Grove bar opens
/// `grove-menu` (the pine: the Grove menu, which is the panel `panel/grove`)
/// and `app-menu` (the app name: the front app's menus). AeroSpace opens `cheatsheet` for its hotkey; `launcher` is the Grove
/// Launcher (its key, ⌘Space, comes through the key tap, not a link; `palette`
/// is its old name and still answered). `menu` alone is no longer opened by the bar (its ⌘ glyph is gone)
/// but still answered, e.g. from a terminal. The bar's other pills open
/// `panel/<name>` (clock, system, battery, wifi, sound, grove): that
/// dropdown, shown or put away. Anything else is ignored.
public enum KeysURL: Equatable, Sendable {
    /// Grove Keys' own menu at the pointer (the pine's Grove Keys ▸ submenu).
    case menu
    /// `menu/<id>`: one row of the Grove menu, run if it is a leaf; a
    /// submenu opens the Grove menu's panel with that submenu open.
    case row(id: String)
    /// The pine's dropdown, the Grove menu: the same as `panel(name: "grove")`.
    case groveMenu
    /// The front app's menus, directly.
    case appMenu
    /// The Grove Launcher: apps and the Grove menu's rows in a type-to-filter panel.
    case launcher
    /// The cheat sheet, shown or put away.
    case cheatSheet
    /// `panel/<name>`: the bar panel of that name, shown or put away (showing
    /// one puts away any other). Whether a panel has that name is the
    /// registry's to say; here it only has to look like a name.
    case panel(name: String)
    /// `panel/close`: whichever bar panel is open is put away (the bar sends
    /// it on a workspace change).
    case closePanel

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "grovekeys" else { return nil }
        let host = url.host?.lowercased()
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if host == "menu", parts.count == 1, let id = parts.first, !id.isEmpty {
            self = .row(id: String(id))
            return
        }
        if host == "panel", parts.count == 1, let name = parts.first?.lowercased(), Self.isPanelName(name) {
            self = name == "close" ? .closePanel : .panel(name: name)
            return
        }
        guard url.path.isEmpty || url.path == "/" else { return nil }
        switch host {
        case "menu": self = .menu
        case "grove-menu": self = .groveMenu
        case "app-menu": self = .appMenu
        case "launcher", "palette": self = .launcher
        case "cheatsheet": self = .cheatSheet
        default: return nil
        }
    }

    /// A panel's name: lower-case letters, digits and hyphens, 24 at most.
    static func isPanelName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 24
            && name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}
