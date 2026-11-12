import Foundation
import Testing
@testable import GroveThemesCore

@Suite struct ModelsTests {
    let decoder = GroveThemesClient.decoder

    @Test func decodesList() throws {
        let list = try decoder.decode(SchemeList.self, from: Fixture.data("list.json"))
        #expect(list.current == "dark-medium")
        #expect(list.schemes == ["dark-hard", "dark-medium", "dark-soft", "light-hard", "light-medium", "light-soft"])
        #expect(list.palettes.count == 6)
        let palette = try #require(list.palettes["dark-medium"])
        #expect(palette.name == "Dark Medium")
        #expect(palette.appearance == "dark")
        #expect(palette.colors.count == 17)
        #expect(palette.colors["on_accent"] == "#2D353B")
        #expect(palette.colors["bg0"] == "#2D353B")
        #expect(list.palettes["light-soft"]?.appearance == "light")
    }

    @Test func decodesTheLogoFields() throws {
        let json = #"{"current": "dark-medium", "schemes": [], "palettes": {}, "logo": "avatar", "logos": ["grove", "avatar"]}"#
        let list = try decoder.decode(SchemeList.self, from: Data(json.utf8))
        #expect(list.logo == "avatar")
        #expect(list.logos == ["grove", "avatar"])
    }

    @Test func aListWithoutLogoFieldsDefaultsThem() throws {
        let json = #"{"current": "dark-medium", "schemes": [], "palettes": {}}"#
        let list = try decoder.decode(SchemeList.self, from: Data(json.utf8))
        #expect(list.logo == "grove")
        #expect(list.logos == ["grove", "avatar"])
    }

    @Test func decodesTheWallpaperFields() throws {
        let json = #"{"current": "dark-medium", "schemes": [], "palettes": {}, "wallpaper": "avatar", "wallpapers": ["grove", "avatar"]}"#
        let list = try decoder.decode(SchemeList.self, from: Data(json.utf8))
        #expect(list.wallpaper == "avatar")
        #expect(list.wallpapers == ["grove", "avatar"])
        let old = try decoder.decode(SchemeList.self, from: Data(#"{"current": "x", "schemes": [], "palettes": {}}"#.utf8))
        #expect(old.wallpaper == "grove")
        #expect(old.wallpapers == ["grove", "avatar"])
    }

    @Test func decodesSet() throws {
        let result = try decoder.decode(SwitchResult.self, from: Fixture.data("set.json"))
        #expect(result.scheme == "dark-medium")
        #expect(result.steps.count == 12)
        #expect(result.steps.first == Step(name: "configs", result: .live, message: ""))
        #expect(result.steps.first { $0.name == "zsh" }?.result == .nextPrompt)
        #expect(result.steps.first { $0.name == "yazi" }?.result == .nextLaunch)
    }

    @Test func decodesSetThatNeedsYou() throws {
        let result = try decoder.decode(SwitchResult.self, from: Fixture.data("set-needs-you.json"))
        #expect(result.scheme == "light-soft")
        let appearance = try #require(result.steps.first { $0.name == "appearance" })
        #expect(appearance.result == .needsYou)
        #expect(appearance.message.contains("Automation"))
    }

    @Test func decodesLog() throws {
        let client = GroveThemesClient(runner: FakeRunner())
        let entries = try client.decodeLog(Fixture.data("log.json"))
        #expect(entries.map(\.scheme) == ["light-soft", "dark-medium"])
        #expect(entries.map(\.exit) == [1, 0])
        #expect(entries[0].steps.count == 12)
        #expect(entries[0].time >= entries[1].time)
    }

    @Test func logTimeParsesOffset() throws {
        let json = #"{"time": "2026-11-10T13:10:04+00:00", "scheme": "dark-medium", "exit": 0, "steps": []}"#
        let entry = try decoder.decode(LogEntry.self, from: Data(json.utf8))
        #expect(entry.time == Date(timeIntervalSince1970: 1_794_316_204))
        let shifted = #"{"time": "2026-11-10T14:10:04+01:00", "scheme": "dark-medium", "exit": 0, "steps": []}"#
        #expect(try decoder.decode(LogEntry.self, from: Data(shifted.utf8)).time == entry.time)
    }

    @Test func unknownResultFailsDecoding() {
        let json = #"{"name": "ghostty", "result": "sideways", "message": ""}"#
        #expect(throws: DecodingError.self) {
            try decoder.decode(Step.self, from: Data(json.utf8))
        }
    }
}
