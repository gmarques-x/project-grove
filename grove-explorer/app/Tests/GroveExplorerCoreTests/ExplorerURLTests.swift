import Foundation
@testable import GroveExplorerCore
import Testing

@Suite struct ExplorerURLTests {
    private func link(_ text: String) -> ExplorerURL? {
        URL(string: text).flatMap { ExplorerURL($0) }
    }

    @Test func openNamesThePercentDecodedPath() {
        #expect(link("groveexplorer://open?path=%2FUsers%2Fx%2FMy%20Docs")
            == .open(URL(fileURLWithPath: "/Users/x/My Docs")))
    }

    @Test func schemeAndHostAreReadWhateverTheirCase() {
        #expect(link("GroveExplorer://Open?path=/Applications") == .open(URL(fileURLWithPath: "/Applications")))
    }

    @Test func aPathThatDoesNotStartAtTheRootIsNoLink() {
        #expect(link("groveexplorer://open?path=Documents%2Fnotes") == nil)
        #expect(link("groveexplorer://open?path=~%2FDocuments") == nil)
        #expect(link("groveexplorer://open?path=") == nil)
    }

    @Test func withoutAPathThereIsNoLink() {
        #expect(link("groveexplorer://open") == nil)
        #expect(link("groveexplorer://open?file=%2FUsers") == nil)
    }

    @Test func anotherHostOrSchemeIsNoLink() {
        #expect(link("groveexplorer://show?path=%2FUsers") == nil)
        #expect(link("groveexplorer://?path=%2FUsers") == nil)
        #expect(link("grovekeys://open?path=%2FUsers") == nil)
        #expect(link("file:///Users") == nil)
    }
}
