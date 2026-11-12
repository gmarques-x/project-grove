import Foundation
import Testing
@testable import GroveUI

@Suite struct PanelChartsTests {
    // MARK: SparklineGeometry

    @Test func aChartsPointsRunEdgeToEdgeAndStayInside() {
        let points = SparklineGeometry.points([0, 0.5, 1], in: CGSize(width: 200, height: 24))
        #expect(points.map(\.x) == [0, 100, 200])
        // 0 is half a point above the bottom, 1 half a point below the top.
        #expect(points.map(\.y) == [23.5, 12, 0.5])
    }

    @Test func aChartHoldsReadingsToItsHeight() {
        let points = SparklineGeometry.points([-1, 2, .nan, .infinity], in: CGSize(width: 30, height: 11))
        #expect(points.map(\.y) == [10.5, 0.5, 10.5, 10.5])
        #expect(points.map(\.x) == [0, 10, 20, 30])
    }

    @Test func oneReadingOrNoneIsNoLine() {
        #expect(SparklineGeometry.points([], in: CGSize(width: 100, height: 24)).isEmpty)
        #expect(SparklineGeometry.points([0.4], in: CGSize(width: 100, height: 24)).isEmpty)
    }

    @Test func ratesAreDrawnAgainstTheLargestShownOrTheFloor() {
        #expect(SparklineGeometry.normalized([0, 50, 200], floor: 100) == [0, 0.25, 1])
        // A quiet minute isn't stretched to the full height.
        #expect(SparklineGeometry.normalized([0, 10, 20], floor: 100) == [0, 0.1, 0.2])
        #expect(SparklineGeometry.normalized([0, 0], floor: 0) == [0, 0])
        #expect(SparklineGeometry.normalized([], floor: 100).isEmpty)
    }

    // MARK: MeterGeometry

    @Test func aShareIsHeldToTheWhole() {
        #expect(MeterGeometry.fraction(0.78) == 0.78)
        #expect(MeterGeometry.fraction(-0.2) == 0)
        #expect(MeterGeometry.fraction(1.4) == 1)
        #expect(MeterGeometry.fraction(.nan) == 0)
        #expect(MeterGeometry.fraction(.infinity) == 0)
    }

    @Test func aMetersPartsShareItsLength() {
        // Memory: app, wired, compressed of 24 GB; free is what is left.
        #expect(MeterGeometry.widths([0.25, 0.125, 0.125], in: 200) == [50, 25, 25])
        #expect(MeterGeometry.widths([0.78], in: 100) == [78])
        #expect(MeterGeometry.widths([], in: 100).isEmpty)
    }

    @Test func partsNeverDrawPastTheTracksEnd() {
        #expect(MeterGeometry.widths([0.75, 0.5, 0.25], in: 100) == [75, 25, 0])
        #expect(MeterGeometry.widths([2, 0.5], in: 100) == [100, 0])
        #expect(MeterGeometry.widths([-1, 0.5], in: 100) == [0, 50])
    }
}
