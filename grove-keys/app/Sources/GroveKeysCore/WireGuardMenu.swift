import Foundation

// The VPN dropdown's "Manage Tunnels…" (spec 2026-11-13-bar-vpn-design).
// WireGuard for macOS (com.wireguard.macos) is a menu-bar app: no Dock icon,
// no window of its own when opened again, no URL scheme, no AppleScript.
// Its tunnels window is reached from its status item's menu, "Manage
// Tunnels", so Grove Keys presses that item through Accessibility; what is
// pure about it is here.

public enum WireGuardMenu {
    /// The footer's and the not-set-up button's words.
    public static let title = "Manage Tunnels…"
    /// Said in yellow when the item couldn't be pressed (WireGuard is
    /// launched or brought forward anyway).
    public static let fallbackLine = "Use WireGuard's icon in the menu bar"

    /// WireGuard's menu item: "Manage Tunnels", any case, with or without a
    /// trailing ellipsis ("…" or "...") and surrounding spaces. Nothing else.
    public static func isManageTunnels(_ title: String?) -> Bool {
        guard var text = title?.trimmingCharacters(in: .whitespaces) else { return false }
        if text.hasSuffix("…") {
            text.removeLast()
        } else if text.hasSuffix("...") {
            text.removeLast(3)
        }
        return text.trimmingCharacters(in: .whitespaces).lowercased() == "manage tunnels"
    }

    /// The first "Manage Tunnels" among a menu's item titles.
    public static func manageTunnelsIndex(in titles: [String?]) -> Int? {
        titles.firstIndex(where: isManageTunnels)
    }

    public enum Outcome: Equatable, Sendable {
        /// The item was pressed: WireGuard's tunnels window comes forward.
        case pressed
        /// Anything failed: WireGuard is launched or activated, and the
        /// dropdown says `fallbackLine`.
        case fallback
    }

    /// How far the press got. Every step defaults to failed.
    public struct Steps: Equatable, Sendable {
        /// Grove Keys may use Accessibility.
        public var trusted = false
        /// WireGuard was running (after a launch and a short wait).
        public var running = false
        /// Items in WireGuard's status bar (`kAXExtrasMenuBarAttribute`).
        public var statusItems = 0
        /// One of them opened a menu.
        public var menuOpened = false
        /// That menu has "Manage Tunnels".
        public var itemFound = false
        /// Pressing it was accepted.
        public var itemPressed = false

        public init(trusted: Bool = false, running: Bool = false, statusItems: Int = 0, menuOpened: Bool = false,
                    itemFound: Bool = false, itemPressed: Bool = false) {
            self.trusted = trusted
            self.running = running
            self.statusItems = statusItems
            self.menuOpened = menuOpened
            self.itemFound = itemFound
            self.itemPressed = itemPressed
        }

        public var outcome: Outcome {
            trusted && running && statusItems > 0 && menuOpened && itemFound && itemPressed ? .pressed : .fallback
        }
    }
}
