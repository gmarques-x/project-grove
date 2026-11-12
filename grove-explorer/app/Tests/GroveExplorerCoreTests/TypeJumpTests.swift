import Foundation
@testable import GroveExplorerCore
import Testing

/// Typing letters in the list: what has been typed so far, and when it starts again.
@Suite struct TypeJumpTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func lettersTypedInQuickSuccessionAddUp() {
        var jump = TypeJump()
        #expect(jump.typed("g", at: start) == "g")
        #expect(jump.typed("r", at: start.addingTimeInterval(0.3)) == "gr")
        #expect(jump.typed("o", at: start.addingTimeInterval(0.9)) == "gro")
    }

    @Test func aPauseOfASecondStartsAgain() {
        var jump = TypeJump()
        _ = jump.typed("g", at: start)
        #expect(jump.typed("r", at: start.addingTimeInterval(1.0)) == "r")
        // The second counts from the last letter, not the first.
        #expect(jump.typed("e", at: start.addingTimeInterval(1.9)) == "re")
        #expect(jump.typed("a", at: start.addingTimeInterval(3)) == "a")
    }

    @Test func resetForgetsWhatWasTyped() {
        var jump = TypeJump()
        _ = jump.typed("g", at: start)
        jump.reset()
        #expect(jump.typed("r", at: start.addingTimeInterval(0.1)) == "r")
    }
}
