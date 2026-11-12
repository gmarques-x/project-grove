import Foundation
import GroveThemesCore
import Testing
@testable import GroveKeysCore

@Suite struct BarPanelStateTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aLinkShowsThePanelAndASecondPutsItAway() {
        var toggle = BarPanelToggle()
        #expect(toggle.toggle("clock", now: Self.t0) == .open("clock", closing: nil))
        #expect(toggle.open == "clock")
        #expect(toggle.toggle("clock", now: Self.t0 + 3) == .close("clock"))
        #expect(toggle.open == nil)
        // And a third shows it again, however soon.
        #expect(toggle.toggle("clock", now: Self.t0 + 3.1) == .open("clock", closing: nil))
    }

    @Test func showingOnePutsAwayTheOther() {
        var toggle = BarPanelToggle()
        _ = toggle.toggle("clock", now: Self.t0)
        #expect(toggle.toggle("wifi", now: Self.t0 + 1) == .open("wifi", closing: "clock"))
        #expect(toggle.open == "wifi")
    }

    @Test func theClickOnItsOwnPillDoesNotShowItAgain() {
        var toggle = BarPanelToggle()
        _ = toggle.toggle("clock", now: Self.t0)
        // The click is first a click outside the panel…
        toggle.dismissedFromOutside(now: Self.t0 + 5)
        #expect(toggle.open == nil)
        // …then the pill's link arrives.
        #expect(toggle.toggle("clock", now: Self.t0 + 5.12) == .nothing)
        #expect(toggle.open == nil)
        // The next click is a new one.
        #expect(toggle.toggle("clock", now: Self.t0 + 5.3) == .open("clock", closing: nil))
    }

    @Test func aClickOutsideThenALaterOrAnotherLinkShowsAsUsual() {
        var toggle = BarPanelToggle()
        _ = toggle.toggle("clock", now: Self.t0)
        toggle.dismissedFromOutside(now: Self.t0 + 5)
        #expect(toggle.toggle("clock", now: Self.t0 + 5.5) == .open("clock", closing: nil))

        // A click on another pill: outside this panel, then that pill's link.
        toggle.dismissedFromOutside(now: Self.t0 + 9)
        #expect(toggle.toggle("battery", now: Self.t0 + 9.1) == .open("battery", closing: nil))
    }

    @Test func anyOtherClosingForgetsTheClick() {
        var toggle = BarPanelToggle()
        _ = toggle.toggle("clock", now: Self.t0)
        toggle.closed()   // Escape
        #expect(toggle.open == nil)
        #expect(toggle.toggle("clock", now: Self.t0 + 0.1) == .open("clock", closing: nil))
        // Nothing open: a click outside is nothing to remember.
        var idle = BarPanelToggle()
        idle.dismissedFromOutside(now: Self.t0)
        #expect(idle.toggle("clock", now: Self.t0 + 0.1) == .open("clock", closing: nil))
    }

    @Test func theOpenPanelsFileIsBesideTheThemeState() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(BarPanelFile.url(environment: [:], home: home).path == "/Users/someone/.local/state/grove/bar-panel")
        #expect(BarPanelFile.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/bar-panel")
    }

    @Test func onlyABarItemsNameIsHandedToTheBar() {
        for name in ["pill.clock", "pill.sys", "pill.ws.1", "front_app"] { #expect(BarPanelFile.isItemName(name)) }
        for name in ["", "pill clock", "pill.clock;rm", "Pill.Clock", "pill/clock", "--set", String(repeating: "a", count: 41)] {
            #expect(!BarPanelFile.isItemName(name), "\(name)")
        }
    }

    @Test func coloursAreWrittenAsTheBarReadsThem() throws {
        let hover = try #require(RGB(hex: "#343F44")), bg0 = try #require(RGB(hex: "#2D353B"))
        #expect(BarPanelFile.argb(hover) == "0xff343f44")
        #expect(BarPanelFile.transparent(bg0) == "0x002d353b")
    }
}
