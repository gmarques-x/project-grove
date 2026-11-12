import CoreGraphics
import Foundation
import Testing
@testable import GroveKeysCore

/// The numbers are the ones measured on 2026-11-12 on the built-in display
/// (1920 × 1243 pt): see the spec, §5.
@Suite struct BarPanelGeometryTests {
    static let screen = CGRect(x: 0, y: 0, width: 1920, height: 1243)
    /// The `borders` windows as the window list gave them: three tiled
    /// windows on the workspace, and two parked with their hidden workspaces.
    static let borderWindows = [
        CGRect(x: -5, y: 39, width: 974, height: 1208),
        CGRect(x: 951, y: 39, width: 974, height: 613),
        CGRect(x: 951, y: 634, width: 974, height: 613),
        CGRect(x: 1906, y: 1178, width: 1132, height: 729),
        CGRect(x: 1906, y: 1189, width: 1930, height: 1209),
    ]
    static let measured = BorderLines(top: 49.5, left: 5.5, right: 1914.5)
    static let fallback = WindowBorders.fallback(screen: screen, notchInset: 37.5, width: 5)

    static func place(_ width: Double, _ height: Double = 300, _ anchor: BarPanelAnchor = .trailing,
                      pill: CGRect?, lines: BorderLines = measured) -> BarPanelPlacement {
        .place(size: CGSize(width: width, height: height), anchor: anchor, pill: pill, lines: lines, bottom: 1235)
    }

    // MARK: The lines

    @Test func theBordersWidthIsReadFromBordersrc() {
        let text = "# JankyBorders\nborders active_color=0xffA7C080 inactive_color=0xff475258 width=5.0 style=round hidpi=on\n"
        #expect(WindowBorders.width(bordersrc: text) == 5)
        #expect(WindowBorders.width(bordersrc: "borders width=6.0 style=round") == 6)
        #expect(WindowBorders.width(bordersrc: "# width=9.0\nborders style=round") == 5)
        #expect(WindowBorders.width(bordersrc: "borders width=wide") == 5)
        #expect(WindowBorders.width(bordersrc: "borders width=0") == 5)
        #expect(WindowBorders.width(bordersrc: nil) == 5)
    }

    @Test func aBordersOuterEdgeIsItsWindowInsetByThePaddingAndHalfTheWidth() {
        // The left window is at x 8, y 52, 948 × 1182: its border shows 2.5 pt outside.
        #expect(WindowBorders.outerRect(ofBorderWindow: Self.borderWindows[0], width: 5)
            == CGRect(x: 5.5, y: 49.5, width: 953, height: 1187))
        #expect(WindowBorders.reach(width: 5) == 2.5)
        #expect(WindowBorders.cornerRadius(width: 5) == 18.5)
        // A width of 6 would put the lines on whole points.
        #expect(WindowBorders.outerRect(ofBorderWindow: CGRect(x: -6, y: 38, width: 976, height: 1210), width: 6)
            == CGRect(x: 5, y: 49, width: 954, height: 1188))
    }

    @Test func theLinesAreTheTopRowsOuterEdges() {
        let lines = WindowBorders.lines(borderWindows: Self.borderWindows, width: 5, screen: Self.screen,
                                        fallback: BorderLines(top: 0, left: 0, right: 0))
        #expect(lines == Self.measured)
    }

    @Test func theFallbackIsTheConfiguredGapsLessTheBordersReach() {
        // Built-in: the notch keeps 37.5, AeroSpace adds 14 and lands on 52.
        #expect(Self.fallback == Self.measured)
        // Elsewhere the windows start at 51.
        let external = CGRect(x: 1920, y: -200, width: 2560, height: 1440)
        #expect(WindowBorders.fallback(screen: external, notchInset: 0, width: 5)
            == BorderLines(top: -151.5, left: 1925.5, right: 4474.5))
        // A border wide enough to reach the strip stops at it.
        #expect(WindowBorders.fallback(screen: Self.screen, notchInset: 0, width: 10).top == 48)
    }

    @Test func withoutATiledWindowTheLinesAreTheFallback() {
        // Nothing on the workspace but the parked ones.
        #expect(WindowBorders.lines(borderWindows: Array(Self.borderWindows[3...]), width: 5, screen: Self.screen,
                                    fallback: Self.fallback) == Self.fallback)
        // A floating window alone, in the middle.
        #expect(WindowBorders.lines(borderWindows: [CGRect(x: 500, y: 300, width: 800, height: 600)], width: 5,
                                    screen: Self.screen, fallback: Self.fallback) == Self.fallback)
        #expect(WindowBorders.lines(borderWindows: [], width: 5, screen: Self.screen, fallback: Self.fallback)
            == Self.fallback)
    }

    @Test func aTopRowThatStopsShortOfASideKeepsTheFallbackThere() {
        // One window, on the right half only.
        let fallback = BorderLines(top: 49.5, left: 7, right: 1913)
        let lines = WindowBorders.lines(borderWindows: [Self.borderWindows[1]], width: 5, screen: Self.screen,
                                        fallback: fallback)
        #expect(lines == BorderLines(top: 49.5, left: 7, right: 1914.5))
    }

    @Test func aSecondScreensWindowsAreNotThisScreens() {
        let other = CGRect(x: 1915, y: 39, width: 974, height: 613)   // on a display to the right
        #expect(WindowBorders.lines(borderWindows: [other], width: 5, screen: Self.screen, fallback: Self.fallback)
            == Self.fallback)
    }

    // MARK: Placement

    @Test func aRightSidePanelsRightEdgeIsItsPillsRightOutline() {
        // CPU & memory: its pill is x 1486 to 1620.
        let system = Self.place(300, 520, pill: CGRect(x: 1486, y: 0, width: 134, height: 48))
        #expect(system.frame == CGRect(x: 1320, y: 49.5, width: 300, height: 520))
        #expect(!system.followsLeft && !system.followsRight)
    }

    @Test func theTopEdgeIsTheBordersTopLine() {
        for pill in [CGRect(x: 1486, y: 0, width: 134, height: 48), CGRect(x: 1764, y: 0, width: 150, height: 48)] {
            #expect(Self.place(248, pill: pill).frame.minY == 49.5)
        }
    }

    @Test func theLastPillsPanelTakesTheBordersSideLineAndItsCorner() {
        // The clock's pill once the bar's end gap is 6: x 1764 to 1914, half a point inside the line.
        let clock = Self.place(248, 262, pill: CGRect(x: 1764, y: 0, width: 150, height: 48))
        #expect(clock.frame == CGRect(x: 1666.5, y: 49.5, width: 248, height: 262))
        #expect(clock.followsRight && !clock.followsLeft)
        // The pine's pill: x 6 to 50.
        let grove = Self.place(190, 240, .leading, pill: CGRect(x: 6, y: 0, width: 44, height: 48))
        #expect(grove.frame == CGRect(x: 5.5, y: 49.5, width: 190, height: 240))
        #expect(grove.followsLeft && !grove.followsRight)
    }

    @Test func aPillFurtherInKeepsItsOwnEdge() {
        // The bar as it was (end gaps 8 + 4): the clock's pill ended at 1908, the pine's began at 12.
        let clock = Self.place(248, pill: CGRect(x: 1758, y: 0, width: 150, height: 48))
        #expect(clock.frame.maxX == 1908)
        #expect(!clock.followsRight)
        let grove = Self.place(190, 240, .leading, pill: CGRect(x: 12, y: 0, width: 44, height: 48))
        #expect(grove.frame.minX == 12)
        #expect(!grove.followsLeft)
    }

    @Test func withoutThePillThePanelHangsFromTheLineOnItsSide() {
        #expect(Self.place(248, pill: nil).frame.maxX == 1914.5)
        #expect(Self.place(248, pill: nil).followsRight)
        #expect(Self.place(190, 240, .leading, pill: nil).frame.minX == 5.5)
    }

    @Test func aPanelStaysBetweenTheLinesAndAboveTheBottomGap() {
        // A pill near the left end with a panel wider than the room to its left.
        let moved = Self.place(300, pill: CGRect(x: 60, y: 0, width: 100, height: 48))
        #expect(moved.frame.minX == 5.5)
        #expect(moved.followsLeft)
        // Too tall: cut at the bottom gap.
        let tall = Self.place(248, 2000, pill: nil)
        #expect(tall.frame.maxY == 1235)
    }

    @Test func theWindowIsThePanelGrownToWholePoints() {
        let clock = Self.place(248, 262, pill: CGRect(x: 1764, y: 0, width: 150, height: 48))
        #expect(clock.window.frame == CGRect(x: 1666, y: 49, width: 249, height: 263))
        #expect(clock.window.inset == CGPoint(x: 0.5, y: 0.5))
        let system = Self.place(300, 520, pill: CGRect(x: 1486, y: 0, width: 134, height: 48))
        #expect(system.window.frame == CGRect(x: 1320, y: 49, width: 300, height: 521))
        #expect(system.window.inset == CGPoint(x: 0, y: 0.5))
    }

    // MARK: The bar's answer

    @Test func aPillsRectangleIsReadFromTheBarsQuery() {
        let json = """
        {"name": "pill.clock", "type": "bracket",
         "bounding_rects": {"display-1": {"origin": [1758.0, 0.0], "size": [150.0, 48.0]},
                            "display-2": {"origin": [4318.0, -200.0], "size": [150.0, 48.0]}}}
        """
        #expect(BarQuery.rects(json: json) == [1: CGRect(x: 1758, y: 0, width: 150, height: 48),
                                               2: CGRect(x: 4318, y: -200, width: 150, height: 48)])
        #expect(BarQuery.rects(json: "{\"bounding_rects\": {}}").isEmpty)
        #expect(BarQuery.rects(json: "{\"bounding_rects\": {\"display-1\": {\"origin\": [0, 0], \"size\": [0, 0]}}}").isEmpty)
        #expect(BarQuery.rects(json: "[bracket] Bracket not found").isEmpty)
        #expect(BarQuery.rects(json: "").isEmpty)
    }

    // MARK: Held to the config files (skipped outside the repo)

    static let dotfiles = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("grove-dotfiles/config")

    @Test func theFallbacksNumbersAreTheConfigFiles() throws {
        guard let aerospace = try? String(contentsOf: Self.dotfiles.appendingPathComponent("aerospace/aerospace.base.toml"),
                                          encoding: .utf8),
              let borders = try? String(contentsOf: Self.dotfiles.appendingPathComponent("borders/bordersrc.tmpl"),
                                        encoding: .utf8),
              let bar = try? String(contentsOf: Self.dotfiles.appendingPathComponent("sketchybar/sketchybarrc"),
                                    encoding: .utf8) else { return }
        func number(_ value: Double) -> String { String(Int(value)) }
        #expect(aerospace.contains("gaps.outer.left = \(number(WindowBorders.sideGap))\n"))
        #expect(aerospace.contains("gaps.outer.right = \(number(WindowBorders.sideGap))\n"))
        #expect(aerospace.contains("gaps.outer.bottom = \(number(WindowBorders.bottomGap))\n"))
        #expect(aerospace.contains("gaps.outer.top = [{ monitor.\"built-in\" = \(number(WindowBorders.topGapBuiltIn)) }, \(number(WindowBorders.topGap))]"))
        #expect(WindowBorders.width(bordersrc: borders) == WindowBorders.defaultWidth)
        #expect(borders.contains("width=5.0"))
        #expect(bar.contains("--bar height=\(number(WindowBorders.stripHeight)) "))
    }
}
