import Foundation
import Testing
@testable import GroveKeysCore

/// A pretend app: what is open (window and menu ids), and what each press
/// opens. No Accessibility anywhere.
private final class Pretend {
    var running = true
    var open: [Int] = [1, 2]
    var windows: [Int] = [40]
    /// A window server window the element's press adds.
    var windowOnElement: [Int] = []
    /// What pressing the element, then the wrapper, adds.
    var opensOnElement: [Int] = []
    var opensOnWrapper: [Int] = []
    var presses: [Bool] = []
    var snapshots = 0

    func run(wrapper: Bool = true, trusted: Bool = true) -> TrayPress.Outcome {
        TrayPress.run(
            wrapper: wrapper, trusted: trusted, isRunning: { self.running },
            snapshot: {
                self.snapshots += 1
                return TrayPress.Snapshot(elements: self.open, windows: self.windows)
            },
            press: { onWrapper in
                self.presses.append(onWrapper)
                self.open += onWrapper ? self.opensOnWrapper : self.opensOnElement
                if !onWrapper { self.windows += self.windowOnElement }
            },
            within: { probe in probe() })
    }
}

struct TrayPressTests {
    @Test func openedMeansSomethingNew() {
        #expect(TrayItems.opened(before: [1, 2], after: [1, 2, 3]))
        #expect(TrayItems.opened(before: [], after: [7]))
        // A new one while another closed: still opened.
        #expect(TrayItems.opened(before: [1, 2], after: [2, 9]))
    }

    @Test func nothingNewIsNotOpened() {
        #expect(!TrayItems.opened(before: [1, 2], after: [1, 2]))
        #expect(!TrayItems.opened(before: [1, 2], after: [2, 1]))
        #expect(!TrayItems.opened(before: [1, 2], after: [1]))
        #expect(!TrayItems.opened(before: [], after: []))
        #expect(!TrayItems.opened(before: [3], after: [3, 3]))
    }

    @Test func elementIdsAndWindowNumbersAreKeptApart() {
        // A new window whose number equals an element id already open is
        // still new; so is a new menu whose id equals a window's number.
        let before = TrayPress.Snapshot(elements: [7], windows: [9])
        #expect(TrayItems.opened(before: before, after: TrayPress.Snapshot(elements: [7], windows: [9, 7])))
        #expect(TrayItems.opened(before: before, after: TrayPress.Snapshot(elements: [7, 9], windows: [9])))
        #expect(!TrayItems.opened(before: before, after: TrayPress.Snapshot(elements: [7], windows: [9])))
        #expect(!TrayItems.opened(before: before, after: TrayPress.Snapshot(elements: [], windows: [])))
    }

    @Test func aNewServerWindowCountsAsOpened() {
        let app = Pretend()
        app.windowOnElement = [1]
        #expect(app.run() == .opened)
        #expect(app.presses == [false])
    }

    @Test func pressOfAGoneItemFails() {
        let app = Pretend()
        app.running = false
        #expect(app.run() == .gone)
        // No Accessibility call at all: nothing read, nothing pressed.
        #expect(app.snapshots == 0)
        #expect(app.presses.isEmpty)
    }

    @Test func theElementsPressOpens() {
        let app = Pretend()
        app.opensOnElement = [3]
        #expect(app.run() == .opened)
        #expect(app.presses == [false])
    }

    @Test func theWrapperIsPressedOnceWhenTheElementOpensNothing() {
        let app = Pretend()
        app.opensOnWrapper = [4]
        #expect(app.run() == .wrapperOpened)
        #expect(app.presses == [false, true])
    }

    @Test func nothingOpensBringsTheAppForward() {
        let app = Pretend()
        #expect(app.run() == .broughtForward)
        #expect(app.presses == [false, true])
        let bare = Pretend()
        #expect(bare.run(wrapper: false) == .broughtForward)
        #expect(bare.presses == [false])
    }

    @Test func withoutAccessibilityNothingIsPressed() {
        let app = Pretend()
        #expect(app.run(trusted: false) == .broughtForward)
        #expect(app.presses.isEmpty)
        #expect(app.snapshots == 0)
    }

    @Test func aLateOpeningIsNotPressedAgain() {
        // The element's menu came up after the wait: pressing the wrapper
        // would only close it.
        let app = Pretend()
        var probes = 0
        let outcome = TrayPress.run(
            wrapper: true, trusted: true, isRunning: { true },
            snapshot: {
                probes += 1
                // The first read is "before"; the menu shows from the third.
                return TrayPress.Snapshot(elements: probes >= 3 ? [1, 2, 5] : [1, 2], windows: [])
            },
            press: { app.presses.append($0) },
            within: { probe in probe() })
        #expect(outcome == .opened)
        #expect(app.presses == [false])
    }
}
