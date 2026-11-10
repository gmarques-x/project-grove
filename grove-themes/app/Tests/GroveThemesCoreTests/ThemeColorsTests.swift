import Foundation
import Testing
@testable import GroveThemesCore

@Suite struct ThemeColorsTests {
    @Test func mapsEveryPaletteColour() throws {
        let list = try GroveThemesClient.decoder.decode(SchemeList.self, from: Fixture.data("list.json"))
        let palette = try #require(list.palettes["dark-medium"])
        let colors = try #require(ThemeColors(palette: palette))
        #expect(colors.bg0 == RGB(red: 45.0 / 255, green: 53.0 / 255, blue: 59.0 / 255))
        #expect(colors.green == RGB(red: 167.0 / 255, green: 192.0 / 255, blue: 128.0 / 255))
        #expect(colors.purple == RGB(red: 214.0 / 255, green: 153.0 / 255, blue: 182.0 / 255))
        #expect(colors.isDark)
        let light = try #require(list.palettes["light-soft"].flatMap(ThemeColors.init(palette:)))
        #expect(!light.isDark)
    }

    @Test func missingColourIsNil() {
        var hex = [String: String]()
        for key in ["bg0", "bg1", "bg2", "fg", "grey1", "red", "orange", "yellow", "green", "aqua", "blue", "purple"] {
            hex[key] = "#000000"
        }
        #expect(ThemeColors(palette: Palette(name: "X", appearance: "dark", colors: hex)) == nil)
        hex["bg3"] = "nope"
        #expect(ThemeColors(palette: Palette(name: "X", appearance: "dark", colors: hex)) == nil)
        hex["bg3"] = "#000000"
        #expect(ThemeColors(palette: Palette(name: "X", appearance: "dark", colors: hex)) != nil)
    }
}
