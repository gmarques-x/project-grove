import Darwin
import Foundation
import GroveKeysCore
import IOKit

// The CPU & memory panel's readings of the Mac. Counters come from Mach,
// sysctl and libproc; one `ps` a sample fills in the processes of other
// users (WindowServer, the daemons), whose accounting only root may read.
// What is made of the counters is pure code in GroveKeysCore (SystemStats).

/// What is cheap enough to read anywhere (a few system calls, microseconds):
/// memory, pressure, swap, uptime, load.
struct SystemGauges: Sendable {
    var memory: SystemMemory
    var pressure: SystemPressure
    /// Swap in use, bytes.
    var swap: UInt64
    /// Seconds since the Mac started.
    var uptime: Double
    /// The one-minute load average.
    var load: Double
}

/// One sample.
struct SystemReading: Sendable {
    /// When, on the steady clock (`SystemProbe.clock`).
    var time: Double
    /// Each core's load and the whole; nil at the first sample (a load is
    /// the difference of two).
    var cores: [Double]?
    var cpu: Double?
    var gauges: SystemGauges
    var topCPU: [SystemTopRow]
    var topMemory: [SystemTopRow]
}

/// The system calls.
enum SystemProbe {
    // `mach_host_self()` hands out a port right at each call: asked once.
    private static let host = mach_host_self()
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(1, info.numer)), UInt64(max(1, info.denom)))
    }()

    /// Seconds on a clock that never goes back and counts sleep.
    static func clock() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9
    }

    static func integer(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // A 4-byte value fills the low half (little-endian); the rest stays 0.
        return size == 4 ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }

    /// The cores' types: the two levels' sizes from sysctl, each core's type
    /// from the device tree (Apple silicon; empty elsewhere).
    static func coreLayout() -> SystemCoreLayout {
        let levels = integer("hw.nperflevels") ?? 1
        guard levels >= 2 else { return SystemCoreLayout(performance: 0, efficiency: 0) }
        return SystemCoreLayout(performance: integer("hw.perflevel0.logicalcpu") ?? 0,
                                efficiency: integer("hw.perflevel1.logicalcpu") ?? 0, types: coreTypes())
    }

    /// "P" or "E" for each core by its number, from `IODeviceTree:/cpus`
    /// (`cluster-type`); empty when any core lacks one.
    private static func coreTypes() -> [String] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var types: [Int: String] = [:], count = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            count += 1
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let number = (property("logical-cpu-id") as? NSNumber)?.intValue,
                  let data = property("cluster-type") as? Data, let letter = data.first else { return [] }
            types[number] = String(UnicodeScalar(letter))
        }
        guard count > 0, types.count == count, (0..<count).allSatisfy({ types[$0] != nil }) else { return [] }
        return (0..<count).map { types[$0] ?? "" }
    }

    /// Every core's tick counters (`host_processor_info`, one call).
    static func ticks() -> [SystemCPUTicks] {
        var cores: natural_t = 0, count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS, let info else {
            return []
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        guard Int(count) >= Int(cores) * states else { return [] }
        return (0..<Int(cores)).map { core in
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[core * states + Int(state)]) }
            return SystemCPUTicks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM), idle: ticks(CPU_STATE_IDLE),
                                  nice: ticks(CPU_STATE_NICE))
        }
    }

    /// Memory (`host_statistics64`), pressure, swap, uptime and load (sysctl,
    /// `getloadavg`): six system calls, no process.
    static func gauges() -> SystemGauges {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        if result != KERN_SUCCESS { stats = vm_statistics64() }
        let pages = SystemMemoryPages(anonymous: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                                      wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count))
        let memory = SystemMemory(pages: pages, pageSize: UInt64(integer("hw.pagesize") ?? Int(getpagesize())),
                                  total: ProcessInfo.processInfo.physicalMemory)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        var boot = timeval()
        var bootSize = MemoryLayout<timeval>.size
        var uptime = ProcessInfo.processInfo.systemUptime
        if sysctlbyname("kern.boottime", &boot, &bootSize, nil, 0) == 0, boot.tv_sec > 0 {
            uptime = Date().timeIntervalSince1970 - Double(boot.tv_sec)
        }

        var loads = [Double](repeating: 0, count: 3)
        let load = getloadavg(&loads, 3) > 0 ? loads[0] : 0

        return SystemGauges(memory: memory, pressure: SystemPressure(level: integer("kern.memorystatus_vm_pressure_level") ?? 1),
                            swap: swapUsed, uptime: uptime, load: load)
    }

    /// Every process: `ps` for the list, its names and what any user may
    /// know (a decaying CPU percentage, the resident size); libproc, where
    /// the system lets us (our own user's processes), for the exact CPU time
    /// and the footprint Activity Monitor shows, and for the app a helper
    /// belongs to. One `ps` (about 20 ms of CPU) and two calls a process.
    static func processes() -> [SystemProcess] {
        let ps = Subprocess.run("/bin/ps", ["-Aceo", "pid,pcpu,rss,comm"], timeout: 1.5)
        guard ps.status == 0 else { return [] }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return SystemPS.parse(ps.output).map { row in
            var process = SystemProcess(pid: row.pid, name: row.name, cpuTime: nil, cpu: row.cpu, memory: row.memory)
            if proc_pidpath(row.pid, &path, UInt32(path.count)) > 0,
               let app = SystemProcesses.appName(path: String(cString: path)) {
                process.name = app
            }
            var usage = rusage_info_v4()
            let read = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(row.pid, RUSAGE_INFO_V4, $0) }
            }
            if read == 0 {
                // Mach time units, nanoseconds only on Intel.
                process.cpuTime = (usage.ri_user_time + usage.ri_system_time) / timebase.denom * timebase.numer
                if usage.ri_phys_footprint > 0 { process.memory = usage.ri_phys_footprint }
            }
            return process
        }
    }
}

/// Samples while a panel is open: once at once, again after `first` seconds
/// (the first CPU loads: they need two samples), then every `interval`. All
/// on its own queue; `deliver` is called there. Made at `start()` and
/// cancelled at `stop()`: nothing is kept from one opening to the next, and
/// nothing runs in between.
final class SystemSampler: @unchecked Sendable {
    static let interval = 2.0
    static let first = 0.5

    private let queue = DispatchQueue(label: "grove.keys.panel.system", qos: .utility)
    private let timer: DispatchSourceTimer
    // Touched on `queue` only.
    private var ticks: [SystemCPUTicks] = []
    private var processes: [Int32: SystemProcess] = [:]
    private var sampled: Double?
    private var cancelled = false

    init(deliver: @escaping @Sendable (SystemReading) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            guard let self, !self.cancelled else { return }
            deliver(self.sample())
        }
        timer.schedule(deadline: .now() + Self.first, repeating: Self.interval, leeway: .milliseconds(100))
        queue.async { [weak self] in
            guard let self, !self.cancelled else { return }
            deliver(self.sample())
        }
        timer.resume()
    }

    func cancel() {
        timer.cancel()
        queue.async { self.cancelled = true }
    }

    deinit { timer.cancel() }

    private func sample() -> SystemReading {
        let now = SystemProbe.clock()
        let ticks = SystemProbe.ticks()
        let loads = SystemCPU.loads(from: self.ticks, to: ticks)
        self.ticks = ticks
        let processes = SystemProbe.processes()
        let top = SystemProcesses.top(processes, previous: self.processes, elapsed: sampled.map { now - $0 } ?? 0)
        self.processes = Dictionary(processes.map { ($0.pid, $0) }) { _, last in last }
        sampled = now
        return SystemReading(time: now, cores: loads?.cores, cpu: loads?.total, gauges: SystemProbe.gauges(),
                             topCPU: top.cpu, topMemory: top.memory)
    }
}
