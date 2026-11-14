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
    /// What a real click adds; `clickable` false: the click can't be made.
    var opensOnClick: [Int] = []
    var clickable = true
    var presses: [Bool] = []
    var clicks = 0
    var snapshots = 0

    func run(wrapper: Bool = true, trusted: Bool = true, clicks canClick: Bool = false,
             clickFirst: Bool = false) -> TrayPress.Outcome {
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
            within: { probe in probe() },
            click: canClick ? {
                self.clicks += 1
                guard self.clickable else { return false }
                self.windows += self.opensOnClick
                return true
            } : nil,
            clickFirst: clickFirst)
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

    // MARK: The real click (OneDrive's item ignores presses)

    @Test func theClickIsTheLastTryAfterBothPresses() {
        let app = Pretend()
        app.opensOnClick = [77]
        #expect(app.run(clicks: true) == .clicked)
        #expect(app.presses == [false, true])
        #expect(app.clicks == 1)
        let bare = Pretend()
        bare.opensOnClick = [77]
        #expect(bare.run(wrapper: false, clicks: true) == .clicked)
        #expect(bare.presses == [false])
    }

    @Test func noClickWhenAPressOpened() {
        let app = Pretend()
        app.opensOnElement = [3]
        app.opensOnClick = [77]
        #expect(app.run(clicks: true) == .opened)
        #expect(app.clicks == 0)
        let wrapped = Pretend()
        wrapped.opensOnWrapper = [4]
        #expect(wrapped.run(clicks: true) == .wrapperOpened)
        #expect(wrapped.clicks == 0)
    }

    @Test func aClickThatOpensNothingOrCantBeMadeBringsTheAppForward() {
        let app = Pretend()
        #expect(app.run(clicks: true) == .broughtForward)
        #expect(app.clicks == 1)
        let blocked = Pretend()
        blocked.clickable = false
        blocked.opensOnClick = [77]
        #expect(blocked.run(clicks: true) == .broughtForward)
        #expect(blocked.clicks == 1)
    }

    @Test func clickFirstSkipsThePresses() {
        let app = Pretend()
        app.opensOnClick = [77]
        #expect(app.run(clicks: true, clickFirst: true) == .clicked)
        #expect(app.presses.isEmpty)
        #expect(app.clicks == 1)
    }

    @Test func clickFirstFallsBackToThePressesOnce() {
        // Clicked first, nothing opened: the presses as usual, no second click.
        let app = Pretend()
        app.opensOnWrapper = [4]
        #expect(app.run(clicks: true, clickFirst: true) == .wrapperOpened)
        #expect(app.presses == [false, true])
        let none = Pretend()
        #expect(none.run(clicks: true, clickFirst: true) == .broughtForward)
        #expect(none.clicks == 1)
        #expect(none.presses == [false, true])
    }

    @Test func withoutAccessibilityNothingIsClicked() {
        let app = Pretend()
        app.opensOnClick = [77]
        #expect(app.run(trusted: false, clicks: true, clickFirst: true) == .broughtForward)
        #expect(app.clicks == 0)
        app.running = false
        #expect(app.run(clicks: true) == .gone)
        #expect(app.clicks == 0)
    }
}

struct StatusItemClickTests {
    @Test func theMiddleOfTheFrame() {
        #expect(StatusItemClick.point(frame: CGRect(x: 1550, y: 7, width: 38, height: 24)) == CGPoint(x: 1569, y: 19))
        #expect(StatusItemClick.point(frame: nil) == nil)
        #expect(StatusItemClick.point(frame: CGRect(x: 10, y: 0, width: 0, height: 24)) == nil)
        #expect(StatusItemClick.point(frame: .null) == nil)
    }

    @Test func reachableOnlyWhenTheMenuBarIsOnTop() {
        let point = CGPoint(x: 1569, y: 19)
        let menuBar = StatusItemClick.Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1920, height: 38))
        let groveBar = StatusItemClick.Window(layer: 25, bounds: CGRect(x: 0, y: 0, width: 1920, height: 48))
        let desktop = StatusItemClick.Window(layer: -2_147_483_603, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1243))
        #expect(StatusItemClick.reachable(point, windows: [menuBar, desktop]))
        // The Grove bar still over it.
        #expect(!StatusItemClick.reachable(point, windows: [groveBar, menuBar, desktop]))
        // A window over the bar elsewhere doesn't matter.
        let aside = StatusItemClick.Window(layer: 101, bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        #expect(StatusItemClick.reachable(point, windows: [aside, menuBar, desktop]))
        // No menu bar there (hidden): the desktop is no target.
        #expect(!StatusItemClick.reachable(point, windows: [desktop]))
        #expect(!StatusItemClick.reachable(point, windows: []))
    }

    @Test func theBarsHiddenState() {
        #expect(StatusItemClick.barHidden(json: #"{"position": "top", "hidden": "off"}"#) == false)
        #expect(StatusItemClick.barHidden(json: #"{"hidden": "on"}"#) == true)
        #expect(StatusItemClick.barHidden(json: #"{"hidden": "maybe"}"#) == nil)
        #expect(StatusItemClick.barHidden(json: "not json") == nil)
        #expect(StatusItemClick.barHidden(json: "{}") == nil)
    }
}
