import GroveThemesCore
import SwiftUI

// The bar panels' drawings: a history chart, a meter of one or more parts
// with its legend, the cores' bars. Their geometry is pure and tested
// (`SparklineGeometry`, `MeterGeometry`). None is ever drawn in orange: that
// is the panel's outline.

/// Where a chart's points go.
public enum SparklineGeometry {
    /// The points of `values` (each 0...1, oldest first) across `size`: the
    /// first at the left edge, the last at the right, 0 half a point above
    /// the bottom and 1 half a point below the top, so a 1 pt line at either
    /// end stays inside. A value outside 0...1 (or not a number) is held to
    /// the nearest end. Fewer than two values: no points, nothing to join.
    public static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let last = CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / last,
                    y: (size.height - 1) * (1 - MeterGeometry.fraction(value)) + 0.5)
        }
    }

    /// A rate (or any unbounded reading) on a chart's 0...1: against `top`,
    /// the largest of the readings shown and of `floor`, so a quiet minute
    /// isn't stretched to the full height.
    public static func normalized(_ values: [Double], floor: Double) -> [Double] {
        let top = max(floor, values.max() ?? 0)
        guard top > 0 else { return values.map { _ in 0 } }
        return values.map { MeterGeometry.fraction($0 / top) }
    }
}

/// How a meter's parts share its length.
public enum MeterGeometry {
    /// A share held to 0...1; not a number is 0.
    public static func fraction(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0 }
        return CGFloat(min(1, max(0, value)))
    }

    /// Each part's width on a track `width` long, left to right. Shares are
    /// held to 0...1, and once the track is full the rest get nothing: parts
    /// that add up to more than the whole never draw past its end.
    public static func widths(_ shares: [Double], in width: CGFloat) -> [CGFloat] {
        var left = CGFloat(1)
        return shares.map { share in
            let part = min(fraction(share), left)
            left -= part
            return width * part
        }
    }
}

/// One line of a `Sparkline`.
public struct SparklineSeries {
    /// 0...1, oldest first, newest at the right.
    public var values: [Double]
    public var accent: RGB

    public init(_ values: [Double], accent: RGB) {
        self.values = values
        self.accent = accent
    }
}

/// A small history chart: one or two lines over a 1 pt baseline, a fixed
/// height, as wide as it is given. Hidden from VoiceOver: the number beside
/// it says the reading.
public struct Sparkline: View {
    let series: [SparklineSeries]
    let height: CGFloat
    @Environment(\.theme) private var theme

    public init(_ series: [SparklineSeries], height: CGFloat = PanelMetrics.chart) {
        self.series = series
        self.height = height
    }

    /// One line.
    public init(_ values: [Double], accent: RGB, height: CGFloat = PanelMetrics.chart) {
        self.init([SparklineSeries(values, accent: accent)], height: height)
    }

    public var body: some View {
        Canvas { context, size in
            for line in series {
                let points = SparklineGeometry.points(line.values, in: size)
                guard let first = points.first else { continue }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(Color(line.accent)),
                               style: StrokeStyle(lineWidth: PanelMetrics.chartLine, lineJoin: .round))
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .accessibilityHidden(true)
    }
}

/// One part of a `PanelMeter`.
public struct MeterPart {
    /// Its share of the whole, 0...1.
    public var share: Double
    public var accent: RGB
    /// For the legend ("app"); nil for a part without an entry.
    public var name: String?
    /// The legend's value ("8.1").
    public var value: String?

    public init(share: Double, accent: RGB, name: String? = nil, value: String? = nil) {
        self.share = share
        self.accent = accent
        self.name = name
        self.value = value
    }
}

/// A horizontal meter on a track: one part (a charge, a progress) or several
/// side by side (memory's app, wired and compressed). What is left of the
/// track is the rest (free).
public struct PanelMeter: View {
    let parts: [MeterPart]
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    public init(_ parts: [MeterPart]) { self.parts = parts }

    /// One part.
    public init(share: Double, accent: RGB) {
        self.init([MeterPart(share: share, accent: accent)])
    }

    public var body: some View {
        GeometryReader { geo in
            let widths = MeterGeometry.widths(parts.map(\.share), in: geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Rectangle().fill(Color(part.accent)).frame(width: widths[index])
                }
            }
        }
        .frame(height: PanelMetrics.meter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.selectedFill(on: surface))
        .clipShape(RoundedRectangle(cornerRadius: GroveRadius.inline))
        .lightOutline(cornerRadius: GroveRadius.inline)
        .accessibilityHidden(true)
    }
}

/// The legend under a `PanelMeter` of several parts: a swatch, the name
/// quiet and the value in fg for each part that has a name, then `rest`
/// (the track's own colour: "free").
public struct PanelLegend: View {
    let parts: [MeterPart]
    let rest: (name: String, value: String)?
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    public init(_ parts: [MeterPart], rest: (name: String, value: String)? = nil) {
        self.parts = parts
        self.rest = rest
    }

    public var body: some View {
        HStack(spacing: GroveSpace.s8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if let name = part.name { entry(Color(part.accent), name, part.value ?? "") }
            }
            if let rest { entry(theme.selectedFill(on: surface), rest.name, rest.value) }
        }
        .font(GroveFont.mono(GroveType.finePrint))
        .lineLimit(1)
    }

    private func entry(_ color: Color, _ name: String, _ value: String) -> some View {
        HStack(spacing: GroveSpace.s4) {
            Rectangle().fill(color).frame(width: GroveSpace.s8, height: GroveSpace.s8)
                .lightOutline(cornerRadius: 0)
            (Text(name).foregroundColor(theme.quiet) + Text(verbatim: " " + value)).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A group of cores as small vertical bars over its caption ("Performance"):
/// each bar a core's load, 0...1, at least a point high so an idle core
/// still shows.
public struct CoreBars: View {
    let caption: String
    let loads: [Double]
    let accent: RGB
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    public init(_ caption: String, loads: [Double], accent: RGB) {
        self.caption = caption
        self.loads = loads
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s4) {
            HStack(alignment: .bottom, spacing: GroveSpace.s2) {
                ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
                    Rectangle().fill(theme.selectedFill(on: surface))
                        .frame(width: PanelMetrics.coreBar.width, height: PanelMetrics.coreBar.height)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(accent))
                                .frame(height: max(1, PanelMetrics.coreBar.height * MeterGeometry.fraction(load)))
                        }
                        .lightOutline(cornerRadius: 0)
                }
            }
            PanelCaption(caption)
        }
        .accessibilityElement().accessibilityLabel("\(caption) cores")
    }
}
