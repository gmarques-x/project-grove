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

    @Test func anythingElseIsIgnored() throws {
        for text in ["grovekeys://other", "http://menu", "grovekeys:", "grovekeys://", "grovekeys://menu/extra"] {
            #expect(KeysURL(try #require(URL(string: text))) == nil, "\(text)")
        }
    }
}
