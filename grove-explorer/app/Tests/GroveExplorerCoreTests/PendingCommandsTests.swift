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

    // MARK: Dropping

    @Test func theSiblingsOfAGivenUpCommandAreDroppedAndTheRestKeepTheirOrder() {
        var pending = PendingCommands<String>()
        _ = pending.add("paste-copy")
        _ = pending.add("paste-duplicate")
        _ = pending.add("trash")
        _ = pending.add("paste-more")
        #expect(pending.dropWaiting { $0.hasPrefix("paste") } == 2)
        // The one in hand is not the queue's to drop.
        #expect(pending.inHand == "paste-copy")
        #expect(pending.waiting == ["trash"])
        #expect(pending.dropWaiting { $0 == "nothing" } == 0)
    }

    // MARK: Quitting

    @Test func quittingWithNothingGoingQuitsAtOnce() {
        var pending = PendingCommands<String>()
        #expect(pending.quit(promptIsUp: false, runIsGoing: false) == QuitPlan(waits: false, cancelsRun: false, answersPrompt: false, dropped: 0))
    }

    @Test func quittingDuringARunCancelsItDropsTheQueuedAndWaits() {
        var pending = PendingCommands<String>()
        _ = pending.add("copy")
        _ = pending.add("move")
        _ = pending.add("trash")
        #expect(pending.quit(promptIsUp: false, runIsGoing: true) == QuitPlan(waits: true, cancelsRun: true, answersPrompt: false, dropped: 2))
        #expect(pending.inHand == "copy")
        #expect(pending.waiting.isEmpty)
        // The one in hand ends, and nothing follows it.
        #expect(pending.finished() == nil)
        #expect(pending.isIdle)
    }

    @Test func quittingWithThePromptUpAnswersItWithCancel() {
        var pending = PendingCommands<String>()
        _ = pending.add("copy")
        _ = pending.add("move")
        #expect(pending.quit(promptIsUp: true, runIsGoing: false) == QuitPlan(waits: true, cancelsRun: false, answersPrompt: true, dropped: 1))
    }

    @Test func aCommandInHandThatNeitherRunsNorAsksIsStillWaitedFor() {
        // Between its validate and its run, or an undo: it ends by itself.
        var pending = PendingCommands<String>()
        _ = pending.add("undo")
        #expect(pending.quit(promptIsUp: false, runIsGoing: false) == QuitPlan(waits: true, cancelsRun: false, answersPrompt: false, dropped: 0))
    }

    @Test func aPromptOrARunWithNothingInHandIsNothingToWaitFor() {
        var pending = PendingCommands<String>()
        #expect(!pending.quit(promptIsUp: true, runIsGoing: true).waits)
    }
}
