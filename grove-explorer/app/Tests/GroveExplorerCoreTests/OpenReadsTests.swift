import Foundation
import GroveExplorerCore
import Testing

/// The reads of a pane's open folders, replayed as the app does them: a
/// read's number comes from one counter for every tab and folder.
@Suite struct OpenReadsTests {
    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// The app's `readCount`.
    private struct Counter {
        var count = 0
        mutating func next() -> Int {
            count += 1
            return count
        }
    }

    /// Tab A on /t reads /t/a; the pane switches to tab B on /t, which has
    /// /t/a open too and reads it. A's read lands first: it is not B's, and
    /// it must not take away B's read, which lands and is taken.
    @Test func aStaleReadOfAnotherTabNeitherLandsNorErasesTheLiveOne() {
        var counter = Counter()
        var tabA = OpenReads()
        let first = counter.next()
        let answer1 = tabA.want(folder("/t/a"))
        #expect(answer1)
        tabA.begun(folder("/t/a"), number: first)

        // The switch: the pane's reads start afresh for B.
        var tabB = OpenReads()
        let second = counter.next()
        let answer2 = tabB.want(folder("/t/a"))
        #expect(answer2)
        tabB.begun(folder("/t/a"), number: second)

        // A's read lands on the pane, which now has B's reads.
        #expect(!tabB.isLatest(folder("/t/a"), number: first))
        tabB.dropped(folder("/t/a"), number: first)
        let answer3 = tabB.landed(folder("/t/a"), number: first)
        #expect(answer3 == false)
        // B's is still on its way, and is taken.
        #expect(tabB.isLatest(folder("/t/a"), number: second))
        #expect(tabB.isWanted(folder("/t/a")))
        let answer4 = tabB.landed(folder("/t/a"), number: second)
        #expect(answer4 == false)
        #expect(!tabB.isWanted(folder("/t/a")))
    }

    /// Closed and opened again quickly: the first read is older than the
    /// second, whichever lands first.
    @Test func aCloseAndQuickReopenTakesOnlyTheNewerRead() {
        var counter = Counter()
        var reads = OpenReads()
        let older = counter.next()
        _ = reads.want(folder("/t/a"))
        reads.begun(folder("/t/a"), number: older)
        reads.keep([])  // closed
        let newer = counter.next()
        _ = reads.want(folder("/t/a"))
        reads.begun(folder("/t/a"), number: newer)

        #expect(!reads.isLatest(folder("/t/a"), number: older))
        reads.dropped(folder("/t/a"), number: older)
        #expect(reads.isLatest(folder("/t/a"), number: newer))
    }

    @Test func aDroppedLatestReadIsForgotten() {
        var reads = OpenReads()
        _ = reads.want(folder("/t/a"))
        reads.begun(folder("/t/a"), number: 7)
        reads.dropped(folder("/t/a"), number: 7)
        #expect(!reads.isWanted(folder("/t/a")))
    }

    /// A tick while a read is on its way: no second read now, one when it lands.
    @Test func aChangeDuringAReadReadsOnceMoreWhenItLands() {
        var reads = OpenReads()
        let answer5 = reads.changed(folder("/t/a"))  // nothing on its way: read now
        #expect(answer5)
        _ = reads.want(folder("/t/a"))
        reads.begun(folder("/t/a"), number: 1)
        let answer6 = reads.changed(folder("/t/a"))
        #expect(!answer6)
        let answer7 = reads.changed(folder("/t/a/"))
        #expect(!answer7)
        let answer8 = reads.landed(folder("/t/a"), number: 1)
        #expect(answer8)
        let answer9 = reads.changed(folder("/t/b"))
        #expect(answer9)
    }

    @Test func atMostEightFoldersAreReadAtOnceTheRestInOrder() {
        var reads = OpenReads()
        #expect(OpenReads.atOnce == 8)
        for number in 0..<8 {
            let answer10 = reads.want(folder("/t/f\(number)"))
            #expect(answer10)
            reads.begun(folder("/t/f\(number)"), number: number + 1)
        }
        let answer11 = reads.want(folder("/t/w1"))
        #expect(!answer11)
        let answer12 = reads.want(folder("/t/w2"))
        #expect(!answer12)
        let answer13 = reads.want(folder("/t/w1"))  // waits once
        #expect(!answer13)
        #expect(reads.isWanted(folder("/t/w1")))
        let answer14 = reads.next()
        #expect(answer14 == nil)
        // One on its way is read again at once all the same.
        let answer15 = reads.want(folder("/t/f3"))
        #expect(answer15)
        _ = reads.landed(folder("/t/f0"), number: 1)
        let answer16 = reads.next()
        #expect(answer16?.path == "/t/w1")
        reads.begun(folder("/t/w1"), number: 20)
        let answer17 = reads.next()
        #expect(answer17 == nil)
        // A waiting folder that closed is not read.
        reads.keep(Set((1..<8).map { "/t/f\($0)" } + ["/t/w1"]))
        _ = reads.landed(folder("/t/f1"), number: 2)
        let answer18 = reads.next()
        #expect(answer18 == nil)
    }

    /// ⌥→ on X fills the eight slots and queues more; → opens Y, which
    /// waits; X closes: its reads go, and Y's turn has come.
    @Test func whenReadsOnTheirWayAreLetGoTheWaitingOneIsNext() {
        var reads = OpenReads()
        for number in 0..<8 {
            _ = reads.want(folder("/t/x/f\(number)"))
            reads.begun(folder("/t/x/f\(number)"), number: number + 1)
        }
        let queued = reads.want(folder("/t/x/more"))
        let waits = reads.want(folder("/t/y"))
        #expect(!queued && !waits)
        reads.keep(["/t/y"])
        #expect(reads.reading == 0)
        let next = reads.next()
        #expect(next?.path == "/t/y")
    }

    /// A folder the user just opened goes before a ⌥→ backlog.
    @Test func aFolderTheUserOpenedJumpsTheQueue() {
        var reads = OpenReads()
        for number in 0..<8 {
            _ = reads.want(folder("/t/x/f\(number)"))
            reads.begun(folder("/t/x/f\(number)"), number: number + 1)
        }
        for number in 0..<50 { _ = reads.want(folder("/t/x/w\(number)")) }
        let mine = reads.want(folder("/t/y"), first: true)
        #expect(!mine)
        _ = reads.landed(folder("/t/x/f0"), number: 1)
        let next = reads.next()
        #expect(next?.path == "/t/y")
        reads.begun(folder("/t/y"), number: 100)
        // Asked for first again while it waits behind others: moved to the front.
        _ = reads.want(folder("/t/x/w9"), first: true)
        _ = reads.landed(folder("/t/x/f1"), number: 2)
        let after = reads.next()
        #expect(after?.path == "/t/x/w9")
    }
}
