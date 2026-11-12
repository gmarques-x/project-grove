import Foundation

// What the CPU & memory panel computes from the Mac's counters (spec
// 2026-11-12-bar-panels-design §6). The app's sampler reads the counters
// (Mach, sysctl, libproc, one `ps`); everything here is pure.

// MARK: CPU

/// One core's tick counters, as `host_processor_info` gives them. They are
/// 32 bits wide and wrap; a load is always read from two samples.
public struct SystemCPUTicks: Equatable, Sendable {
    public var user, system, idle, nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum SystemCPU {
    /// The share of the time between two samples a core was busy, 0...1; nil
    /// when no time passed.
    public static func load(from old: SystemCPUTicks, to new: SystemCPUTicks) -> Double? {
        let (busy, all) = spent(from: old, to: new)
        return all > 0 ? Double(busy) / Double(all) : nil
    }

    /// Each core's load, and the whole machine's (the cores' ticks summed,
    /// what Activity Monitor and the bar call the CPU's load). Nil when the
    /// two samples aren't of the same cores, or no time passed.
    public static func loads(from old: [SystemCPUTicks], to new: [SystemCPUTicks]) -> (cores: [Double], total: Double)? {
        guard !new.isEmpty, old.count == new.count else { return nil }
        var busy: UInt64 = 0, all: UInt64 = 0
        let cores = zip(old, new).map { old, new -> Double in
            let (coreBusy, coreAll) = spent(from: old, to: new)
            busy += coreBusy
            all += coreAll
            return coreAll > 0 ? Double(coreBusy) / Double(coreAll) : 0
        }
        guard all > 0 else { return nil }
        return (cores, Double(busy) / Double(all))
    }

    private static func spent(from old: SystemCPUTicks, to new: SystemCPUTicks) -> (busy: UInt64, all: UInt64) {
        // Wrapping: the counters overflow after a few hundred days.
        let busy = UInt64(new.user &- old.user) + UInt64(new.system &- old.system) + UInt64(new.nice &- old.nice)
        return (busy, busy + UInt64(new.idle &- old.idle))
    }
}

/// A group of cores under its caption.
public struct SystemCoreGroup: Equatable, Sendable {
    public var caption: String
    public var loads: [Double]

    public init(_ caption: String, _ loads: [Double]) {
        self.caption = caption
        self.loads = loads
    }
}

/// Which cores are of which type.
public struct SystemCoreLayout: Equatable, Sendable {
    /// `hw.perflevel0.logicalcpu` and `hw.perflevel1.logicalcpu`; 0 where the
    /// Mac has no such level.
    public var performance: Int
    public var efficiency: Int
    /// Each core's type by its index ("P", "E"), from the device tree; empty
    /// when it couldn't be read.
    public var types: [String]

    public init(performance: Int, efficiency: Int, types: [String] = []) {
        self.performance = performance
        self.efficiency = efficiency
        self.types = types
    }

    /// The cores' loads grouped as the panel shows them: Performance, then
    /// Efficiency; one group "Cores" on a Mac without two levels (or when the
    /// counts don't add up to the cores there are).
    public func groups(_ loads: [Double]) -> [SystemCoreGroup] {
        guard performance > 0, efficiency > 0, performance + efficiency == loads.count else {
            return [SystemCoreGroup("Cores", loads)]
        }
        var fast: [Double] = [], slow: [Double] = []
        if types.count == loads.count, types.filter({ $0 == "P" }).count == performance,
           types.filter({ $0 == "E" }).count == efficiency {
            for (type, load) in zip(types, loads) {
                if type == "P" { fast.append(load) } else { slow.append(load) }
            }
        } else {
            // Apple silicon numbers its efficiency cores first.
            slow = Array(loads.prefix(efficiency))
            fast = Array(loads.suffix(performance))
        }
        return [SystemCoreGroup("Performance", fast), SystemCoreGroup("Efficiency", slow)]
    }
}

// MARK: Memory

/// The page counts of `host_statistics64(HOST_VM_INFO64)` the panel reads.
public struct SystemMemoryPages: Equatable, Sendable {
    /// `internal_page_count`: anonymous pages (an app's own memory).
    public var anonymous: UInt64
    /// `purgeable_count`: memory the system may take back at will.
    public var purgeable: UInt64
    /// `wire_count`.
    public var wired: UInt64
    /// `compressor_page_count`: the pages the compressor occupies.
    public var compressor: UInt64

    public init(anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressor: UInt64) {
        self.anonymous = anonymous
        self.purgeable = purgeable
        self.wired = wired
        self.compressor = compressor
    }
}

/// Memory as Activity Monitor splits it, in bytes.
public struct SystemMemory: Equatable, Sendable {
    public var app, wired, compressed, total: UInt64

    public init(app: UInt64, wired: UInt64, compressed: UInt64, total: UInt64) {
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.total = total
    }

    /// Activity Monitor's numbers: App Memory is the anonymous pages less the
    /// purgeable ones, Wired the wired pages, Compressed the pages the
    /// compressor occupies; Memory Used is their sum. (Cached Files, the
    /// file-backed and purgeable pages, count as free here, as there.)
    public init(pages: SystemMemoryPages, pageSize: UInt64, total: UInt64) {
        self.init(app: (pages.anonymous - min(pages.purgeable, pages.anonymous)) * pageSize,
                  wired: pages.wired * pageSize, compressed: pages.compressor * pageSize, total: total)
    }

    /// "Memory Used": app + wired + compressed, never more than there is.
    public var used: UInt64 { min(total, app + wired + compressed) }
    /// The rest: free and cached.
    public var free: UInt64 { total - used }
    /// 0...1.
    public var usedShare: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// A part's share of the whole, for the meter.
    public func share(_ part: UInt64) -> Double { total > 0 ? Double(part) / Double(total) : 0 }
}

/// The kernel's memory pressure.
public enum SystemPressure: String, Equatable, Sendable {
    case normal = "Normal", warning = "Warning", critical = "Critical"

    /// From `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning,
    /// 4 critical. Anything else reads as normal.
    public init(level: Int) {
        switch level {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

// MARK: Processes

/// A line of `/bin/ps -Aceo pid,pcpu,rss,comm`.
public struct SystemPSRow: Equatable, Sendable {
    public var pid: Int32
    /// Percent of one core, `ps`'s decaying average.
    public var cpu: Double
    /// Resident memory, bytes.
    public var memory: UInt64
    public var name: String
}

public enum SystemPS {
    /// The rows of `ps -Aceo pid,pcpu,rss,comm`. The header and anything that
    /// isn't three numbers and a name are skipped; the name keeps its spaces.
    /// A decimal comma is read too (`ps` follows the locale unless run with
    /// `LC_ALL=C`).
    public static func parse(_ output: String) -> [SystemPSRow] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]),
                  let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")), cpu.isFinite, cpu >= 0,
                  let rss = UInt64(fields[2]) else { return nil }
            var name = fields[3].trimmingCharacters(in: .whitespaces)
            // A process on its way out is listed as "(name)".
            if name.hasPrefix("("), name.hasSuffix(")"), name.count > 2 { name = String(name.dropFirst().dropLast()) }
            guard !name.isEmpty else { return nil }
            return SystemPSRow(pid: pid, cpu: cpu, memory: rss * 1024, name: name)
        }
    }
}

/// One process at one sample.
public struct SystemProcess: Equatable, Sendable {
    public var pid: Int32
    /// What its row is called: its app's name when it runs from inside an
    /// app's bundle (helpers count with their app), else its own.
    public var name: String
    /// CPU time used since it started, nanoseconds; nil when the system
    /// doesn't let us read it (another user's process).
    public var cpuTime: UInt64?
    /// `ps`'s percentage, used when there is no CPU time to compare.
    public var cpu: Double
    /// Bytes: the physical footprint (Activity Monitor's "Memory") where it
    /// can be read, else the resident size.
    public var memory: UInt64

    public init(pid: Int32, name: String, cpuTime: UInt64?, cpu: Double, memory: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuTime = cpuTime
        self.cpu = cpu
        self.memory = memory
    }
}

/// A row of a "top three" list.
public struct SystemTopRow: Equatable, Sendable {
    public var name: String
    /// Percent of one core, or bytes.
    public var amount: Double

    public init(_ name: String, _ amount: Double) {
        self.name = name
        self.amount = amount
    }
}

public enum SystemProcesses {
    /// The app a process belongs to, from its executable's path: the name of
    /// the outermost `.app` it is inside ("…/Google Chrome.app/…/Google
    /// Chrome Helper (Renderer).app/…" is "Google Chrome"). Nil outside any.
    public static func appName(path: String) -> String? {
        for part in path.split(separator: "/") where part.hasSuffix(".app") && part.count > 4 {
            return String(part.dropLast(4))
        }
        return nil
    }

    /// A process's percentage of one core between two samples `elapsed`
    /// seconds apart: from its CPU time when both samples have it (and it
    /// didn't go backwards: a reused pid), else `ps`'s figure.
    public static func cpu(_ process: SystemProcess, before: SystemProcess?, elapsed: Double) -> Double {
        guard elapsed > 0, let now = process.cpuTime, let then = before?.cpuTime, now >= then else { return process.cpu }
        return Double(now - then) / (elapsed * 1e9) * 100
    }

    /// The `count` busiest and the `count` largest, processes of one name
    /// added together. `previous`: the sample before, by pid (empty at the
    /// first: `ps`'s figures are used). Ties go by name, so the order is
    /// steady.
    public static func top(_ processes: [SystemProcess], previous: [Int32: SystemProcess], elapsed: Double,
                           count: Int = 3) -> (cpu: [SystemTopRow], memory: [SystemTopRow]) {
        var cpu: [String: Double] = [:], memory: [String: Double] = [:]
        for process in processes {
            cpu[process.name, default: 0] += Self.cpu(process, before: previous[process.pid], elapsed: elapsed)
            memory[process.name, default: 0] += Double(process.memory)
        }
        func first(_ totals: [String: Double]) -> [SystemTopRow] {
            totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(count).map { SystemTopRow($0.key, $0.value) }
        }
        return (first(cpu), first(memory))
    }
}

// MARK: History

/// The readings a chart shows: the last `span` seconds, each with the time
/// it was taken. Nothing is sampled while the panel is closed, so the time
/// without readings is drawn as absent, never as zero.
public struct SystemHistory: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        /// 0 (the left edge, `span` seconds ago) to 1 (now).
        public var x: Double
        /// The reading, 0...1.
        public var value: Double

        public init(x: Double, value: Double) {
            self.x = x
            self.value = value
        }
    }

    /// Seconds shown.
    public let span: Double
    /// Readings further apart than this aren't joined (the panel was closed
    /// in between).
    public let gap: Double
    public private(set) var samples: [(time: Double, value: Double)] = []

    public init(span: Double = 60, gap: Double = 5) {
        self.span = span
        self.gap = gap
    }

    public static func == (a: SystemHistory, b: SystemHistory) -> Bool {
        a.span == b.span && a.gap == b.gap && a.samples.elementsEqual(b.samples) { $0 == $1 }
    }

    /// Adds a reading taken at `time` (seconds on any steady clock) and
    /// drops what is older than the span.
    public mutating func add(_ value: Double, at time: Double) {
        if let last = samples.last, time < last.time { samples.removeAll() }   // the clock went back
        samples.append((time, value))
        trim(at: time)
    }

    /// Drops what is older than the span at `now`.
    public mutating func trim(at now: Double) {
        samples.removeAll { $0.time < now - span }
    }

    /// The lines to draw at `now`: each run of readings no further apart
    /// than `gap`, oldest first, placed by age. A run of one is a single
    /// point (the first reading after opening).
    public func runs(at now: Double) -> [[Point]] {
        var runs: [[Point]] = [], last: Double?
        for sample in samples where sample.time >= now - span && sample.time <= now {
            let point = Point(x: 1 - (now - sample.time) / span, value: min(1, max(0, sample.value)))
            if let last, sample.time - last <= gap { runs[runs.count - 1].append(point) } else { runs.append([point]) }
            last = sample.time
        }
        return runs
    }
}

// MARK: Words

/// The panel's numbers as text. Written the same in every locale: a decimal
/// point, no grouping.
public enum SystemFormat {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func fixed(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", locale: posix, value.isFinite ? value : 0)
    }

    /// A share as the headline: 0.137 is "14%".
    public static func percent(_ share: Double) -> String {
        "\(Int((min(1, max(0, share.isFinite ? share : 0)) * 100).rounded()))%"
    }

    /// A process's percentage of one core: "9.8%", "112%" from a hundred up.
    public static func processCPU(_ percent: Double) -> String {
        fixed(max(0, percent), percent >= 99.95 ? 0 : 1) + "%"
    }

    /// Bytes in GB for the legend, without the unit: "8.1".
    public static func gigabytes(_ bytes: UInt64) -> String {
        fixed(Double(bytes) / 1_073_741_824, 1)
    }

    /// A process's memory or the swap in use: "3.2 GB", "612 MB".
    public static func memory(_ bytes: Double) -> String {
        let megabytes = max(0, bytes) / 1_048_576
        return megabytes.rounded() >= 1000 ? fixed(megabytes / 1024, 1) + " GB" : fixed(megabytes, 0) + " MB"
    }

    /// The time since the Mac started: "53m", "6h 53m", "3d 4h".
    public static func uptime(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds.isFinite ? seconds : 0) / 60)
        let (days, hours) = (minutes / 1440, minutes / 60 % 24)
        if days > 0 { return "\(days)d \(hours)h" }
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// The one-minute load average: "1.86".
    public static func load(_ load: Double) -> String { fixed(max(0, load), 2) }

    /// The footer's note: "up 6h 53m · load 1.86".
    public static func note(uptime: Double, load: Double) -> String {
        "up \(Self.uptime(uptime)) · load \(Self.load(load))"
    }
}
