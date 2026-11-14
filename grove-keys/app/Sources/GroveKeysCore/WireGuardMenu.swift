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
    /// System Settings ▸ Privacy & Security ▸ Accessibility.
    public static let privacyURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

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

    /// Why the menu couldn't be pressed, said in yellow in the dropdown
    /// (WireGuard is brought forward anyway).
    public enum Reason: Equatable, Sendable {
        /// Grove Keys may not use Accessibility: with a Privacy Settings…
        /// button, as the Bluetooth section's refusal.
        case notTrusted
        /// Anything else: not running after the launch, no status item, no
        /// menu, no "Manage Tunnels", or the press didn't take.
        case menuDidNotOpen

        public var line: String {
            switch self {
            case .notTrusted: return "Grove Keys needs Accessibility permission"
            case .menuDidNotOpen: return "WireGuard's menu didn't open"
            }
        }

        public var offersPrivacySettings: Bool { self == .notTrusted }
    }

    public enum Outcome: Equatable, Sendable {
        /// The item was pressed: WireGuard's tunnels window comes forward.
        case pressed
        /// Something failed: WireGuard is launched or activated, and the
        /// dropdown says the reason's line.
        case fallback(Reason)
    }

    /// The menu item's press took: its menu went away, or WireGuard has more
    /// windows than before. (AXPress in a tracking menu can answer
    /// kAXErrorCannotComplete although it worked, so its answer isn't used.)
    public static func pressTook(menuGone: Bool, windowsBefore: Int, windowsAfter: Int) -> Bool {
        menuGone || windowsAfter > windowsBefore
    }

    /// The dropdown's line after a fallback: the next opening shows it,
    /// the one after clears it, and so does a new click on Manage Tunnels….
    public typealias Hint = FallbackHint<Reason>

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
        /// Its press took (`pressTook`).
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
            guard trusted else { return .fallback(.notTrusted) }
            return running && statusItems > 0 && menuOpened && itemFound && itemPressed
                ? .pressed : .fallback(.menuDidNotOpen)
        }
    }
}
