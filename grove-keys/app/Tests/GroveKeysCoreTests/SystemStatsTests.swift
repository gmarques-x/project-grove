import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct SystemCPUTests {
    static func ticks(_ user: UInt32, _ system: UInt32, _ idle: UInt32, _ nice: UInt32 = 0) -> SystemCPUTicks {
        SystemCPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func aLoadIsTheBusyShareBetweenTwoSamples() {
        #expect(SystemCPU.load(from: Self.ticks(100, 50, 850), to: Self.ticks(120, 60, 1020)) == 0.15)
        #expect(SystemCPU.load(from: Self.ticks(0, 0, 0), to: Self.ticks(0, 0, 200)) == 0)
        #expect(SystemCPU.load(from: Self.ticks(0, 0, 0), to: Self.ticks(10, 0, 0, 10)) == 1)
    }

    @Test func noTimeBetweenSamplesIsNoLoad() {
        #expect(SystemCPU.load(from: Self.ticks(5, 5, 5), to: Self.ticks(5, 5, 5)) == nil)
        #expect(SystemCPU.loads(from: [Self.ticks(5, 5, 5)], to: [Self.ticks(5, 5, 5)]) == nil)
    }

    @Test func countersThatWrapStillGiveTheLoad() {
        let old = Self.ticks(.max - 9, 0, .max - 29), new = Self.ticks(10, 0, 50)
        #expect(SystemCPU.load(from: old, to: new) == 0.2)
    }

    @Test func theTotalIsTheCoresTicksSummed() throws {
        let old = [Self.ticks(0, 0, 0), Self.ticks(0, 0, 0)]
        // One core busy half of 200 ticks, one idle for 200.
        let new = [Self.ticks(60, 40, 100), Self.ticks(0, 0, 200)]
        let loads = try #require(SystemCPU.loads(from: old, to: new))
        #expect(loads.cores == [0.5, 0])
        #expect(loads.total == 0.25)
    }

    @Test func samplesOfDifferentCoresGiveNothing() {
        #expect(SystemCPU.loads(from: [Self.ticks(0, 0, 0)], to: [Self.ticks(1, 1, 1), Self.ticks(1, 1, 1)]) == nil)
        #expect(SystemCPU.loads(from: [], to: []) == nil)
    }

    @Test func coresAreGroupedByTheirTypeFromTheDeviceTree() {
        // This Mac (M4): six efficiency cores first, then four performance.
        let layout = SystemCoreLayout(performance: 4, efficiency: 6, types: ["E", "E", "E", "E", "E", "E", "P", "P", "P", "P"])
        let loads = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        #expect(layout.groups(loads) == [SystemCoreGroup("Performance", [0.7, 0.8, 0.9, 1.0]),
                                         SystemCoreGroup("Efficiency", [0.1, 0.2, 0.3, 0.4, 0.5, 0.6])])
        // Types in another order are followed, not assumed.
        let mixed = SystemCoreLayout(performance: 2, efficiency: 2, types: ["P", "E", "P", "E"])
        #expect(mixed.groups([1, 2, 3, 4]) == [SystemCoreGroup("Performance", [1, 3]), SystemCoreGroup("Efficiency", [2, 4])])
    }

    @Test func withoutTypesEfficiencyCoresComeFirst() {
        let layout = SystemCoreLayout(performance: 4, efficiency: 2)
        #expect(layout.groups([1, 2, 3, 4, 5, 6]) == [SystemCoreGroup("Performance", [3, 4, 5, 6]),
                                                      SystemCoreGroup("Efficiency", [1, 2])])
        // Types that disagree with the counts are not believed.
        let wrong = SystemCoreLayout(performance: 4, efficiency: 2, types: ["P", "P", "P", "E", "E", "E"])
        #expect(wrong.groups([1, 2, 3, 4, 5, 6]).first == SystemCoreGroup("Performance", [3, 4, 5, 6]))
    }

    @Test func aMacWithoutTwoLevelsHasOneGroup() {
        #expect(SystemCoreLayout(performance: 0, efficiency: 0).groups([0.1, 0.2]) == [SystemCoreGroup("Cores", [0.1, 0.2])])
        #expect(SystemCoreLayout(performance: 8, efficiency: 0).groups([0.1, 0.2]) == [SystemCoreGroup("Cores", [0.1, 0.2])])
        // Counts that don't add up to the cores there are.
        #expect(SystemCoreLayout(performance: 4, efficiency: 6).groups([0.1, 0.2]) == [SystemCoreGroup("Cores", [0.1, 0.2])])
    }
}

@Suite struct SystemMemoryTests {
    static let page: UInt64 = 16384, total: UInt64 = 25_769_803_776

    @Test func usedIsAppWiredAndCompressed() {
        // 24 GB at 16 KB pages: 8 GB anonymous of which 0.5 GB purgeable, 2.5 GB wired, 2 GB compressor.
        let gb = UInt64(1_073_741_824) / Self.page
        let pages = SystemMemoryPages(anonymous: 8 * gb, purgeable: gb / 2, wired: 5 * gb / 2, compressor: 2 * gb)
        let memory = SystemMemory(pages: pages, pageSize: Self.page, total: Self.total)
        #expect(memory.app == 7_516_192_768 + 536_870_912)
        #expect(memory.wired == 2_684_354_560)
        #expect(memory.compressed == 2_147_483_648)
        #expect(memory.used == 12 * 1_073_741_824)
        #expect(memory.free == 12 * 1_073_741_824)
        #expect(memory.usedShare == 0.5)
        #expect(memory.share(memory.wired) == 2.5 / 24)
    }

    @Test func oddCountsNeverGoBelowZeroOrAboveTheWhole() {
        let more = SystemMemoryPages(anonymous: 10, purgeable: 50, wired: 0, compressor: 0)
        #expect(SystemMemory(pages: more, pageSize: Self.page, total: Self.total).app == 0)
        let over = SystemMemory(app: 20, wired: 20, compressed: 20, total: 50)
        #expect(over.used == 50)
        #expect(over.free == 0)
        #expect(over.usedShare == 1)
        #expect(SystemMemory(app: 1, wired: 1, compressed: 1, total: 0).usedShare == 0)
    }

    @Test func pressureLevelsAreTheKernels() {
        #expect(SystemPressure(level: 1) == .normal)
        #expect(SystemPressure(level: 2) == .warning)
        #expect(SystemPressure(level: 4) == .critical)
        #expect(SystemPressure(level: 0) == .normal)
        #expect(SystemPressure(level: -1) == .normal)
        #expect(SystemPressure.warning.rawValue == "Warning")
    }
}

@Suite struct SystemProcessesTests {
    static func process(_ pid: Int32, _ name: String, time: UInt64? = nil, cpu: Double = 0, memory: UInt64 = 0) -> SystemProcess {
        SystemProcess(pid: pid, name: name, cpuTime: time, cpu: cpu, memory: memory)
    }

    @Test func psOutputIsReadWithNamesThatHaveSpaces() throws {
        let rows = SystemPS.parse(try fixture("system-ps.txt"))
        #expect(rows.count == 14)
        #expect(rows.first == SystemPSRow(pid: 1, cpu: 0.8, memory: 25056 * 1024, name: "launchd"))
        #expect(rows[2] == SystemPSRow(pid: 407, cpu: 12.4, memory: 363_840 * 1024, name: "WindowServer"))
        #expect(rows[10] == SystemPSRow(pid: 55775, cpu: 0, memory: 135_120 * 1024, name: "Google Chrome Helper (Aperitif Renderer)"))
        #expect(rows.last == SystemPSRow(pid: 9202, cpu: 9.3, memory: 1_152_112 * 1024, name: "claude"))
    }

    @Test func aDecimalCommaAndBrokenLinesAreHandled() {
        let rows = SystemPS.parse("  PID  %CPU    RSS COMM\n  407  12,4 363840 WindowServer\nnonsense\n 12 x 5 name\n 9 1.0 7\n\n 3 0.5 16 a  b \n")
        #expect(rows == [SystemPSRow(pid: 407, cpu: 12.4, memory: 363_840 * 1024, name: "WindowServer"),
                         SystemPSRow(pid: 3, cpu: 0.5, memory: 16384, name: "a  b")])
        #expect(SystemPS.parse("").isEmpty)
        // A process that is exiting is listed in brackets; a helper's own brackets stay.
        #expect(SystemPS.parse("31971  93.4 176176 (swift-frontend)\n 7 0.0 16 Code Helper (Plugin)\n").map(\.name)
            == ["swift-frontend", "Code Helper (Plugin)"])
    }

    @Test func aHelperBelongsToTheOutermostApp() {
        #expect(SystemProcesses.appName(path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/157.0.8103.51/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)") == "Google Chrome")
        #expect(SystemProcesses.appName(path: "/Applications/Ghostty.app/Contents/MacOS/ghostty") == "Ghostty")
        #expect(SystemProcesses.appName(path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder") == "Finder")
        #expect(SystemProcesses.appName(path: "/usr/libexec/secd") == nil)
        #expect(SystemProcesses.appName(path: "/opt/tools/.app/bin/x") == nil)
        #expect(SystemProcesses.appName(path: "") == nil)
    }

    @Test func cpuComesFromTheTimeUsedBetweenSamples() {
        // 0.196 s of CPU in 2 s: 9.8% of a core.
        let before = Self.process(1, "a", time: 1_000_000_000, cpu: 50)
        let now = Self.process(1, "a", time: 1_196_000_000, cpu: 50)
        #expect(abs(SystemProcesses.cpu(now, before: before, elapsed: 2) - 9.8) < 1e-9)
        // Two threads flat out: above a hundred.
        #expect(SystemProcesses.cpu(Self.process(1, "a", time: 5_000_000_000), before: before, elapsed: 2) == 200)
    }

    @Test func withoutTwoReadingsPsIsBelieved() {
        let now = Self.process(1, "a", time: 500, cpu: 12.4)
        #expect(SystemProcesses.cpu(now, before: nil, elapsed: 2) == 12.4)
        #expect(SystemProcesses.cpu(Self.process(1, "a", cpu: 3), before: now, elapsed: 2) == 3)          // unreadable now
        #expect(SystemProcesses.cpu(now, before: Self.process(1, "a", cpu: 3), elapsed: 2) == 12.4)       // unreadable before
        #expect(SystemProcesses.cpu(now, before: Self.process(1, "b", time: 900), elapsed: 2) == 12.4)    // a reused pid
        #expect(SystemProcesses.cpu(now, before: Self.process(1, "a", time: 100), elapsed: 0) == 12.4)
    }

    @Test func theTopThreeAddUpProcessesOfOneName() {
        let gb: UInt64 = 1_073_741_824
        let now = [
            Self.process(1, "WindowServer", cpu: 9.8, memory: gb / 4),
            Self.process(2, "Google Chrome", time: 100_000_000, memory: gb),
            Self.process(3, "Google Chrome", time: 22_000_000, memory: 2 * gb),
            Self.process(4, "claude", time: 68_000_000, memory: gb / 2),
            Self.process(5, "Ghostty", time: 2_000_000, memory: gb / 2),
            Self.process(6, "idle", time: 0, memory: 1),
        ]
        let before = Dictionary(uniqueKeysWithValues: now.map { ($0.pid, Self.process($0.pid, $0.name, time: $0.cpuTime.map { _ in 0 })) })
        let top = SystemProcesses.top(now, previous: before, elapsed: 2)
        #expect(top.cpu.map(\.name) == ["WindowServer", "Google Chrome", "claude"])
        #expect(top.cpu.map { ($0.amount * 10).rounded() / 10 } == [9.8, 6.1, 3.4])
        // Equal sizes go by name.
        #expect(top.memory == [SystemTopRow("Google Chrome", Double(3 * gb)), SystemTopRow("Ghostty", Double(gb / 2)),
                               SystemTopRow("claude", Double(gb / 2))])
        #expect(SystemProcesses.top(now, previous: [:], elapsed: 2, count: 1).cpu == [SystemTopRow("WindowServer", 9.8)])
        #expect(SystemProcesses.top([], previous: [:], elapsed: 2).cpu.isEmpty)
    }
}

@Suite struct SystemHistoryTests {
    @Test func readingsArePlacedByAge() {
        var history = SystemHistory()
        history.add(0.2, at: 100)
        history.add(0.4, at: 102)
        history.add(0.6, at: 104)
        let runs = history.runs(at: 104)
        #expect(runs.count == 1)
        #expect(runs[0].map(\.value) == [0.2, 0.4, 0.6])
        #expect(runs[0].last?.x == 1)
        #expect(abs(runs[0][0].x - (1 - 4.0 / 60)) < 1e-12)
    }

    @Test func theFirstReadingIsAPointAndNothingIsDrawnBeforeIt() {
        var history = SystemHistory()
        #expect(history.runs(at: 50).isEmpty)
        history.add(0.14, at: 50.5)
        #expect(history.runs(at: 50.5) == [[SystemHistory.Point(x: 1, value: 0.14)]])
    }

    @Test func aClosedPanelLeavesAGapNotAZero() {
        var history = SystemHistory()
        for step in 0..<5 { history.add(0.3, at: 100 + Double(step) * 2) }     // open until 108
        // Reopened at 130: what is left is shown where it was, nothing since.
        let reopened = history.runs(at: 130)
        #expect(reopened.count == 1)
        #expect(reopened[0].count == 5)
        #expect(abs((reopened[0].last?.x ?? 0) - (1 - 22.0 / 60)) < 1e-12)
        history.add(0.5, at: 130.5)
        history.add(0.5, at: 132.5)
        let runs = history.runs(at: 132.5)
        #expect(runs.map(\.count) == [5, 2])
        #expect(runs[1].map(\.value) == [0.5, 0.5])
    }

    @Test func readingsOlderThanTheSpanAreDropped() {
        var history = SystemHistory()
        for step in 0..<40 { history.add(Double(step) / 40, at: Double(step) * 2) }   // 0...78
        #expect(history.samples.count == 31)                                            // 18...78
        #expect(history.samples.first?.time == 18)
        #expect(history.runs(at: 78)[0].first?.x == 0)
        history.trim(at: 200)
        #expect(history.samples.isEmpty)
        #expect(history.runs(at: 200).isEmpty)
    }

    @Test func timerJitterDoesNotBreakTheLine() {
        var history = SystemHistory()
        for time in [10.0, 12.4, 13.9, 16.8, 21.7] { history.add(0.1, at: time) }
        #expect(history.runs(at: 21.7).count == 1)
        history.add(0.1, at: 26.8)                                                      // more than the gap
        #expect(history.runs(at: 26.8).map(\.count) == [5, 1])
    }

    @Test func valuesAreHeldToTheChartAndAClockGoingBackStartsAgain() {
        var history = SystemHistory()
        history.add(1.4, at: 10)
        history.add(-0.2, at: 12)
        #expect(history.runs(at: 12)[0].map(\.value) == [1, 0])
        history.add(0.5, at: 5)
        #expect(history.samples.count == 1)
        // A reading from after "now" (the view is a moment behind) isn't drawn.
        #expect(history.runs(at: 4).isEmpty)
    }
}

@Suite struct SystemFormatTests {
    @Test func headlinePercentagesAreWhole() {
        #expect(SystemFormat.percent(0.137) == "14%")
        #expect(SystemFormat.percent(0.5291) == "53%")
        #expect(SystemFormat.percent(0) == "0%")
        #expect(SystemFormat.percent(1.2) == "100%")
        #expect(SystemFormat.percent(.nan) == "0%")
    }

    @Test func aProcessShareHasOneDecimalBelowAHundred() {
        #expect(SystemFormat.processCPU(9.84) == "9.8%")
        #expect(SystemFormat.processCPU(0) == "0.0%")
        #expect(SystemFormat.processCPU(99.94) == "99.9%")
        #expect(SystemFormat.processCPU(99.96) == "100%")
        #expect(SystemFormat.processCPU(212.4) == "212%")
    }

    @Test func memoryIsInMegabytesThenGigabytes() {
        #expect(SystemFormat.memory(612 * 1_048_576) == "612 MB")
        #expect(SystemFormat.memory(3.2 * 1_073_741_824) == "3.2 GB")
        #expect(SystemFormat.memory(999.4 * 1_048_576) == "999 MB")
        #expect(SystemFormat.memory(999.6 * 1_048_576) == "1.0 GB")
        #expect(SystemFormat.memory(0) == "0 MB")
        #expect(SystemFormat.gigabytes(8_697_308_774) == "8.1")
        #expect(SystemFormat.gigabytes(12_133_283_430) == "11.3")
    }

    @Test func uptimeShowsItsTwoLargestUnits() {
        #expect(SystemFormat.uptime(6 * 3600 + 53 * 60 + 40) == "6h 53m")
        #expect(SystemFormat.uptime(53 * 60) == "53m")
        #expect(SystemFormat.uptime(20) == "0m")
        #expect(SystemFormat.uptime(3 * 86400 + 4 * 3600 + 59 * 60) == "3d 4h")
        #expect(SystemFormat.uptime(-5) == "0m")
    }

    @Test func theNoteIsWrittenWithADecimalPoint() {
        #expect(SystemFormat.load(1.856) == "1.86")
        #expect(SystemFormat.load(12) == "12.00")
        #expect(SystemFormat.note(uptime: 6 * 3600 + 53 * 60, load: 1.86) == "up 6h 53m · load 1.86")
    }
}
