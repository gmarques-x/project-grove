import Foundation
import Testing
@testable import GroveKeysCore

// Invented apps only (the repo is public).
private func item(_ bundle: String, _ name: String = "App", pid: pid_t = 100, id: String? = nil,
                  title: String? = nil, description: String? = nil, help: String? = nil,
                  x: Double = 0) -> TrayItem {
    TrayItem(bundleID: bundle, appName: name, pid: pid, identifier: id, title: title,
             description: description, help: help, x: x)
}

private let home = URL(fileURLWithPath: "/Users/someone")

struct TrayItemsTests {
    @Test func appleAndAgentItemsAreLeftOut() {
        let items = [
            item("com.apple.controlcenter", x: 1), item(StatusItems.agentBundleID, x: 2),
            item("com.apple.TextInputMenuAgent", x: 3), item("", "sketchybar", x: 4),
            item("com.example.vpn", "Example VPN", x: 5),
        ]
        #expect(TrayItems.shown(items).map(\.bundleID) == ["com.example.vpn"])
    }

    @Test func orderIsLeftToRight() {
        let items = [item("com.example.c", x: 30), item("com.example.a", x: 10), item("com.example.b", x: 20)]
        #expect(TrayItems.shown(items).map(\.x) == [10, 20, 30])
    }

    @Test func twoItemsOfOneAppAreTwoRows() {
        let items = [item("com.example.vpn", x: 5), item("com.example.vpn", x: 9)]
        #expect(TrayItems.shown(items).count == 2)
    }

    @Test func keyUsesAStableIdentifier() {
        let a = item("com.example.vpn", id: "main", title: "Connected", x: 5)
        let b = item("com.example.vpn", id: "second", x: 9)
        #expect(TrayItems.key(a, among: [a, b]) == "com.example.vpn#main")
        #expect(TrayItems.key(b, among: [a, b]) == "com.example.vpn#second")
    }

    @Test func keysFallBackToTheIndexAmongTheAppsItems() {
        let other = item("com.example.other", x: 1)
        let a = item("com.example.vpn", x: 5)
        let b = item("com.example.vpn", id: "", x: 9)
        let all = [b, other, a]
        #expect(TrayItems.key(a, among: all) == "com.example.vpn#0")
        #expect(TrayItems.key(b, among: all) == "com.example.vpn#1")
        #expect(TrayItems.key(other, among: all) == "com.example.other#0")
    }

    @Test func keysStayStableWhenStatusTextChanges() {
        let before = item("com.example.sync", id: "Sync issue", title: "Sync issue", x: 5)
        #expect(TrayItems.key(before, among: [before]) == "com.example.sync#0")
        let after = item("com.example.sync", id: "Up to date", title: "Up to date", x: 5)
        #expect(TrayItems.key(after, among: [after]) == "com.example.sync#0")
        let byDescription = item("com.example.sync", id: "Sync", description: "Sync", x: 5)
        #expect(TrayItems.key(byDescription, among: [byDescription]) == "com.example.sync#0")
    }

    @Test func textSkipsTheAppName() {
        #expect(TrayItems.text(item("com.example.vpn", "Example VPN", title: "Example VPN", description: "Connected")) == "Connected")
        #expect(TrayItems.text(item("com.example.vpn", "Example VPN", title: "Example VPN")) == nil)
        #expect(TrayItems.text(item("com.example.vpn", "Example VPN", title: "", description: "  ")) == nil)
    }

    @Test func textOrderIsTitleDescriptionHelp() {
        #expect(TrayItems.text(item("x", title: "T", description: "D", help: "H")) == "T")
        #expect(TrayItems.text(item("x", title: nil, description: "D", help: "H")) == "D")
        #expect(TrayItems.text(item("x", title: "", description: nil, help: "H")) == "H")
    }

    @Test func hiddenSplitAndDefaults() {
        #expect(TrayItems.defaultHidden == ["com.projectgrove.keys", "com.projectgrove.themes", "bobko.aerospace"])
        let keys = item("com.projectgrove.keys", x: 1)
        let vpn = item("com.example.vpn", x: 2)
        let split = TrayItems.split([keys, vpn], hidden: TrayItems.defaultHidden)
        #expect(split.visible == [vpn])
        #expect(split.hidden == [keys])
        let byKey = TrayItems.split([keys, vpn], hidden: ["com.example.vpn#0"])
        #expect(byKey.visible == [keys])
        #expect(byKey.hidden == [vpn])
    }

    @Test func countIgnoresHidden() {
        let vpn = item("com.example.vpn", x: 2)
        let sync = item("com.example.sync", x: 3)
        let keys = item("com.projectgrove.keys", x: 1)
        let split = TrayItems.split([keys, vpn, sync], hidden: TrayItems.defaultHidden)
        #expect(TrayItems.count(visible: split.visible) == 2)
        #expect(TrayItems.count(visible: []) == 0)
    }
}

struct TrayFilesTests {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString) }

    @Test func pathsAreBesideTheOtherState() {
        #expect(TrayHiddenFile.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/tray-hidden")
        #expect(TrayBarFile.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/tray")
        #expect(TrayBarFile.url(environment: [:], home: home).path == "/Users/someone/.local/state/grove/tray")
        #expect(TrayHiddenFile.url(environment: [:], home: home).path == "/Users/someone/.local/state/grove/tray-hidden")
    }

    @Test func hiddenFileRoundTripsAndMissingIsDefaults() throws {
        let d = dir()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = TrayHiddenFile.url(environment: ["GROVE_STATE": d.path], home: home)
        #expect(TrayHiddenFile.read(url) == TrayItems.defaultHidden)
        try TrayHiddenFile.write(["b#1", "a#0"], to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "a#0\nb#1\n")
        #expect(TrayHiddenFile.read(url) == ["a#0", "b#1"])
        try TrayHiddenFile.write([], to: url)
        #expect(TrayHiddenFile.read(url) == [])
    }

    @Test func barFileWrittenOnlyOnChangeAndRemovedOnNil() throws {
        let d = dir()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = TrayBarFile.url(environment: ["GROVE_STATE": d.path], home: home)
        #expect(try TrayBarFile.update(3, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "3\n")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.02)
        #expect(try !TrayBarFile.update(3, at: url))
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)
        #expect(try TrayBarFile.update(0, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "0\n")
        #expect(try TrayBarFile.update(nil, at: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try !TrayBarFile.update(nil, at: url))
    }
}
