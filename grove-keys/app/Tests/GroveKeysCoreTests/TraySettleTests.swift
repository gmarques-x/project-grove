import Foundation
import Testing
@testable import GroveKeysCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

/// The seconds after t0 at which `events` list.
private func listings(_ events: [(TraySettle.Event, TimeInterval)]) -> [TimeInterval] {
    TraySettle.listings(events.map { ($0.0, at($0.1)) }).map { $0.timeIntervalSince(t0) }
}

struct TraySettleTests {
    @Test func burstOfLaunchesListsOnce() {
        // A login: ten apps launching a quarter second apart are one
        // listing, 2 s after the last.
        let burst = (0..<10).map { (TraySettle.Event.launched, Double($0) * 0.25) }
        #expect(listings(burst) == [2.25 + TraySettle.appDelay])
    }

    @Test func aLaunchListsAfterTwoSeconds() {
        #expect(TraySettle.appDelay == 2)
        #expect(listings([(.launched, 0)]) == [2])
        #expect(listings([(.quit, 5)]) == [7])
    }

    @Test func launchesFarApartListEachTime() {
        #expect(listings([(.launched, 0), (.quit, 10), (.launched, 30)]) == [2, 12, 32])
    }

    @Test func aBurstThatNeverSettlesStillListsByTheLongestWait() {
        // A launch every second for 30 s: listed every longest wait, never
        // put off for good.
        #expect(TraySettle.longest == 10)
        let endless = (0..<30).map { (TraySettle.Event.launched, Double($0)) }
        #expect(listings(endless) == [10, 20, 30])
    }

    @Test func aChangeInTheBarSettlesShorter() {
        #expect(TraySettle.barDelay < TraySettle.appDelay)
        #expect(listings([(.barChanged, 0)]) == [TraySettle.barDelay])
        // The bar's children change as an app launches: one listing, the app's settle.
        #expect(listings([(.launched, 0), (.barChanged, 0.25), (.barChanged, 0.5)]) == [2])
        // A launch after a bar change waits for the launch.
        #expect(listings([(.barChanged, 0), (.launched, 0.25)]) == [2.25])
    }

    @Test func dueAndFire() {
        var settle = TraySettle()
        #expect(settle.due == nil)
        let r1 = settle.fire(at: at(0))
        #expect(!r1)
        let r2 = settle.note(.launched, at: at(0))
        #expect(r2 == at(2))
        let r3 = settle.note(.launched, at: at(1))
        #expect(r3 == at(3))
        // Its timer for 2 s comes early now: not yet.
        let r4 = settle.fire(at: at(2))
        #expect(!r4)
        #expect(settle.due == at(3))
        let r5 = settle.fire(at: at(3))
        #expect(r5)
        #expect(settle.due == nil)
        // Nothing pending: a stray timer lists nothing.
        let r6 = settle.fire(at: at(4))
        #expect(!r6)
    }

    @Test func aListingNowClearsWhatWasPending() {
        // The panel opened and listed: the settle's own listing isn't needed.
        var settle = TraySettle()
        _ = settle.note(.launched, at: at(0))
        settle.listed()
        #expect(settle.due == nil)
        let r7 = settle.fire(at: at(2))
        #expect(!r7)
    }
}
