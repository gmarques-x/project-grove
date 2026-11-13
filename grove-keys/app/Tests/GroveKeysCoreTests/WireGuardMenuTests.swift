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
        steps.trusted = false
        #expect(steps.outcome == .fallback)
        steps = all
        steps.running = false
        #expect(steps.outcome == .fallback)
        steps = all
        steps.statusItems = 0
        #expect(steps.outcome == .fallback)
        steps = all
        steps.menuOpened = false
        #expect(steps.outcome == .fallback)
        steps = all
        steps.itemFound = false
        #expect(steps.outcome == .fallback)
        steps = all
        steps.itemPressed = false
        #expect(steps.outcome == .fallback)
        #expect(WireGuardMenu.Steps().outcome == .fallback)
    }

    @Test func theLines() {
        #expect(WireGuardMenu.title == "Manage Tunnels…")
        #expect(WireGuardMenu.fallbackLine == "Use WireGuard's icon in the menu bar")
    }
}
