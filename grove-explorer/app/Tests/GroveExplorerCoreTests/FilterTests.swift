import Foundation
import GroveExplorerCore
import Testing

@Suite struct FilterTests {
    private func entries(_ names: [String]) -> [Entry] {
        names.map {
            Entry(
                url: URL(fileURLWithPath: "/tmp/grove/\($0)"), name: $0, kind: .file,
                size: 1, modified: nil, isHidden: false, typeDescription: "Document")
        }
    }

    private func entries(_ names: String...) -> [Entry] { entries(names) }

    private func matches(_ words: String, in names: String...) -> [String] {
        Filter.matches(entries(names), words: words).map(\.name)
    }

    // MARK: The ⌘F filter

    @Test func everyWordMustBeSomewhereInTheName() {
        #expect(matches("gro key", in: "grove-keys", "grove-themes", "keys.toml", "monkey-grove") == ["grove-keys", "monkey-grove"])
    }

    @Test func aWordMatchesAnywhereNotOnlyAtTheStart() {
        #expect(matches("eme", in: "grove-themes", "README.md", "notes") == ["grove-themes"])
        #expect(matches(".md", in: "grove-themes", "README.md") == ["README.md"])
    }

    @Test func caseIsIgnored() {
        #expect(matches("READ", in: "readme.md", "Readme 2.md", "notes") == ["readme.md", "Readme 2.md"])
        #expect(matches("read", in: "README.md") == ["README.md"])
    }

    @Test func accentsAreIgnoredBothWays() {
        #expect(matches("é", in: "eclair.txt", "éclair.txt", "talk") == ["eclair.txt", "éclair.txt"])
        #expect(matches("e", in: "éclair.txt") == ["éclair.txt"])
        #expect(matches("acucar", in: "Açúcar.pdf") == ["Açúcar.pdf"])
        // A name stored decomposed (e + U+0301), as a volume may give it.
        #expect(matches("café", in: "cafe\u{301} 10.txt") == ["cafe\u{301} 10.txt"])
        #expect(matches("cafe\u{301}", in: "café 9.txt") == ["café 9.txt"])
    }

    @Test func noWordsReturnsEverythingInTheGivenOrder() {
        let all = entries("b", "a", "c")
        #expect(Filter.matches(all, words: "") == all)
        #expect(Filter.matches(all, words: "  \t ") == all)
    }

    @Test func theGivenOrderIsKeptAndSpacesAroundWordsDoNotCount() {
        #expect(matches("  o   t ", in: "zot", "other", "none", "atom") == ["zot", "other", "atom"])
    }

    @Test func nothingMatchingReturnsNothing() {
        #expect(matches("xyz", in: "grove-keys", "notes").isEmpty)
        #expect(Filter.matches([], words: "a").isEmpty)
    }

    // MARK: Type-to-jump

    @Test func jumpsToTheFirstNameWithThatPrefixInTheGivenOrder() {
        let list = entries("docs", "Grove", "grove-keys", "great.txt", "zeta")
        #expect(Filter.jumpIndex(in: list, typed: "gr") == 1)
        #expect(Filter.jumpIndex(in: list, typed: "GRE") == 3)
        #expect(Filter.jumpIndex(in: list, typed: "grove-") == 2)
        #expect(Filter.jumpIndex(in: list, typed: "z") == 4)
    }

    @Test func aPrefixIsNotFoundInTheMiddleOfAName() {
        let list = entries("monkey-grove", "docs")
        #expect(Filter.jumpIndex(in: list, typed: "gr") == nil)
        #expect(Filter.jumpIndex(in: list, typed: "x") == nil)
    }

    @Test func nothingTypedJumpsNowhere() {
        #expect(Filter.jumpIndex(in: entries("a", "b"), typed: "") == nil)
        #expect(Filter.jumpIndex(in: [], typed: "a") == nil)
    }

    @Test func aSpaceTypedIsPartOfThePrefix() {
        let list = entries("my-file", "my file", "myfile")
        #expect(Filter.jumpIndex(in: list, typed: "my f") == 1)
    }

    @Test func jumpingIgnoresAccentsToo() {
        let list = entries("docs", "École.pdf", "eclair")
        #expect(Filter.jumpIndex(in: list, typed: "ec") == 1)
        #expect(Filter.jumpIndex(in: list, typed: "éc") == 1)
    }

    // MARK: The filter and the selection

    @Test func aSelectionKeepsOnlyTheRowsTheFilterShows() {
        let all = entries("notes.md", "shot-1.png", "shot-2.png")
        let shown = Filter.matches(all, words: "shot")
        let selection = Set([all[0].url, all[1].url])
        #expect(Filter.visibleSelection(selection, among: shown) == [all[1].url])
    }

    @Test func aSelectionWhollyShownIsKeptWhole() {
        let all = entries("a", "b")
        #expect(Filter.visibleSelection(Set(all.map(\.url)), among: all) == Set(all.map(\.url)))
        #expect(Filter.visibleSelection([], among: all).isEmpty)
        #expect(Filter.visibleSelection([all[0].url], among: []).isEmpty)
    }

    // MARK: ↑ and ↓ from the filter field

    @Test func withNothingSelectedDownTakesTheFirstRowAndUpTheLast() {
        let shown = entries("a", "b", "c")
        #expect(Filter.moved(from: [], by: 1, in: shown) == shown[0].url)
        #expect(Filter.moved(from: [], by: -1, in: shown) == shown[2].url)
    }

    @Test func theSelectionMovesOneRowAndStopsAtTheEnds() {
        let shown = entries("a", "b", "c")
        #expect(Filter.moved(from: [shown[1].url], by: 1, in: shown) == shown[2].url)
        #expect(Filter.moved(from: [shown[1].url], by: -1, in: shown) == shown[0].url)
        #expect(Filter.moved(from: [shown[2].url], by: 1, in: shown) == shown[2].url)
        #expect(Filter.moved(from: [shown[0].url], by: -1, in: shown) == shown[0].url)
    }

    @Test func fromSeveralRowsItMovesFromTheEndItGoesTowards() {
        let shown = entries("a", "b", "c", "d")
        let chosen = Set([shown[1].url, shown[2].url])
        #expect(Filter.moved(from: chosen, by: 1, in: shown) == shown[3].url)
        #expect(Filter.moved(from: chosen, by: -1, in: shown) == shown[0].url)
    }

    @Test func aSelectionThatIsNotShownCountsAsNone() {
        let shown = entries("a", "b")
        let gone = URL(fileURLWithPath: "/tmp/grove/zzz")
        #expect(Filter.moved(from: [gone], by: 1, in: shown) == shown[0].url)
    }

    @Test func noRowsNoMove() {
        #expect(Filter.moved(from: [], by: 1, in: []) == nil)
    }
}
