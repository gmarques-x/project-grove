import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct InstalledAppsTests {
    func makeApp(_ dir: URL, _ name: String, id: String?) throws {
        let contents = dir.appendingPathComponent(name + ".app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [:]
        if let id { plist["CFBundleIdentifier"] = id }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    @Test func scansOneLevelSortedByName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("Applications"), b = root.appendingPathComponent("user")
        try makeApp(a, "zed", id: "dev.zed.Zed")
        try makeApp(a, "Ghostty", id: "com.mitchellh.ghostty")
        try makeApp(a, "NoID", id: nil)
        try makeApp(a.appendingPathComponent("Utilities"), "Deep", id: "com.example.deep")
        try makeApp(b, "Arc", id: "company.thebrowser.Browser")
        try makeApp(b, "Ghostty", id: "com.mitchellh.ghostty")  // same ID twice: listed once
        let apps = InstalledApps.scan(folders: [a, b, root.appendingPathComponent("missing")])
        #expect(apps.map(\.name) == ["Arc", "Ghostty", "zed"])
        #expect(apps.map(\.bundleID) == ["company.thebrowser.Browser", "com.mitchellh.ghostty", "dev.zed.Zed"])
    }
}
