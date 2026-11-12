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

    @Test func rolesAreEachSchemesOwnPick() throws {
        let list = try GroveThemesClient.decoder.decode(SchemeList.self, from: Fixture.data("list.json"))
        // Dark: the colours the apps always drew with.
        for scheme in ["dark-hard", "dark-medium", "dark-soft"] {
            let dark = try #require(list.palettes[scheme].flatMap(ThemeColors.init(palette:)))
            #expect(dark.border == dark.bg3)
            #expect(dark.onAccent == dark.bg0)
            #expect(dark.dim == dark.grey1)
            #expect(!dark.isLight)
        }
        // Light: bg5, the dark sibling's bg0 as ink, grey2.
        let light = try #require(list.palettes["light-medium"].flatMap(ThemeColors.init(palette:)))
        #expect(light.border == RGB(hex: "#BDC3AF"))
        #expect(light.onAccent == RGB(hex: "#2D353B"))
        #expect(light.dim == RGB(hex: "#829181"))
        #expect(light.isLight)
    }

    /// The thirteen colours a CLI older than the roles sends.
    private func oldPalette(_ appearance: String) -> Palette {
        Palette(name: "X", appearance: appearance, colors: [
            "bg0": "#000000", "bg1": "#111111", "bg2": "#222222", "bg3": "#333333",
            "fg": "#EEEEEE", "grey1": "#888888", "red": "#FF0000", "orange": "#FF8800",
            "yellow": "#FFFF00", "green": "#00FF00", "aqua": "#00FFFF", "blue": "#0000FF",
            "purple": "#FF00FF",
        ])
    }

    @Test func anOlderCLIsPaletteFallsBackToTheOldColours() throws {
        let old = try #require(ThemeColors(palette: oldPalette("light")))
        #expect(old.border == old.bg3)
        #expect(old.onAccent == old.bg0)
        #expect(old.dim == old.grey1)
    }

    @Test func anUnreadableRoleFallsBackToo() throws {
        // A theme file without the role renders as "": not a colour.
        var hex = oldPalette("dark").colors
        hex["border"] = ""
        hex["on_accent"] = "nope"
        hex["dim"] = "#ABCDEF"
        let colors = try #require(ThemeColors(palette: Palette(name: "X", appearance: "dark", colors: hex)))
        #expect(colors.border == colors.bg3)
        #expect(colors.onAccent == colors.bg0)
        #expect(colors.dim == RGB(hex: "#ABCDEF"))
    }

    /// The wordmark's ink the views drew before the role: these two literals,
    /// by appearance. Every scheme's `lockup_ink` is the same colour, and so
    /// is what an older CLI's palette (or an unreadable role) falls back to.
    @Test func theWordmarksInkIsWhatTheViewsAlwaysDrew() throws {
        let paper = RGB(red: 0xDA / 255, green: 0xC7 / 255, blue: 0xA2 / 255)
        let ink = RGB(red: 0x27 / 255, green: 0x33 / 255, blue: 0x2A / 255)
        let list = try GroveThemesClient.decoder.decode(SchemeList.self, from: Fixture.data("list.json"))
        #expect(list.palettes.count == 6)
        for (scheme, palette) in list.palettes {
            let colors = try #require(ThemeColors(palette: palette))
            #expect(palette.colors["lockup_ink"] == (colors.isDark ? "#DAC7A2" : "#27332A"), "\(scheme)")
            #expect(colors.lockupInk == (colors.isDark ? paper : ink), "\(scheme)")
        }
        #expect(try #require(ThemeColors(palette: oldPalette("dark"))).lockupInk == paper)
        #expect(try #require(ThemeColors(palette: oldPalette("light"))).lockupInk == ink)
        var hex = oldPalette("light").colors
        hex["lockup_ink"] = ""
        #expect(try #require(ThemeColors(palette: Palette(name: "X", appearance: "light", colors: hex))).lockupInk == ink)
        hex["lockup_ink"] = "#ABCDEF"
        #expect(try #require(ThemeColors(palette: Palette(name: "X", appearance: "light", colors: hex))).lockupInk
                == RGB(hex: "#ABCDEF"))
    }

    /// `hover` is bg1 on the dark schemes and bg3 on the light, sent or not.
    @Test func hoverIsOneStepUpAndStandsInForAnOlderCLI() throws {
        let list = try GroveThemesClient.decoder.decode(SchemeList.self, from: Fixture.data("list.json"))
        for (scheme, palette) in list.palettes {
            let colors = try #require(ThemeColors(palette: palette))
            #expect(palette.colors["hover"] != nil, "\(scheme)")
            #expect(colors.hover == (colors.isDark ? colors.bg1 : colors.bg3), "\(scheme)")
        }
        let dark = try #require(ThemeColors(palette: oldPalette("dark")))
        let light = try #require(ThemeColors(palette: oldPalette("light")))
        #expect(dark.hover == dark.bg1)
        #expect(light.hover == light.bg3)
        var hex = oldPalette("light").colors
        hex["hover"] = "#ABCDEF"
        #expect(try #require(ThemeColors(palette: Palette(name: "X", appearance: "light", colors: hex))).hover
                == RGB(hex: "#ABCDEF"))
    }

    @Test func darkKeepsItsTuningAndLightDropsIt() throws {
        let dark = try #require(ThemeColors(palette: oldPalette("dark")))
        let light = try #require(ThemeColors(palette: oldPalette("light")))
        #expect(dark.quietOpacity(dark: 0.75) == 0.75)
        #expect(light.quietOpacity(dark: 0.75) == 1)
        #expect(dark.accentInk(dark.green) == dark.green)
        #expect(light.accentInk(light.green) == light.fg)
    }
}
