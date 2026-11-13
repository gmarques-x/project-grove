import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// CPU & memory, stacked (variant A of the approved mock-ups; spec
// 2026-11-12-bar-panels-design §6): "is something eating my Mac?". The
// readings are SystemSampler's, what is made of them GroveKeysCore's
// (SystemStats).

/// The CPU & memory panel's state. `start()` at each opening, `stop()` at each
/// closing; `.sample` is fixed data for `--render-panel`.
@MainActor
final class SystemModel: ObservableObject, BarPanelModel {
    /// Everything the panel draws, published as one value a sample.
    struct Shown {
        /// The whole CPU's load, 0...1; nil until the second sample of an
        /// opening (half a second in): a load is the difference of two.
        var cpu: Double?
        var cores: [SystemCoreGroup]
        /// Nil until the first sample arrives (a few milliseconds).
        var topCPU: [SystemTopRow]?
        var memory: SystemMemory?
        var pressure = SystemPressure.normal
        /// Bytes of swap in use; its row shows only above zero.
        var swap: UInt64 = 0
        var topMemory: [SystemTopRow]?
        /// "up 6h 53m · load 1.86".
        var note: String?
        var cpuHistory = SystemHistory()
        var memoryHistory = SystemHistory()
        /// The charts' right edge, on the sampler's clock.
        var now = 0.0
    }

    /// How many processes each list names.
    static let top = 3

    @Published private(set) var shown: Shown
    /// What Return does: the footer's action (the view sets it, the host's
    /// actions being its to reach).
    var activate: (() -> Void)?
    private let layout: SystemCoreLayout
    private var coreCount: Int
    private var sampler: SystemSampler?
    /// Counts the openings, to tell a late sample of an earlier one.
    private var opening = 0

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            layout = SystemProbe.coreLayout()
            coreCount = ProcessInfo.processInfo.activeProcessorCount
            shown = Shown(cores: layout.groups(Array(repeating: 0, count: coreCount)))
        case .sample:
            // The mock-ups' Mac. GROVE_SYSTEM_SAMPLE picks another state:
            // `pressed`, `critical`, `starting`, `reopened`, `cores`.
            let state = ProcessInfo.processInfo.environment["GROVE_SYSTEM_SAMPLE"] ?? ""
            layout = state == "cores" ? SystemCoreLayout(performance: 0, efficiency: 0)
                : SystemCoreLayout(performance: 4, efficiency: 6)
            coreCount = 10
            shown = Self.sample(state, layout)
        }
    }

    /// Shows what is known at once and samples from then on. The gauges
    /// (memory, pressure, swap, uptime, load: six system calls, microseconds)
    /// are read here, so the first frame has them and its height; the cores'
    /// ticks and the processes are the sampler's, off the main thread. The
    /// charts keep the readings of the last opening that are still inside
    /// their minute, where they were: the time the panel was closed is drawn
    /// as absent.
    func start() {
        stop()
        let now = SystemProbe.clock()
        shown.cpu = nil
        shown.cores = layout.groups(Array(repeating: 0, count: coreCount))
        shown.topCPU = nil
        shown.topMemory = nil
        shown.cpuHistory.trim(at: now)
        shown.memoryHistory.trim(at: now)
        shown.now = now
        let gauges = SystemProbe.gauges()
        show(gauges)
        shown.memoryHistory.add(gauges.memory.usedShare, at: now)
        opening += 1
        let opening = opening
        sampler = SystemSampler { [weak self] reading in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // A sample that was under way when the panel closed is dropped.
                    guard let self, self.sampler != nil, self.opening == opening else { return }
                    self.take(reading)
                }
            }
        }
    }

    func stop() {
        sampler?.cancel()
        sampler = nil
    }

    /// Return opens Activity Monitor, the panel's one action.
    func key(_ key: BarPanelKey) -> Bool {
        guard key == .enter, let activate else { return false }
        activate()
        return true
    }

    private func show(_ gauges: SystemGauges) {
        shown.memory = gauges.memory
        shown.pressure = gauges.pressure
        shown.swap = gauges.swap
        shown.note = SystemFormat.note(uptime: gauges.uptime, load: gauges.load)
    }

    private func take(_ reading: SystemReading) {
        var next = shown
        if let cpu = reading.cpu, let cores = reading.cores {
            next.cpu = cpu
            coreCount = cores.count
            next.cores = layout.groups(cores)
            next.cpuHistory.add(cpu, at: reading.time)
        }
        next.topCPU = reading.topCPU
        next.topMemory = reading.topMemory
        next.memoryHistory.add(reading.gauges.memory.usedShare, at: reading.time)
        next.now = reading.time
        shown = next
        show(reading.gauges)
    }

    // MARK: Sample data

    /// A repeatable wandering series in 0...1 (the mock-ups' own).
    private static func series(seed: UInt64, base: Double, swing: Double, spikes: [Int: Double] = [:]) -> [Double] {
        var state = seed
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 1000) / 1000
        }
        var value = base
        return (0...30).map { index in
            value += (next() - 0.5) * swing
            value = min(max(value, base - swing), base + swing)
            return min(max(value + (spikes[index] ?? 0), 0.01), 1)
        }
    }

    /// A minute of readings two seconds apart, the last at 60; `skip` leaves
    /// those samples out (the panel was closed).
    private static func history(_ values: [Double], skip: Range<Int> = 0..<0) -> SystemHistory {
        var history = SystemHistory()
        for (index, value) in values.enumerated() where !skip.contains(index) {
            history.add(value, at: Double(index) * SystemSampler.interval)
        }
        return history
    }

    private static func sample(_ state: String, _ layout: SystemCoreLayout) -> Shown {
        let gb = 1_073_741_824.0, mb = 1_048_576.0
        func memory(_ app: Double, _ wired: Double, _ compressed: Double) -> SystemMemory {
            SystemMemory(app: UInt64(app * gb), wired: UInt64(wired * gb), compressed: UInt64(compressed * gb),
                         total: UInt64(24 * gb))
        }
        let cpu = series(seed: 7, base: 0.14, swing: 0.08, spikes: [9: 0.32, 10: 0.44, 11: 0.2, 22: 0.15])
        // Efficiency cores first, as this Mac numbers them.
        let cores = [0.31, 0.27, 0.18, 0.12, 0.08, 0.05, 0.38, 0.22, 0.12, 0.06]
        var shown = Shown(cpu: 0.14, cores: layout.groups(cores))
        shown.topCPU = [SystemTopRow("WindowServer", 9.8), SystemTopRow("Google Chrome", 6.1), SystemTopRow("claude", 3.4)]
        shown.memory = memory(8.1, 2.6, 2.0)
        shown.topMemory = [SystemTopRow("Google Chrome", 3.2 * gb), SystemTopRow("SourceKitService", 1.4 * gb),
                           SystemTopRow("Ghostty", 612 * mb)]
        shown.note = SystemFormat.note(uptime: 6 * 3600 + 53 * 60, load: 1.86)
        shown.cpuHistory = history(cpu)
        shown.memoryHistory = history(series(seed: 11, base: 0.52, swing: 0.03))
        shown.now = 60
        switch state {
        case "pressed", "critical":
            // The same Mac short of memory: where a warning shows.
            shown.memory = memory(13.9, 3.1, 4.8)
            shown.memoryHistory = history(series(seed: 5, base: 0.86, swing: 0.05))
            shown.pressure = state == "critical" ? .critical : .warning
            shown.swap = UInt64(1.2 * gb)
            shown.topMemory = [SystemTopRow("Google Chrome", 7.9 * gb), SystemTopRow("SourceKitService", 3.1 * gb),
                               SystemTopRow("claude", 1.2 * gb)]
        case "starting":
            // The first half second of the first opening: the gauges are
            // there, the loads and the processes not yet, no history.
            shown.cpu = nil
            shown.cores = layout.groups(Array(repeating: 0, count: cores.count))
            shown.topCPU = nil
            shown.topMemory = nil
            shown.cpuHistory = SystemHistory()
            shown.memoryHistory = history([0.53], skip: 0..<0)
            shown.now = 0
        case "reopened":
            // Closed for twenty seconds, open again for six.
            shown.cpuHistory = history(cpu, skip: 18..<28)
            shown.memoryHistory = history(series(seed: 11, base: 0.52, swing: 0.03), skip: 18..<28)
        default:
            break
        }
        return shown
    }
}

struct SystemPanel: View {
    static let width: CGFloat = 320
    static let registration = BarPanelRegistration("system", pill: "pill.sys", width: width,
                                                   model: SystemModel.init) { SystemPanel(model: $0) }

    @ObservedObject var model: SystemModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        let shown = model.shown
        BarPanel(width: Self.width) {
            cpu(shown)
            // The halves' line is orange (the owner's choice, spec
            // 2026-11-13-bar-wifi-bluetooth-design); the others keep theme.line.
            PanelRule(accent: theme.orange)
            memory(shown)
            PanelRule()
            PanelFooter("Activity Monitor…", note: shown.note, action: openMonitor)
                .help("Open Activity Monitor (Return)")
        }
        .onAppear { model.activate = openMonitor }
    }

    private func openMonitor() {
        panel.openApp(bundleID: "com.apple.ActivityMonitor")
    }

    @ViewBuilder private func cpu(_ shown: SystemModel.Shown) -> some View {
        PanelHeader(.cpu, accent: theme.aqua, title: "CPU") { headline(shown.cpu) }
        SystemChart(history: shown.cpuHistory, now: shown.now, accent: theme.aqua)
        HStack(alignment: .top, spacing: GroveSpace.s12) {
            ForEach(shown.cores, id: \.caption) { group in
                CoreBars(group.caption, loads: group.loads, accent: theme.aqua)
                    .accessibilityValue(group.loads.map(SystemFormat.percent).joined(separator: ", "))
            }
        }
        PanelPairs(rows(shown.topCPU, SystemFormat.processCPU))
    }

    @ViewBuilder private func memory(_ shown: SystemModel.Shown) -> some View {
        PanelHeader(.memory, accent: theme.aqua, title: "Memory") { headline(shown.memory?.usedShare) }
        SystemChart(history: shown.memoryHistory, now: shown.now, accent: theme.aqua)
        let parts = parts(shown.memory)
        VStack(alignment: .leading, spacing: GroveSpace.s4) {
            PanelMeter(parts)
            SystemLegend(parts: parts, free: shown.memory.map { SystemFormat.gigabytes($0.free) } ?? "")
        }
        VStack(alignment: .leading, spacing: GroveSpace.s4) {
            PanelDetail("Pressure") { PanelStatus(shown.pressure.rawValue, accent: accent(shown.pressure)) }
            if shown.swap > 0 { PanelDetail("Swap", SystemFormat.memory(Double(shown.swap))) }
        }
        PanelPairs(rows(shown.topMemory, SystemFormat.memory))
    }

    /// A share as the header's number; a quiet dash while there is none yet.
    @ViewBuilder private func headline(_ share: Double?) -> some View {
        if let share {
            PanelValue(SystemFormat.percent(share))
        } else {
            Text("–").font(GroveFont.mono(GroveType.title, .semibold)).foregroundStyle(theme.quiet)
                .accessibilityLabel("Measuring")
        }
    }

    /// A list's lines: always `SystemModel.top` of them, blank where there is
    /// no process (yet), so the panel keeps its height.
    private func rows(_ top: [SystemTopRow]?, _ format: (Double) -> String) -> [(name: String, value: String)] {
        let rows = (top ?? []).prefix(SystemModel.top).map { (name: $0.name, value: format($0.amount)) }
        return rows + Array(repeating: (name: " ", value: " "), count: SystemModel.top - rows.count)
    }

    /// Memory's three parts; what is left of the bar is free.
    private func parts(_ memory: SystemMemory?) -> [MeterPart] {
        func part(_ name: String, _ bytes: UInt64?, _ accent: RGB) -> MeterPart {
            MeterPart(share: bytes.flatMap { memory?.share($0) } ?? 0, accent: accent, name: name,
                      value: bytes.map(SystemFormat.gigabytes) ?? "")
        }
        return [part("app", memory?.app, theme.aqua), part("wired", memory?.wired, theme.blue),
                part("compressed", memory?.compressed, theme.purple)]
    }

    /// The dot's colour; the word stays fg.
    private func accent(_ pressure: SystemPressure) -> RGB {
        switch pressure {
        case .normal: return theme.green
        case .warning: return theme.yellow
        case .critical: return theme.red
        }
    }
}

/// A minute of readings placed by their age: the newest at the right edge,
/// nothing drawn where nothing was read (before the panel first opened,
/// while it was closed), so the line starts where the data starts. A lone
/// reading is a dot. `Sparkline`'s height, line and baseline.
struct SystemChart: View {
    let history: SystemHistory
    let now: Double
    let accent: RGB
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let dot = PanelMetrics.chartLine
            func place(_ point: SystemHistory.Point) -> CGPoint {
                // As `SparklineGeometry`: half a point inside the top and bottom.
                CGPoint(x: size.width * point.x, y: (size.height - 1) * (1 - MeterGeometry.fraction(point.value)) + 0.5)
            }
            for run in history.runs(at: now) {
                guard let first = run.first.map(place) else { continue }
                if run.count == 1 {
                    let x = min(max(first.x, dot), size.width - dot), y = min(max(first.y, dot), size.height - dot)
                    context.fill(Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: 2 * dot, height: 2 * dot)),
                                 with: .color(Color(accent)))
                    continue
                }
                var path = Path()
                path.move(to: first)
                for point in run.dropFirst() { path.addLine(to: place(point)) }
                context.stroke(path, with: .color(Color(accent)),
                               style: StrokeStyle(lineWidth: PanelMetrics.chartLine, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: PanelMetrics.chart)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .accessibilityHidden(true)
    }
}

/// The memory bar's legend on one line across the panel: `PanelLegend`'s
/// entries, spread from edge to edge (four of them don't fit packed 8 pt
/// apart), "compressed" cut short when the sizes are too wide even so.
struct SystemLegend: View {
    let parts: [MeterPart]
    let free: String
    @Environment(\.theme) private var theme
    @Environment(\.panelSurface) private var surface

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(short: false)
            line(short: true)
        }
        .font(GroveFont.mono(GroveType.finePrint))
        .lineLimit(1)
    }

    private func line(short: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                let name = part.name ?? ""
                entry(Color(part.accent), short && name == "compressed" ? "compr." : name, part.value ?? "", spoken: name)
                Spacer(minLength: GroveSpace.s4)
            }
            entry(theme.selectedFill(on: surface), "free", free, spoken: "free")
        }
    }

    private func entry(_ color: Color, _ name: String, _ value: String, spoken: String) -> some View {
        HStack(spacing: GroveSpace.s4) {
            Rectangle().fill(color).frame(width: PanelMetrics.meter, height: PanelMetrics.meter)
                .lightOutline(cornerRadius: 0)
            (Text(name).foregroundColor(theme.quiet) + Text(verbatim: " " + value)).fixedSize()
        }
        .accessibilityElement().accessibilityLabel("\(spoken) \(value) GB")
    }
}
