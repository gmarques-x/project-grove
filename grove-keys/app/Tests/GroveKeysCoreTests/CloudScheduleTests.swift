import Foundation
import Testing
@testable import GroveKeysCore

// Invented paths only (the repo is public). The clock is passed in.
private let oneDrive = URL(fileURLWithPath: "/Users/someone/Library/CloudStorage/OneDrive-Personal")
private let iCloud = URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs")
private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// A set that hit the cap for `root` and then drained back to `left` items.
private func overflowed(_ root: URL, left: Int, at now: Date) -> CloudPending {
    var pending = CloudPending()
    for i in 0...CloudPending.cap {
        pending.update(root.appendingPathComponent("\(i).txt"), root: root, state: .uploading, at: now)
    }
    for i in left..<CloudPending.cap { pending.settle(root.appendingPathComponent("\(i).txt")) }
    return pending
}

/// No item waiting for a read before `at` (they were all just read then).
private func readAt(_ pending: inout CloudPending, _ at: Date) {
    for entry in pending.entries { pending.update(entry.url, root: entry.root, state: entry.read, at: at) }
}

struct CloudScheduleTests {
    @Test func aRootNeedingARewalkIsDueOnceThereIsRoom() {
        var schedule = CloudSchedule()
        schedule.nextRootsCheck = t0 + 60
        let full = overflowed(oneDrive, left: CloudPending.cap, at: t0)
        #expect(!full.hasRoom)
        #expect(schedule.rescansDue(at: t0, pending: full, walks: []).isEmpty)
        let room = overflowed(oneDrive, left: 10, at: t0)
        #expect(schedule.rescansDue(at: t0, pending: room, walks: []) == [oneDrive])
        // Started: not again for a minute.
        schedule.started(rescan: oneDrive, at: t0)
        #expect(schedule.rescansDue(at: t0 + 59, pending: room, walks: []).isEmpty)
        #expect(schedule.rescansDue(at: t0 + 60, pending: room, walks: []) == [oneDrive])
    }

    @Test func aWholeRootWalkWaitingCoversTheRewalkAndTheDeadlineIsNotPast() {
        // The spin: room again after the cap, a whole-root walk of it already
        // waiting (events asked for it and it settles until t0 + 20): nothing
        // is due, so the deadline must not be in the past.
        let schedule = CloudSchedule()
        var pending = overflowed(oneDrive, left: 10, at: t0)
        readAt(&pending, t0 + 5)
        var later = schedule
        later.nextRootsCheck = t0 + 60
        let waiting = [CloudSchedule.Walk(root: oneDrive, isWholeRoot: true, notBefore: t0 + 20)]
        #expect(later.rescansDue(at: t0 + 5, pending: pending, walks: waiting).isEmpty)
        let deadline = later.deadline(at: t0 + 5, pending: pending, walks: waiting, roots: [oneDrive])
        #expect(deadline > t0 + 5)
        #expect(deadline == t0 + 10)  // the next re-read (5 s), before the walk's start
        // A walk of a folder below doesn't cover the whole root: the re-walk is due.
        let below = [CloudSchedule.Walk(root: oneDrive, isWholeRoot: false, notBefore: t0 + 20)]
        #expect(later.rescansDue(at: t0 + 5, pending: pending, walks: below) == [oneDrive])
    }

    @Test func aRefusedRootIsNeverRewalkedAfterTheCapAndDoesNotHoldTheDeadline() {
        var schedule = CloudSchedule()
        schedule.nextRootsCheck = t0 + 60
        var pending = overflowed(oneDrive, left: 10, at: t0)
        readAt(&pending, t0 + 5)
        schedule.refuse(oneDrive, at: t0)
        #expect(schedule.isRefused(oneDrive))
        #expect(schedule.rescansDue(at: t0 + 5, pending: pending, walks: []).isEmpty)
        #expect(schedule.deadline(at: t0 + 5, pending: pending, walks: [], roots: [oneDrive]) > t0 + 5)
    }

    @Test func aRefusedRootIsTriedAgainInTenMinutesWhenNothingWalksIt() {
        var schedule = CloudSchedule()
        schedule.nextRootsCheck = .distantFuture
        schedule.refuse(oneDrive, at: t0)
        // A second refusal doesn't push the retry back.
        schedule.refuse(oneDrive, at: t0 + 100)
        let pending = CloudPending()
        #expect(schedule.retriesDue(at: t0 + 599, roots: [oneDrive, iCloud], walks: []).isEmpty)
        #expect(schedule.deadline(at: t0 + 599, pending: pending, walks: [], roots: [oneDrive]) == t0 + 600)
        #expect(schedule.retriesDue(at: t0 + 600, roots: [oneDrive, iCloud], walks: []) == [oneDrive])
        // A walk of it under way: not due, and not the deadline either.
        let walking = [CloudSchedule.Walk(root: oneDrive, isWholeRoot: true, notBefore: .distantPast)]
        #expect(schedule.retriesDue(at: t0 + 700, roots: [oneDrive], walks: walking).isEmpty)
        #expect(schedule.deadline(at: t0 + 700, pending: pending, walks: [], roots: [oneDrive]) <= t0 + 700)
        // A root that's no longer followed isn't tried.
        #expect(schedule.retriesDue(at: t0 + 700, roots: [iCloud], walks: []).isEmpty)
        #expect(schedule.deadline(at: t0 + 700, pending: pending, walks: [], roots: [iCloud]) == t0 + 760)
        // Started: ten minutes on again.
        schedule.started(retry: oneDrive, at: t0 + 700)
        #expect(schedule.isRefused(oneDrive))
        #expect(schedule.retriesDue(at: t0 + 1299, roots: [oneDrive], walks: []).isEmpty)
        schedule.clearRefusal(oneDrive)
        #expect(!schedule.isRefused(oneDrive))
        #expect(schedule.retriesDue(at: t0 + 9999, roots: [oneDrive], walks: []).isEmpty)
    }

    @Test func theDeadlineIsTheSoonestOfEverythingWaiting() {
        var schedule = CloudSchedule()
        schedule.nextRootsCheck = t0 + 50
        var pending = CloudPending()
        // Idle: a minute at most (the 30-minute rule, the roots).
        #expect(schedule.deadline(at: t0, pending: pending, walks: [], roots: []) == t0 + 50)
        schedule.nextRootsCheck = t0 + 600
        #expect(schedule.deadline(at: t0, pending: pending, walks: [], roots: []) == t0 + CloudSchedule.tick)
        pending.update(oneDrive.appendingPathComponent("a.txt"), root: oneDrive, state: .uploading, at: t0)
        #expect(schedule.deadline(at: t0, pending: pending, walks: [], roots: []) == t0 + 5)
        let settling = [CloudSchedule.Walk(root: oneDrive, isWholeRoot: false, notBefore: t0 + 2)]
        #expect(schedule.deadline(at: t0, pending: pending, walks: settling, roots: []) == t0 + 2)
    }

    @Test func whenNothingIsDueTheDeadlineIsNeverPast() {
        // Every mix of: an overflowed root with room or not, refused or not,
        // a whole-root walk waiting or not; once what's due is started (as the
        // tracker does every turn), nothing is due and no walk is ready, the
        // deadline is in the future.
        let now = t0 + 300
        for room in [false, true] {
            for refused in [false, true] {
                for walkWaiting in [false, true] {
                    var schedule = CloudSchedule()
                    schedule.nextRootsCheck = now + 30
                    if refused { schedule.refuse(oneDrive, at: t0) }
                    var pending = overflowed(oneDrive, left: room ? 10 : CloudPending.cap, at: t0)
                    readAt(&pending, now)
                    var walks = walkWaiting
                        ? [CloudSchedule.Walk(root: oneDrive, isWholeRoot: true, notBefore: now + 20)] : []
                    for root in schedule.rescansDue(at: now, pending: pending, walks: walks) {
                        schedule.started(rescan: root, at: now)
                        walks.append(.init(root: root, isWholeRoot: true, notBefore: .distantPast))
                    }
                    for root in schedule.retriesDue(at: now, roots: [oneDrive], walks: walks) {
                        schedule.started(retry: root, at: now)
                        walks.append(.init(root: root, isWholeRoot: true, notBefore: .distantPast))
                    }
                    // A walk just started runs this turn; the waiting ones don't.
                    let waiting = walks.filter { $0.notBefore > now }
                    guard waiting.count == walks.count else { continue }
                    #expect(schedule.rescansDue(at: now, pending: pending, walks: waiting).isEmpty)
                    #expect(schedule.retriesDue(at: now, roots: [oneDrive], walks: waiting).isEmpty)
                    let deadline = schedule.deadline(at: now, pending: pending, walks: waiting, roots: [oneDrive])
                    #expect(deadline > now, "room \(room) refused \(refused) waiting \(walkWaiting)")
                }
            }
        }
    }

    @Test func aRootThatGoesIsForgotten() {
        var schedule = CloudSchedule()
        schedule.refuse(oneDrive, at: t0)
        schedule.started(rescan: oneDrive, at: t0)
        schedule.forget(oneDrive)
        #expect(!schedule.isRefused(oneDrive))
        let room = overflowed(oneDrive, left: 10, at: t0)
        #expect(schedule.rescansDue(at: t0 + 1, pending: room, walks: []) == [oneDrive])
    }
}

struct CloudThrottleTests {
    @Test func atMostTwiceASecondAndTheLatestAlwaysLands() {
        var throttle = CloudThrottle<Int>(interval: 0.5)
        // The first is sent at once.
        #expect(throttle.offer(1, at: t0) == 0)
        #expect(throttle.flush(at: t0) == 1)
        // The next within half a second waits for the rest of it; offers
        // meanwhile are folded into that one send, the latest kept.
        let wait = throttle.offer(2, at: t0 + 0.1)
        #expect(wait.map { abs($0 - 0.4) < 1e-6 } == true)
        #expect(throttle.offer(3, at: t0 + 0.2) == nil)
        #expect(throttle.offer(4, at: t0 + 0.3) == nil)
        #expect(throttle.flush(at: t0 + 0.5) == 4)
        // Nothing waiting: nothing to send.
        #expect(throttle.flush(at: t0 + 0.6) == nil)
        // Long after: at once again.
        #expect(throttle.offer(5, at: t0 + 2) == 0)
        #expect(throttle.flush(at: t0 + 2) == 5)
        #expect(CloudThrottle<Int>.summaryInterval == 0.5)
    }
}
