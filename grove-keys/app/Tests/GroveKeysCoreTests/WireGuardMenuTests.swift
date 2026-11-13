import Testing
@testable import GroveKeysCore

struct WireGuardMenuTests {
    @Test(arguments: ["Manage Tunnels", "Manage Tunnels…", "Manage Tunnels...", "manage tunnels", "MANAGE TUNNELS…",
                      "  Manage Tunnels  ", "Manage Tunnels …"])
    func manageTunnelsMatches(_ title: String) {
        #expect(WireGuardMenu.isManageTunnels(title))
    }

    @Test(arguments: [nil, "", "Manage Tunnels Later", "Manage", "Tunnels", "Manage Log", "Import Tunnel(s) from File…",
                      "Quit WireGuard", "Manage  Tunnels", "Manage Tunnels……x"])
    func otherItemsDont(_ title: String?) {
        #expect(!WireGuardMenu.isManageTunnels(title))
    }

    @Test func theFirstMatchingItemIsChosen() {
        #expect(WireGuardMenu.manageTunnelsIndex(in: ["grove-lab", nil, "Manage Tunnels…", "Quit"]) == 2)
        #expect(WireGuardMenu.manageTunnelsIndex(in: ["grove-lab", "Quit"]) == nil)
        #expect(WireGuardMenu.manageTunnelsIndex(in: []) == nil)
    }

    @Test func pressedOnlyWhenEveryStepWorked() {
        let all = WireGuardMenu.Steps(trusted: true, running: true, statusItems: 1, menuOpened: true,
                                      itemFound: true, itemPressed: true)
        #expect(all.outcome == .pressed)
        var steps = all
        steps.running = false
        #expect(steps.outcome == .fallback(.menuDidNotOpen))
        steps = all
        steps.statusItems = 0
        #expect(steps.outcome == .fallback(.menuDidNotOpen))
        steps = all
        steps.menuOpened = false
        #expect(steps.outcome == .fallback(.menuDidNotOpen))
        steps = all
        steps.itemFound = false
        #expect(steps.outcome == .fallback(.menuDidNotOpen))
        steps = all
        steps.itemPressed = false
        #expect(steps.outcome == .fallback(.menuDidNotOpen))
    }

    @Test func untrustedIsItsOwnReason() {
        // Whatever else, without Accessibility the panel asks for it.
        var steps = WireGuardMenu.Steps(trusted: false, running: true, statusItems: 1, menuOpened: true,
                                        itemFound: true, itemPressed: true)
        #expect(steps.outcome == .fallback(.notTrusted))
        steps = WireGuardMenu.Steps()
        #expect(steps.outcome == .fallback(.notTrusted))
    }

    @Test func aPressTookWhenItsMenuWentOrAWindowCame() {
        // AXPress in a tracking menu can say it failed although it worked:
        // what WireGuard shows afterwards decides.
        #expect(WireGuardMenu.pressTook(menuGone: true, windowsBefore: 0, windowsAfter: 0))
        #expect(WireGuardMenu.pressTook(menuGone: false, windowsBefore: 0, windowsAfter: 1))
        #expect(!WireGuardMenu.pressTook(menuGone: false, windowsBefore: 0, windowsAfter: 0))
        // A tunnels window already open isn't a sign by itself.
        #expect(!WireGuardMenu.pressTook(menuGone: false, windowsBefore: 1, windowsAfter: 1))
    }

    @Test func theLines() {
        #expect(WireGuardMenu.title == "Manage Tunnels…")
        #expect(WireGuardMenu.Reason.notTrusted.line == "Grove Keys needs Accessibility permission")
        #expect(WireGuardMenu.Reason.menuDidNotOpen.line == "WireGuard's menu didn't open")
        #expect(WireGuardMenu.Reason.notTrusted.offersPrivacySettings)
        #expect(!WireGuardMenu.Reason.menuDidNotOpen.offersPrivacySettings)
        #expect(WireGuardMenu.privacyURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @Test func theHintStaysUntilItHasBeenSeen() {
        // Set with the panel open: the fallback brings WireGuard forward,
        // which closes the panel; the next opening still shows it.
        var hint = WireGuardMenu.Hint()
        hint.set(.menuDidNotOpen)
        #expect(hint.reason == .menuDidNotOpen)
        hint.opened()
        #expect(hint.reason == .menuDidNotOpen)
        // The opening after the one that showed it clears it.
        hint.opened()
        #expect(hint.reason == nil)
        // A new click clears it at once.
        hint.set(.notTrusted)
        hint.clear()
        #expect(hint.reason == nil)
        hint.opened()
        #expect(hint.reason == nil)
    }
}
