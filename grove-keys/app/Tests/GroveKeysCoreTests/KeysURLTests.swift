import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct KeysURLTests {
    @Test func menuIsRecognised() throws {
        #expect(KeysURL(try #require(URL(string: "grovekeys://menu"))) == .menu)
        #expect(KeysURL(try #require(URL(string: "GroveKeys://menu"))) == .menu)
    }

    @Test func theGroveAndAppMenusAreRecognised() throws {
        #expect(KeysURL(try #require(URL(string: "grovekeys://grove-menu"))) == .groveMenu)
        #expect(KeysURL(try #require(URL(string: "grovekeys://app-menu"))) == .appMenu)
        #expect(KeysURL(try #require(URL(string: "grovekeys://APP-MENU"))) == .appMenu)
        #expect(KeysURL(try #require(URL(string: "grovekeys://grove-menu/x"))) == nil)
    }

    @Test func aRowOfTheGroveMenuIsNamedByItsId() throws {
        #expect(KeysURL(try #require(URL(string: "grovekeys://menu/learn"))) == .row(id: "learn"))
        #expect(KeysURL(try #require(URL(string: "grovekeys://menu/appearance.dark-hard"))) == .row(id: "appearance.dark-hard"))
        #expect(KeysURL(try #require(URL(string: "grovekeys://MENU/global-menu"))) == .row(id: "global-menu"))
        // No id: Grove Keys' own menu, as before.
        #expect(KeysURL(try #require(URL(string: "grovekeys://menu/"))) == .menu)
    }

    @Test func theLauncherAndTheCheatSheetAreRecognised() throws {
        #expect(KeysURL(try #require(URL(string: "grovekeys://launcher"))) == .launcher)
        // Its name until 2026-11-11, still answered.
        #expect(KeysURL(try #require(URL(string: "grovekeys://palette"))) == .launcher)
        #expect(KeysURL(try #require(URL(string: "grovekeys://cheatsheet"))) == .cheatSheet)
        #expect(KeysURL(try #require(URL(string: "grovekeys://CheatSheet/"))) == .cheatSheet)
    }

    @Test func aBarPanelIsNamedInThePath() throws {
        for name in ["clock", "system", "battery", "wifi", "sound", "vpn", "grove"] {
            #expect(KeysURL(try #require(URL(string: "grovekeys://panel/\(name)"))) == .panel(name: name))
        }
        #expect(KeysURL(try #require(URL(string: "grovekeys://PANEL/Clock"))) == .panel(name: "clock"))
        #expect(KeysURL(try #require(URL(string: "grovekeys://panel/close"))) == .closePanel)
        // No name, a second part, or something that isn't a name: ignored.
        for text in ["grovekeys://panel", "grovekeys://panel/", "grovekeys://panel/clock/x", "grovekeys://panel/a%20b",
                     "grovekeys://panel/a.b", "grovekeys://panel/" + String(repeating: "a", count: 25)] {
            #expect(KeysURL(try #require(URL(string: text))) == nil, "\(text)")
        }
        // The Grove menu's link is as it was.
        #expect(KeysURL(try #require(URL(string: "grovekeys://grove-menu"))) == .groveMenu)
    }

    @Test func anythingElseIsIgnored() throws {
        for text in ["grovekeys://other", "http://menu", "grovekeys:", "grovekeys://", "grovekeys://menu/a/b",
                     "grovekeys://launcher/x", "grovekeys://palette/x", "grovekeys://cheatsheet/x", "http://launcher"] {
            #expect(KeysURL(try #require(URL(string: text))) == nil, "\(text)")
        }
    }
}
