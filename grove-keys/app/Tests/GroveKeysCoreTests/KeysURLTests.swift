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

    @Test func thePaletteAndTheCheatSheetAreRecognised() throws {
        #expect(KeysURL(try #require(URL(string: "grovekeys://palette"))) == .palette)
        #expect(KeysURL(try #require(URL(string: "grovekeys://cheatsheet"))) == .cheatSheet)
        #expect(KeysURL(try #require(URL(string: "grovekeys://CheatSheet/"))) == .cheatSheet)
    }

    @Test func anythingElseIsIgnored() throws {
        for text in ["grovekeys://other", "http://menu", "grovekeys:", "grovekeys://", "grovekeys://menu/a/b",
                     "grovekeys://palette/x", "grovekeys://cheatsheet/x", "http://palette"] {
            #expect(KeysURL(try #require(URL(string: text))) == nil, "\(text)")
        }
    }
}
