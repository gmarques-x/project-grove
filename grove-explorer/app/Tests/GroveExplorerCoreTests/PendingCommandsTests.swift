import GroveExplorerCore
import Testing

@Suite struct PendingCommandsTests {
    @Test func theFirstCommandStartsAtOnce() {
        var pending = PendingCommands<String>()
        #expect(pending.isIdle)
        #expect(pending.add("copy") == "copy")
        #expect(!pending.isIdle)
        #expect(pending.inHand == "copy")
    }

    @Test func aCommandIssuedWhileOneRunsWaitsBehindIt() {
        var pending = PendingCommands<String>()
        _ = pending.add("copy")
        #expect(pending.add("move") == nil)
        #expect(pending.add("trash") == nil)
        #expect(pending.inHand == "copy")
        #expect(pending.waiting == ["move", "trash"])
    }

    @Test func theyRunInTheOrderIssuedOneAtATime() {
        var pending = PendingCommands<String>()
        _ = pending.add("copy")
        _ = pending.add("move")
        _ = pending.add("trash")
        #expect(pending.finished() == "move")
        #expect(pending.inHand == "move")
        // One issued meanwhile goes to the end.
        #expect(pending.add("rename") == nil)
        #expect(pending.finished() == "trash")
        #expect(pending.finished() == "rename")
        #expect(!pending.isIdle)
        #expect(pending.finished() == nil)
        #expect(pending.isIdle)
        #expect(pending.inHand == nil)
    }

    @Test func afterTheLastOneTheNextStartsAtOnceAgain() {
        var pending = PendingCommands<String>()
        _ = pending.add("copy")
        _ = pending.finished()
        #expect(pending.add("move") == "move")
    }

    @Test func finishingWithNothingInHandChangesNothing() {
        var pending = PendingCommands<String>()
        #expect(pending.finished() == nil)
        #expect(pending.isIdle)
    }

    @Test func undoIsOfferedOnlyWhileNothingIsInHandOrWaiting() {
        var pending = PendingCommands<String>()
        #expect(pending.allowsUndo)
        _ = pending.add("copy")
        // From its `existingNames` to its `record`, a command is in hand.
        #expect(!pending.allowsUndo)
        _ = pending.add("move")
        _ = pending.finished()
        #expect(!pending.allowsUndo)
        _ = pending.finished()
        #expect(pending.allowsUndo)
    }
}
