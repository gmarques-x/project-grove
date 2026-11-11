import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct WifiNameTests {
    @Test func pathIsNextToKeysJSON() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(WifiName.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/wifi-name")
        #expect(WifiName.url(environment: ["GROVE_STATE": ""], home: home).path
            == "/Users/someone/.local/state/grove/wifi-name")
        #expect(WifiName.url(environment: [:], home: home).path
            == "/Users/someone/.local/state/grove/wifi-name")
    }

    @Test func plainNamesPassThrough() {
        #expect(WifiName.sanitize("Casa") == "Casa")
        #expect(WifiName.sanitize("Café do Zé 5G") == "Café do Zé 5G")
        #expect(WifiName.sanitize("🌲 grove") == "🌲 grove")
        // Shell and sketchybar punctuation is text: the bar passes it as one argument.
        #expect(WifiName.sanitize("a\"; $(rm -rf ~) `x` label=y") == "a\"; $(rm -rf ~) `x` label=y")
    }

    @Test func dropsLineBreaksAndControlCharacters() {
        #expect(WifiName.sanitize("one\ntwo") == "onetwo")
        #expect(WifiName.sanitize("one\r\ntwo\u{0}\u{7}\u{1B}[31m\u{7F}") == "onetwo[31m")
        #expect(WifiName.sanitize("tab\there") == "tabhere")
        #expect(WifiName.sanitize("a\u{2028}b\u{2029}c\u{85}d") == "abcd")
        // Invisible formatting: right-to-left override, zero-width space, BOM.
        #expect(WifiName.sanitize("a\u{202E}b\u{200B}c\u{FEFF}") == "abc")
    }

    @Test func trimsAndCapsAtThirtyTwoCharacters() {
        #expect(WifiName.sanitize("  Casa \u{A0}") == "Casa")
        #expect(WifiName.sanitize(String(repeating: "x", count: 40)) == String(repeating: "x", count: 32))
        #expect(WifiName.sanitize(String(repeating: "x", count: 32)) == String(repeating: "x", count: 32))
        // The cut never leaves a space at the end.
        #expect(WifiName.sanitize(String(repeating: "x", count: 31) + " yz") == String(repeating: "x", count: 31))
    }

    @Test func nothingLeftIsNoName() {
        #expect(WifiName.sanitize(nil) == nil)
        #expect(WifiName.sanitize("") == nil)
        #expect(WifiName.sanitize(" \n\t ") == nil)
        #expect(WifiName.sanitize("\u{0}\u{1}") == nil)
    }

    @Test func contentsNeedPermissionAndANetwork() {
        #expect(WifiName.contents(authorized: true, ssid: "Casa\n") == "Casa")
        #expect(WifiName.contents(authorized: true, ssid: nil) == nil)
        #expect(WifiName.contents(authorized: true, ssid: "") == nil)
        #expect(WifiName.contents(authorized: false, ssid: "Casa") == nil)
        #expect(WifiName.contents(authorized: false, ssid: nil) == nil)
    }

    @Test func writesOneLineAndRemoves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = WifiName.url(environment: ["GROVE_STATE": dir.path], home: URL(fileURLWithPath: "/nowhere"))

        // No file and no folder yet: removing is not an error.
        try WifiName.write(nil, to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        try WifiName.write("Casa", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Casa\n")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)

        try WifiName.write("Outra", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Outra\n")

        try WifiName.write(nil, to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try WifiName.write(nil, to: url)
    }
}
