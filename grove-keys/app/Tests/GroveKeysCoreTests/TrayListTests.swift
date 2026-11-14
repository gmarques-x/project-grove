import Foundation
import Testing
@testable import GroveKeysCore

// Invented apps only (the repo is public).
private func item(_ bundle: String, _ name: String = "App", pid: pid_t = 100, id: String? = nil,
                  title: String? = nil, description: String? = nil, help: String? = nil,
                  x: Double? = 0) -> TrayItem {
    TrayItem(bundleID: bundle, appName: name, pid: pid, identifier: id, title: title,
             description: description, help: help, x: x)
}

struct TrayRowTextTests {
    @Test func theAppsNameOnItsOwnLineGoes() {
        // A sync app's title arrives as its name, a newline and the status.
        let sync = item("com.example.sync", "Example Sync", title: "Example Sync\nSync issue")
        #expect(TrayItems.rowText(sync) == "Sync issue")
    }

    @Test func theAppsNameAsAPrefixGoesWhateverTheCaseAndSeparator() {
        #expect(TrayItems.rowText(item("x", "Example Sync", title: "example sync: Up to date")) == "Up to date")
        #expect(TrayItems.rowText(item("x", "Example Sync", title: "Example Sync - Paused")) == "Paused")
        #expect(TrayItems.rowText(item("x", "Example Sync", title: "Example Sync — Paused")) == "Paused")
    }

    @Test func aNameThatOnlyStartsTheSameWordStays() {
        // "Example Syncing" isn't the app's name followed by anything.
        #expect(TrayItems.rowText(item("x", "Example Sync", title: "Example Syncing now")) == "Example Syncing now")
        // Nor is a sentence that starts with it.
        #expect(TrayItems.rowText(item("x", "Containers", title: "Containers is running")) == "Containers is running")
        #expect(TrayItems.rowText(item("x", "Containers", title: "Containers  \n  is running")) == "is running")
    }

    @Test func whitespaceRunsBecomeOneSpace() {
        #expect(TrayItems.rowText(item("x", "VPN", title: "  Connected\n\nto\tthe   lab ")) == "Connected to the lab")
    }

    @Test func onlyTheNameMeansNoText() {
        #expect(TrayItems.rowText(item("x", "Example Sync", title: "Example Sync\n")) == nil)
        #expect(TrayItems.rowText(item("x", "Example Sync", title: "Example Sync: ")) == nil)
        #expect(TrayItems.rowText(item("x", "Example Sync", title: " ", description: "\n")) == nil)
    }

    @Test func theNextAttributeIsUsedWhenOneIsOnlyTheName() {
        let sync = item("x", "Example Sync", title: "Example Sync\n", description: "Up to date", help: "Help")
        #expect(TrayItems.rowText(sync) == "Up to date")
        #expect(TrayItems.rowText(item("x", "A", title: nil, description: nil, help: "Help me")) == "Help me")
    }

    @Test func longTextIsCutWithAnEllipsis() {
        let long = String(repeating: "a", count: 50)
        let text = TrayItems.rowText(item("x", "App", title: long))
        #expect(text == String(repeating: "a", count: TrayItems.rowTextLimit - 1) + "…")
        #expect(text?.count == TrayItems.rowTextLimit)
        let exact = String(repeating: "b", count: TrayItems.rowTextLimit)
        #expect(TrayItems.rowText(item("x", "App", title: exact)) == exact)
    }

    @Test func aCutNeverEndsInASpace() {
        let words = String(repeating: "ab ", count: 20)
        let text = TrayItems.rowText(item("x", "App", title: words))
        #expect(text?.hasSuffix("…") == true)
        #expect(text?.dropLast().last != " ")
    }
}

struct TrayListTests {
    @Test func rowsSplitVisibleAndHiddenKeyedByItemKey() {
        let vpn = item("com.example.vpn", "Example VPN", title: "Example VPN", x: 1)
        let sync = item("com.example.sync", "Example Sync", title: "Example Sync\nSync issue", x: 2)
        let mine = item("com.projectgrove.keys", "Grove Keys", x: 3)
        let list = TrayList(items: [vpn, sync, mine], hidden: TrayItems.defaultHidden)
        #expect(list.visible.map(\.id) == ["com.example.vpn#0", "com.example.sync#0"])
        #expect(list.visible.map(\.text) == [nil, "Sync issue"])
        #expect(list.hidden.map(\.id) == ["com.projectgrove.keys#0"])
        #expect(list.hidden.allSatisfy { $0.hidden })
        #expect(!list.visible.contains { $0.hidden })
        #expect(list.row("com.example.sync#0")?.item == sync)
        #expect(list.row("nothing") == nil)
        #expect(list.visible.map(\.index) == [0, 1])
        #expect(list.hidden.map(\.index) == [2])
    }

    @Test func idsStayUniqueWhenKeysCollide() {
        // Untitled, unplaced twins of one app share a key (a theoretical case).
        let a = item("com.example.a", x: nil), b = item("com.example.a", x: nil)
        let list = TrayList(items: [a, b], hidden: [])
        #expect(Set(list.visible.map(\.id)).count == 2)
        #expect(list.visible.first?.id == "com.example.a#0")
    }

    @Test func entriesAreTheVisibleRowsThenTheDisclosureThenHiddenWhenOpen() {
        let a = item("com.example.a", x: 1), h = item("com.projectgrove.keys", x: 2)
        let list = TrayList(items: [a, h], hidden: TrayItems.defaultHidden)
        #expect(list.entries(expanded: false) == [.row("com.example.a#0"), .disclosure])
        #expect(list.entries(expanded: true) == [.row("com.example.a#0"), .disclosure, .row("com.projectgrove.keys#0")])
        let none = TrayList(items: [a], hidden: [])
        #expect(none.entries(expanded: true) == [.row("com.example.a#0")])
    }

    @Test func keysMoveWrapAndJumpByName() {
        let list = TrayList(items: [item("com.example.a", "Alpha", x: 1), item("com.example.b", "Beta", x: 2),
                                    item("com.example.c", "Avocado", x: 3), item("com.projectgrove.keys", "Grove Keys", x: 4)],
                            hidden: TrayItems.defaultHidden)
        let entries = list.entries(expanded: false)
        #expect(list.moved(from: nil, by: 1, expanded: false) == entries[0])
        #expect(list.moved(from: nil, by: -1, expanded: false) == .disclosure)
        #expect(list.moved(from: .disclosure, by: 1, expanded: false) == entries[0])
        #expect(list.jumped(to: "a", from: nil, expanded: false) == .row("com.example.a#0"))
        #expect(list.jumped(to: "a", from: .row("com.example.a#0"), expanded: false) == .row("com.example.c#0"))
        // The disclosure isn't a name; hidden rows only when open.
        #expect(list.jumped(to: "h", from: nil, expanded: false) == nil)
        #expect(list.jumped(to: "g", from: nil, expanded: false) == nil)
        #expect(list.jumped(to: "g", from: nil, expanded: true) == .row("com.projectgrove.keys#0"))
    }

    @Test func aLitRowThatWentAwayIsForgotten() {
        let list = TrayList(items: [item("com.example.a", x: 1)], hidden: [])
        #expect(list.kept(.row("com.example.a#0"), expanded: false) == .row("com.example.a#0"))
        #expect(list.kept(.row("com.example.gone#0"), expanded: false) == nil)
        #expect(list.kept(.disclosure, expanded: false) == nil)
        #expect(list.kept(nil, expanded: false) == nil)
    }

    @Test func theRowMenu() {
        #expect(TrayList.menu(app: "Example VPN", hidden: false) == [.open, .hide, .bringForward])
        #expect(TrayList.menu(app: "Example VPN", hidden: true) == [.open, .show, .bringForward])
        #expect(TrayList.Choice.open.title(app: "X") == "Open")
        #expect(TrayList.Choice.hide.title(app: "X") == "Hide from tray")
        #expect(TrayList.Choice.show.title(app: "X") == "Show in tray")
        #expect(TrayList.Choice.bringForward.title(app: "Example VPN") == "Bring Example VPN forward")
        #expect(TrayList.Choice.bringForward.separated)
        #expect(!TrayList.Choice.hide.separated)
        #expect(TrayList.Choice(rawValue: TrayList.Choice.show.rawValue) == .show)
    }

    @Test func theDisclosureTitle() {
        #expect(TrayList.hiddenTitle(3) == "Hidden (3)")
    }

    @Test func hideAndShowFromTheListUseItsOwnSnapshot() {
        let a = item("com.projectgrove.keys", x: 1), b = item("com.projectgrove.keys", x: 2)
        let list = TrayList(items: [a, b], hidden: TrayItems.defaultHidden)
        let shown = list.toggled(list.hidden[0].id)
        #expect(shown == ["com.projectgrove.themes", "bobko.aerospace", "com.projectgrove.keys#1"])
        let again = TrayList(items: [a, b], hidden: shown!)
        #expect(again.visible.map(\.id) == ["com.projectgrove.keys#0"])
        let hidden = again.toggled("com.projectgrove.keys#0")
        #expect(hidden == ["com.projectgrove.themes", "bobko.aerospace", "com.projectgrove.keys#1", "com.projectgrove.keys#0"])
        #expect(again.toggled("nothing") == nil)
    }
}
