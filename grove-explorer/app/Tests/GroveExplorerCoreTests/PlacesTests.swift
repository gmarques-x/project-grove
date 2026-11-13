import Foundation
@testable import GroveExplorerCore
import Testing

/// The sidebar's rules that need no window: which row is lit, how wide the
/// sidebar is, and where the divider between the panes may stand.
@Suite struct PlacesTests {
    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    // MARK: The lit row

    @Test func theLitPlaceIsTheNearestOneAboveTheFolder() {
        let places = [folder("/Applications"), folder("/Users/me"), folder("/Users/me/Developer"), folder("/Users/me/Documents")]
        #expect(Places.nearest(above: folder("/Users/me/Developer/project-grove"), among: places) == 2)
        #expect(Places.nearest(above: folder("/Users/me/Music"), among: places) == 1)
        #expect(Places.nearest(above: folder("/Users/me/Documents"), among: places) == 3)
        #expect(Places.nearest(above: folder("/Applications/Utilities"), among: places) == 0)
    }

    @Test func aFolderUnderNoPlaceLightsNone() {
        let places = [folder("/Applications"), folder("/Users/me")]
        #expect(Places.nearest(above: folder("/usr/local"), among: places) == nil)
        #expect(Places.nearest(above: folder("/Users"), among: places) == nil)
        #expect(Places.nearest(above: folder("/Users/me"), among: []) == nil)
    }

    @Test func aNameThatOnlyStartsLikeAPlaceIsNotUnderIt() {
        let places = [folder("/Users/me/Dev")]
        #expect(Places.nearest(above: folder("/Users/me/Developer"), among: places) == nil)
    }

    @Test func theRootIsAboveEverythingAndPathsAreComparedAsFolders() {
        let places = [folder("/"), folder("/Volumes/Backup")]
        #expect(Places.nearest(above: folder("/usr/local"), among: places) == 0)
        #expect(Places.nearest(above: folder("/Volumes/Backup/photos"), among: places) == 1)
        #expect(Places.nearest(above: URL(fileURLWithPath: "/Volumes/Backup/a/../b/"), among: places) == 1)
        #expect(Places.nearest(above: folder("/"), among: places) == 0)
    }

    @Test func ofTwoPlacesOnTheSameFolderTheFirstIsLit() {
        let places = [folder("/Users/me"), folder("/Users/me")]
        #expect(Places.nearest(above: folder("/Users/me/x"), among: places) == 0)
    }

    @Test func aCloudPlaceInsideHomeIsLitOverHome() {
        let drive = "/Users/me/Library/Mobile Documents/com~apple~CloudDocs"
        let places = [folder("/Users/me"), folder(drive), folder("/")]
        #expect(Places.nearest(above: folder(drive), among: places) == 1)
        #expect(Places.nearest(above: folder(drive + "/Notes"), among: places) == 1)
        #expect(Places.nearest(above: folder("/Users/me/Library"), among: places) == 0)
    }

    // MARK: The sidebar's width

    @Test func theSidebarIsFullWhileEachPaneKeeps430Points() {
        // The mock-ups' windows: 1904 with two panes, 948 with one.
        #expect(SidebarLayout.mode(windowWidth: 1904, panes: 2, hidden: false) == .full)
        #expect(SidebarLayout.mode(windowWidth: 948, panes: 1, hidden: false) == .full)
        // 200 + a line + 430: the narrowest one pane beside the full sidebar.
        #expect(SidebarLayout.mode(windowWidth: 631, panes: 1, hidden: false) == .full)
        #expect(SidebarLayout.mode(windowWidth: 630, panes: 1, hidden: false) == .rail)
    }

    @Test func theSidebarIsARailWhenThePanesWouldBeUnder430() {
        // Half width with two panes: 373 pt each beside the full sidebar, 449 beside the rail.
        #expect(SidebarLayout.mode(windowWidth: 948, panes: 2, hidden: false) == .rail)
        // 200 + 2 lines + 2 × 430.
        #expect(SidebarLayout.mode(windowWidth: 1062, panes: 2, hidden: false) == .full)
        #expect(SidebarLayout.mode(windowWidth: 1061, panes: 2, hidden: false) == .rail)
    }

    @Test func aHiddenSidebarIsHiddenAtAnyWidth() {
        #expect(SidebarLayout.mode(windowWidth: 1904, panes: 2, hidden: true) == .hidden)
        #expect(SidebarLayout.mode(windowWidth: 400, panes: 2, hidden: true) == .hidden)
    }

    @Test func eachModeHasItsWidthAndTheLineAfterIt() {
        #expect(SidebarLayout.Mode.full.width == 200)
        #expect(SidebarLayout.Mode.rail.width == 48)
        #expect(SidebarLayout.Mode.hidden.width == 0)
        // What is left for the panes and the line between them.
        #expect(SidebarLayout.panesWidth(windowWidth: 948, mode: .rail) == 899)
        #expect(SidebarLayout.panesWidth(windowWidth: 948, mode: .full) == 747)
        #expect(SidebarLayout.panesWidth(windowWidth: 948, mode: .hidden) == 948)
    }

    // MARK: The divider

    @Test func theLeftPaneTakesItsShareOfWhatTheLineLeaves() {
        #expect(SidebarLayout.leftPaneWidth(panesWidth: 899, split: 0.5) == 449)
        #expect(SidebarLayout.leftPaneWidth(panesWidth: 1001, split: 0.25) == 250)
    }

    @Test func aDraggedDividerStopsWhereAPaneWouldGetTooNarrow() {
        // 1001 pt for two panes and their line: each keeps 240 at least.
        #expect(SidebarLayout.split(leftWidth: 500, panesWidth: 1001) == 0.5)
        #expect(SidebarLayout.split(leftWidth: 10, panesWidth: 1001) == 0.24)
        #expect(SidebarLayout.split(leftWidth: 990, panesWidth: 1001) == 0.76)
    }

    @Test func inAWindowTooNarrowForTwoSmallestPanesTheSplitIsEven() {
        #expect(SidebarLayout.split(leftWidth: 10, panesWidth: 400) == 0.5)
    }

    @Test func aSplitFromAFileIsBroughtIntoRange() {
        #expect(SidebarLayout.clamped(split: 0.5) == 0.5)
        #expect(SidebarLayout.clamped(split: -3) == 0.1)
        #expect(SidebarLayout.clamped(split: 7) == 0.9)
        #expect(SidebarLayout.clamped(split: .nan) == 0.5)
    }
}
