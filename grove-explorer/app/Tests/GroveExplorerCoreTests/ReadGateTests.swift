import Foundation
import GroveExplorerCore
import Testing

/// One read of a pane's folder at a time: a folder written to without a
/// pause must not start a read per watcher tick, each undoing the last.
@Suite struct ReadGateTests {
    private let builds = URL(fileURLWithPath: "/Users/me/project/build", isDirectory: true)
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    @Test func aTickWithNothingInFlightStartsARead() {
        var gate = ReadGate()
        let answer1 = gate.changed(builds)
        #expect(answer1)
        gate.begin(builds)
        #expect(gate.inFlight == builds.standardizedFileURL.path)
    }

    @Test func ticksDuringAReadStartNoneAndItsLandingStartsExactlyOne() {
        var gate = ReadGate()
        gate.begin(builds)
        // A storm: the folder changes all through the read.
        for _ in 0..<100 {
            let started = gate.changed(builds)
            #expect(!started)
        }
        // The read lands: one more, for everything that changed meanwhile.
        let answer2 = gate.landed(builds)
        #expect(answer2)
        gate.begin(builds)
        // Nothing changed during that one: it is the last.
        let answer3 = gate.landed(builds)
        #expect(!answer3)
        #expect(gate.inFlight == nil)
        // The next tick starts a read again.
        let answer4 = gate.changed(builds)
        #expect(answer4)
    }

    @Test func aStormThatGoesOnIsOneReadAfterTheOther() {
        var gate = ReadGate()
        gate.begin(builds)
        var reads = 1
        for _ in 0..<5 {
            for _ in 0..<20 {
                let started = gate.changed(builds)
                #expect(!started)
            }
            let answer5 = gate.landed(builds)
            #expect(answer5)
            gate.begin(builds)
            reads += 1
        }
        let answer6 = gate.landed(builds)
        #expect(!answer6)
        // Five landings with changes behind them: five more reads, each
        // begun only when the one before had landed.
        #expect(reads == 6)
    }

    @Test func aReadThatLandsQuietlyAsksForNoOther() {
        var gate = ReadGate()
        gate.begin(builds)
        let answer7 = gate.landed(builds)
        #expect(!answer7)
        #expect(gate.inFlight == nil)
    }

    /// The tab goes elsewhere: that read begins at once, and what the
    /// folder left did meanwhile is nothing to it.
    @Test func aNavigationSupersedesAtOnce() {
        var gate = ReadGate()
        gate.begin(builds)
        let answer8 = gate.changed(builds)
        #expect(!answer8)
        gate.begin(home)
        #expect(gate.inFlight == home.standardizedFileURL.path)
        // The read it superseded comes back: not this gate's read.
        let answer9 = gate.landed(builds)
        #expect(!answer9)
        #expect(gate.inFlight == home.standardizedFileURL.path)
        // And the changes of the folder left ask for no read of the new one.
        let answer10 = gate.landed(home)
        #expect(!answer10)
    }

    @Test func aTickForAnotherFolderThanTheOneInFlightStartsARead() {
        var gate = ReadGate()
        gate.begin(home)
        let answer11 = gate.changed(builds)
        #expect(answer11)
    }

    @Test func aFolderIsItselfHoweverItsPathIsSpelled() {
        var gate = ReadGate()
        gate.begin(builds)
        let answer12 = gate.changed(URL(fileURLWithPath: "/Users/me/project/x/../build"))
        #expect(!answer12)
        let answer13 = gate.landed(URL(fileURLWithPath: "/Users/me/project/build"))
        #expect(answer13)
    }

    /// The pane begins the same folder again itself (a disk that stayed
    /// after an eject): as a navigation, at once, with nothing owed.
    @Test func beginningAgainOwesNothing() {
        var gate = ReadGate()
        gate.begin(builds)
        let answer14 = gate.changed(builds)
        #expect(!answer14)
        gate.begin(builds)
        let answer15 = gate.landed(builds)
        #expect(!answer15)
    }
}
