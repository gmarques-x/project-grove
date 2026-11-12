import Foundation
import GroveExplorerCore
import Testing

@Suite struct ConflictAskingTests {
    private let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)
    private func there(_ name: String) -> URL { documents.appendingPathComponent(name) }

    @Test func eachNameIsAskedAboutInTurn() {
        var asking = ConflictAsking(existing: [there("a.md"), there("b.md"), there("c.md")])
        #expect(asking.current == there("a.md"))
        #expect(asking.remaining == 2)
        asking.answer(.skip, applyToAll: false)
        #expect(asking.current == there("b.md"))
        #expect(asking.remaining == 1)
        asking.answer(.replace, applyToAll: false)
        #expect(asking.current == there("c.md"))
        #expect(asking.remaining == 0)
        asking.answer(.keepBoth, applyToAll: false)
        #expect(asking.current == nil)
        #expect(asking.answers == [there("a.md"): .skip, there("b.md"): .replace, there("c.md"): .keepBoth])
        #expect(asking.plan.choice(for: there("a.md")) == .skip)
        #expect(asking.plan.choice(for: there("b.md")) == .replace)
        #expect(asking.plan.choice(for: there("c.md")) == .keepBoth)
    }

    @Test func applyToAllAnswersTheRestAndOnlyTheRest() {
        var asking = ConflictAsking(existing: [there("a.md"), there("b.md"), there("c.md")])
        asking.answer(.skip, applyToAll: false)
        asking.answer(.replace, applyToAll: true)
        #expect(asking.current == nil)
        #expect(asking.answers == [there("a.md"): .skip, there("b.md"): .replace, there("c.md"): .replace])
        // The one answered by itself keeps its answer.
        #expect(asking.plan.choice(for: there("a.md")) == .skip)
        #expect(asking.plan.choice(for: there("c.md")) == .replace)
    }

    @Test func aNameNobodyWasAskedAboutHasNoAnswerWithoutApplyToAll() {
        var asking = ConflictAsking(existing: [there("a.md")])
        asking.answer(.replace, applyToAll: false)
        #expect(asking.plan.choice(for: there("appeared-since.md")) == nil)
        #expect(asking.answers[there("appeared-since.md")] == nil)
    }

    @Test func aNameGivenTwiceIsAskedAboutOnceAndAnsweredUnderBothUrls() {
        let slash = URL(fileURLWithPath: "/Users/me/Documents/docs", isDirectory: true)
        let plain = URL(fileURLWithPath: "/Users/me/Documents/docs", isDirectory: false)
        var asking = ConflictAsking(existing: [slash, plain, there("b.md")])
        #expect(asking.remaining == 1)
        asking.answer(.keepBoth, applyToAll: false)
        #expect(asking.current == there("b.md"))
        asking.answer(.skip, applyToAll: false)
        #expect(asking.answers[slash] == .keepBoth)
        #expect(asking.answers[plain] == .keepBoth)
        #expect(asking.answers.count == 3)
    }

    @Test func nothingExistingIsNothingToAsk() {
        var asking = ConflictAsking(existing: [])
        #expect(asking.current == nil)
        asking.answer(.replace, applyToAll: true)
        #expect(asking.answers.isEmpty)
        #expect(asking.plan == ConflictPlan())
    }

    // MARK: Words

    @Test func thePromptSaysTheNameAndWhere() {
        #expect(ConflictWords.title(for: there("notes.md")) == "An item named “notes.md” already exists in Documents.")
        #expect(ConflictWords.thereLabel(for: there("notes.md")) == "In Documents")
    }

    @Test func theItemComingIsBeingCopiedOrMoved() {
        let item = URL(fileURLWithPath: "/Users/me/Downloads/notes.md")
        #expect(ConflictWords.comingLabel(for: .copy(items: [item], to: documents)) == "Being copied")
        #expect(ConflictWords.comingLabel(for: .move(items: [item], to: documents)) == "Being moved")
    }

    @Test func sizeAndDateOfAnItem() {
        #expect(ConflictWords.detail(size: 2_000, date: "9 Nov 2026 at 02:04") == "2 KB · 9 Nov 2026 at 02:04")
        // A folder has no size of its own.
        #expect(ConflictWords.detail(size: nil, date: "Today at 09:41") == "Today at 09:41")
        #expect(ConflictWords.detail(size: 2_000, date: nil) == "2 KB")
        #expect(ConflictWords.detail(size: nil, date: nil) == "--")
    }

    @Test func applyToAllSaysHowManyMore() {
        #expect(ConflictWords.applyToAll(remaining: 3) == "Apply to all (3 more)")
        #expect(ConflictWords.applyToAll(remaining: 1) == "Apply to all (1 more)")
    }

    // MARK: The buttons

    @Test func keepBothIsTheButtonReturnTakes() {
        #expect(ConflictButton.standard == .keepBoth)
        #expect(ConflictButton.keepBoth.choice == .keepBoth)
        #expect(ConflictButton.replace.choice == .replace)
        #expect(ConflictButton.skip.choice == .skip)
        // Cancel is no answer: it gives up the whole operation.
        #expect(ConflictButton.cancel.choice == nil)
    }

    @Test func theKeyboardGoesRoundTheButtonsAsTheyStand() {
        #expect(ConflictButton.allCases == [.cancel, .skip, .replace, .keepBoth])
        #expect(ConflictButton.keepBoth.next == .cancel)
        #expect(ConflictButton.cancel.next == .skip)
        #expect(ConflictButton.cancel.previous == .keepBoth)
        #expect(ConflictButton.replace.previous == .skip)
    }
}
