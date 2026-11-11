import Foundation
import Testing
@testable import GroveThemesCore

@Suite struct ThemesURLTests {
    @Test func galleryIsRecognised() throws {
        #expect(ThemesURL(try #require(URL(string: "grovethemes://gallery"))) == .gallery)
        #expect(ThemesURL(try #require(URL(string: "GroveThemes://Gallery"))) == .gallery)
    }

    @Test func anythingElseIsIgnored() throws {
        for text in ["grovethemes://other", "grovethemes://gallery/x", "http://gallery", "grovethemes:"] {
            #expect(ThemesURL(try #require(URL(string: text))) == nil, "\(text)")
        }
    }
}
