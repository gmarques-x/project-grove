import Foundation
import Testing
@testable import GroveKeysCore

// Recorded shapes of MenuBarAgent's Accessibility tree on macOS 27 (research
// 2026-11-14, menu-bar tray), with invented titles and pids.
private typealias Item = StatusItems.Node

private let agent: pid_t = 100
private let wireGuard: pid_t = 201
private let oneDrive: pid_t = 202
private let other: pid_t = 203

private func item(_ pid: pid_t, _ title: String? = nil, role: String = "AXButton") -> Item {
    Item(role: role, pid: pid, title: title)
}

private func group(_ children: [Item]) -> Item {
    Item(role: "AXGroup", pid: agent, children: children)
}

/// The reveal shield, then the dialog with one group per item.
private let windows = [
    Item(role: "AXWindow", subrole: "AXUnknown", identifier: StatusItems.revealShield, pid: agent),
    Item(role: "AXWindow", subrole: "AXDialog", pid: agent, children: [
        group([item(wireGuard, "")]),
        group([item(oneDrive, "OneDrive Up to date")]),
        group([item(other, "1")]),
        group([item(oneDrive, "Second item")]),
        group([Item(role: "AXMenuExtra", identifier: "com.apple.menuextra.clock", pid: agent)]),
    ]),
]

struct StatusItemsTests {
    @Test func theItemsOfAnAppInTheBarsOrder() {
        let found = StatusItems.find(owner: oneDrive, in: windows)
        #expect(found.map(\.item) == [[1, 1, 0], [1, 3, 0]])
        // The wrapping group, the second thing to press.
        #expect(found.map(\.wrapper) == [[1, 1], [1, 3]])
        #expect(StatusItems.find(owner: wireGuard, in: windows).map(\.item) == [[1, 0, 0]])
    }

    @Test func nothingForAnAppWithoutAnItem() {
        #expect(StatusItems.find(owner: 999, in: windows).isEmpty)
        #expect(StatusItems.find(owner: oneDrive, in: []).isEmpty)
    }

    @Test func theRevealShieldIsSkipped() {
        let shield = [Item(role: "AXWindow", identifier: StatusItems.revealShield, pid: agent, children: [
            group([item(oneDrive)]),
        ])]
        #expect(StatusItems.find(owner: oneDrive, in: shield).isEmpty)
    }

    @Test func aDeeperGroupIsFound() {
        let nested = [Item(role: "AXWindow", subrole: "AXDialog", pid: agent, children: [
            Item(role: "AXGroup", pid: agent, children: [group([item(wireGuard)])]),
        ])]
        #expect(StatusItems.find(owner: wireGuard, in: nested).map(\.item) == [[0, 0, 0, 0]])
        // Apple's own extras are MenuBarAgent's; its groups aren't items.
        let apple = StatusItems.find(owner: agent, in: windows)
        #expect(apple.map(\.item) == [[1, 4, 0]])
        #expect(apple.map(\.wrapper) == [nil])
    }

    @Test func onlyElementsThatCanBePressed() {
        let odd = [Item(role: "AXWindow", subrole: "AXDialog", pid: agent, children: [
            group([item(oneDrive, role: "AXStaticText"), item(oneDrive, role: "AXMenuBarItem")]),
        ])]
        #expect(StatusItems.find(owner: oneDrive, in: odd).map(\.item) == [[0, 0, 1]])
    }

    @Test func anItemStraightInTheWindowHasNoWrapper() {
        let flat = [Item(role: "AXWindow", subrole: "AXDialog", pid: agent, children: [item(oneDrive)])]
        let found = StatusItems.find(owner: oneDrive, in: flat)
        #expect(found.map(\.item) == [[0, 0]])
        #expect(found.map(\.wrapper) == [nil])
    }

    @Test func theAgent() {
        #expect(StatusItems.agentBundleID == "com.apple.MenuBarAgent")
        #expect(StatusItems.revealShield == "MenuBarRevealShield")
    }
}
