import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct WifiRateTests {
    @Test func ratesAreWrittenInDecimalUnits() {
        #expect(WifiRate.format(0) == "0 KB/s")
        #expect(WifiRate.format(400) == "0 KB/s")
        #expect(WifiRate.format(348_000) == "348 KB/s")
        #expect(WifiRate.format(999_400) == "999 KB/s")
        #expect(WifiRate.format(999_600) == "1.0 MB/s")
        #expect(WifiRate.format(2_100_000) == "2.1 MB/s")
        #expect(WifiRate.format(1_640_000) == "1.6 MB/s")
        #expect(WifiRate.format(99_960_000) == "100 MB/s")
        #expect(WifiRate.format(412_000_000) == "412 MB/s")
        #expect(WifiRate.format(1_240_000_000) == "1.2 GB/s")
    }

    @Test func oddReadingsAreZero() {
        #expect(WifiRate.format(-5) == "0 KB/s")
        #expect(WifiRate.format(.nan) == "0 KB/s")
        #expect(WifiRate.format(.infinity) == "0 KB/s")
    }

    /// The text is built from whole numbers, so no locale's comma gets in.
    @Test func theDecimalMarkIsAPoint() {
        #expect(!WifiRate.format(2_150_000).contains(","))
        #expect(WifiRate.format(2_150_000).contains("."))
    }

    @Test func aCounterThatWrapsAt32BitsStillCounts() {
        #expect(WifiRate.delta(from: 100, to: 350) == 250)
        #expect(WifiRate.delta(from: UInt64(UInt32.max) - 9, to: 20) == 30)
        // A 64-bit counter that went backwards started again.
        #expect(WifiRate.delta(from: 10_000_000_000, to: 5) == 0)
        #expect(WifiRate.rate(from: 1000, to: 3000, seconds: 2) == 1000)
        #expect(WifiRate.rate(from: 1000, to: 3000, seconds: 0) == 0)
    }

    @Test func historyHoldsAMinuteAndStartsAbsent() {
        var history = WifiHistory()
        #expect(history.down.count == 60 && history.down.allSatisfy { $0 == nil })
        history.add(down: 100_000, up: 25_000)
        history.add(down: 200_000, up: 50_000)
        #expect(history.down.suffix(3) == [nil, 100_000, 200_000])
        #expect(WifiHistory.runs(history.down) == [58..<60])
        for _ in 0..<70 { history.add(down: 1, up: 1) }
        #expect(history.down.count == 60 && history.up.count == 60)
        #expect(WifiHistory.runs(history.down) == [0..<60])
    }

    @Test func bothLinesShareOneScale() {
        var history = WifiHistory()
        history.add(down: 200_000, up: 50_000)
        let lines = history.normalized
        #expect(lines.down.last == 1 && lines.up.last == 0.25 && lines.down.first == .some(nil))
        // A quiet minute isn't stretched to the full height.
        var quiet = WifiHistory()
        quiet.add(down: 5_000, up: 0)
        #expect(quiet.normalized.down.last == 0.1)
    }

    @Test func runsSkipTheGaps() {
        #expect(WifiHistory.runs([nil, 1, 2, nil, 3, nil]) == [1..<3, 4..<5])
        #expect(WifiHistory.runs([]) == [])
    }
}

@Suite struct WifiLinkTests {
    static func facts(_ primary: String?, wifiOn: Bool = true, name: String? = "Grove-5G", service: String? = nil)
        -> WifiLink.Facts {
        WifiLink.Facts(primaryInterface: primary, wifiInterface: "en0", wifiOn: wifiOn, wifiName: name,
                       serviceName: service)
    }

    @Test func theLinkFollowsThePrimaryInterface() {
        #expect(WifiLink(Self.facts("en0")) == .wifi(name: "Grove-5G"))
        #expect(WifiLink(Self.facts("en0", name: nil)) == .wifi(name: nil))
        #expect(WifiLink(Self.facts("en7")) == .ethernet)
        #expect(WifiLink(Self.facts("utun4", service: "Grove VPN")) == .vpn(name: "Grove VPN"))
        #expect(WifiLink(Self.facts("ipsec0")) == .vpn(name: nil))
        #expect(WifiLink(Self.facts("ppp0")) == .vpn(name: nil))
        #expect(WifiLink(Self.facts(nil)) == .offline(wifiOn: true))
        #expect(WifiLink(Self.facts(nil, wifiOn: false)) == .offline(wifiOn: false))
        #expect(WifiLink(Self.facts("")) == .offline(wifiOn: true))
    }

    @Test func onlyTunnelNamesAreTunnels() {
        #expect(WifiLink.isTunnel("utun0") && WifiLink.isTunnel("utun12") && WifiLink.isTunnel("ipsec0"))
        #expect(!WifiLink.isTunnel("en0") && !WifiLink.isTunnel("utun") && !WifiLink.isTunnel("pppoe") )
        #expect(!WifiLink.isTunnel("bridge0") && !WifiLink.isTunnel("tunnel"))
    }

    @Test func titlesAndNotes() {
        #expect(WifiLink.wifi(name: "Grove-5G").title == "Grove-5G")
        #expect(WifiLink.wifi(name: nil).title == "Wi-Fi")
        #expect(WifiLink.ethernet.title == "Ethernet")
        #expect(WifiLink.vpn(name: "Grove-5G").title == "VPN · Grove-5G")
        #expect(WifiLink.vpn(name: nil).title == "VPN")
        #expect(WifiLink.offline(wifiOn: true).title == "Offline")
        #expect(WifiLink.offline(wifiOn: true).note == "Not connected")
        #expect(WifiLink.offline(wifiOn: false).note == "Wi-Fi is off")
        #expect(WifiLink.ethernet.note == nil)
    }

    @Test func aNamePassesThroughTheBarsCleaning() {
        #expect(WifiLink(Self.facts("en0", name: "  Grove\n5G ")) == .wifi(name: "Grove5G"))
        #expect(WifiLink(Self.facts("utun0", service: "\u{202E}")) == .vpn(name: nil))
    }

    @Test func settingsFollowTheLink() {
        #expect(WifiLink.wifi(name: nil).settings.url == "x-apple.systempreferences:com.apple.wifi-settings-extension")
        #expect(WifiLink.offline(wifiOn: false).settings.title == "Wi-Fi Settings…")
        #expect(WifiLink.ethernet.settings.url == "x-apple.systempreferences:com.apple.Network-Settings.extension")
        #expect(WifiLink.vpn(name: nil).settings.title == "Network Settings…")
        #expect(URL(string: WifiLink.ethernet.settings.url) != nil)
    }

    @Test func aNetworkIsItsKindNameAndRouter() {
        let home = WifiLink.wifi(name: "Grove-5G").identity(router: "192.168.150.1")
        #expect(home == WifiLink.wifi(name: "Grove-5G").identity(router: "192.168.150.1"))
        #expect(home != WifiLink.wifi(name: "Cafe").identity(router: "192.168.150.1"))
        #expect(home != WifiLink.wifi(name: "Grove-5G").identity(router: "10.0.0.1"))
        #expect(home != WifiLink.ethernet.identity(router: "192.168.150.1"))
        #expect(WifiLink.offline(wifiOn: true).identity(router: nil) == "offline")
    }

    @Test func addressesShowTheFirstAndCopyAll() {
        #expect(WifiAddress([]) == nil)
        #expect(WifiAddress(["", " "]) == nil)
        let one = WifiAddress(["192.168.150.1"])
        #expect(one?.shown == "192.168.150.1" && one?.more == nil && one?.copied == "192.168.150.1")
        // macOS lists a server once per resolver.
        let twice = WifiAddress(["192.168.150.1", "192.168.150.1"])
        #expect(twice?.more == nil && twice?.copied == "192.168.150.1")
        let three = WifiAddress(["1.1.1.1", "8.8.8.8", "1.1.1.1", "9.9.9.9"])
        #expect(three?.shown == "1.1.1.1" && three?.more == "+2" && three?.copied == "1.1.1.1\n8.8.8.8\n9.9.9.9")
    }
}

@Suite struct WifiPowerTests {
    final class Fake: WifiPowerSwitch {
        struct Refused: Error {}
        let works: Bool
        var calls: [(on: Bool, interface: String)] = []
        init(works: Bool) { self.works = works }
        func setPower(_ on: Bool, interface: String) throws {
            calls.append((on, interface))
            if !works { throw Refused() }
        }
    }

    @Test func theFirstWayThatWorksIsEnough() {
        let first = Fake(works: true), second = Fake(works: true)
        #expect(WifiPower.set(false, interface: "en0", using: [first, second]) == .switched)
        #expect(first.calls.count == 1 && first.calls[0].on == false && first.calls[0].interface == "en0")
        #expect(second.calls.isEmpty)
    }

    @Test func aRefusalFallsBackToTheNextWay() {
        let first = Fake(works: false), second = Fake(works: true)
        #expect(WifiPower.set(true, interface: "en1", using: [first, second]) == .switched)
        #expect(first.calls.count == 1 && second.calls.count == 1 && second.calls[0].on)
    }

    @Test func whenNothingWorksItFails() {
        #expect(WifiPower.set(true, interface: "en0", using: [Fake(works: false), Fake(works: false)]) == .failed)
        #expect(WifiPower.set(true, interface: "en0", using: []) == .failed)
    }

    @Test func networksetupIsGivenOnlyAnInterfaceName() {
        #expect(WifiPower.networksetupArguments(true, interface: "en0") == ["-setairportpower", "en0", "on"])
        #expect(WifiPower.networksetupArguments(false, interface: "en0") == ["-setairportpower", "en0", "off"])
        #expect(WifiPower.isInterfaceName("en0") && WifiPower.isInterfaceName("bridge100"))
        #expect(!WifiPower.isInterfaceName("") && !WifiPower.isInterfaceName("en0 off") && !WifiPower.isInterfaceName("-x"))
    }
}

@Suite struct WifiSpeedTestTests {
    /// `networkQuality -c` on macOS 27.2, 2026-11-12 (download and upload together).
    @Test func theRealOutputParses() throws {
        let result = try #require(WifiSpeedResult(json: Data(try fixture("wifi-networkquality.json").utf8)))
        #expect(result.down == 879_510_592 && result.up == 512_002_400)
        #expect(result.downText == "880 Mbps" && result.upText == "512 Mbps")
        #expect(result.delayText == "23 ms")
    }

    /// The same with `-s`: no "responsiveness", one per direction instead.
    @Test func theSequentialOutputParsesToo() throws {
        let result = try #require(WifiSpeedResult(json: Data(try fixture("wifi-networkquality-sequential.json").utf8)))
        #expect(result.downText == "879 Mbps" && result.upText == "803 Mbps" && result.delayText == "21 ms")
    }

    @Test func withoutTheIdleDelayTheScoreIsShownAsRPM() {
        let both = WifiSpeedResult(json: Data(#"{"dl_throughput": 412000000, "ul_throughput": 38000000, "responsiveness": 916.04}"#.utf8))
        #expect(both?.delay == .rpm(916.04) && both?.delayText == "916 RPM")
        let perDirection = WifiSpeedResult(json: Data(#"{"dl_throughput": 1, "ul_throughput": 1, "dl_responsiveness": 1213.9}"#.utf8))
        #expect(perDirection?.delayText == "1214 RPM")
        let neither = WifiSpeedResult(json: Data(#"{"dl_throughput": 412000000, "ul_throughput": 38000000}"#.utf8))
        #expect(neither != nil && neither?.delayText == nil)
    }

    @Test func whatIsNotAResultIsNil() {
        #expect(WifiSpeedResult(json: Data()) == nil)
        #expect(WifiSpeedResult(json: Data("networkQuality: offline".utf8)) == nil)
        #expect(WifiSpeedResult(json: Data(#"{"base_rtt": 12}"#.utf8)) == nil)
        #expect(WifiSpeedResult(json: Data(#"{"dl_throughput": "fast", "ul_throughput": 1}"#.utf8)) == nil)
        #expect(WifiSpeedResult(json: Data(#"[1, 2]"#.utf8)) == nil)
    }

    @Test func speedsAreWrittenInMegabits() {
        #expect(WifiSpeedResult.format(bitsPerSecond: 412_000_000) == "412 Mbps")
        #expect(WifiSpeedResult.format(bitsPerSecond: 38_400_000) == "38 Mbps")
        #expect(WifiSpeedResult.format(bitsPerSecond: 9_400_000) == "9.4 Mbps")
        #expect(WifiSpeedResult.format(bitsPerSecond: 9_960_000) == "10 Mbps")
        #expect(WifiSpeedResult.format(bitsPerSecond: 420_000) == "0.4 Mbps")
        #expect(WifiSpeedResult.format(bitsPerSecond: 1_240_000_000) == "1.2 Gbps")
        #expect(WifiSpeedResult.format(bitsPerSecond: 0) == "0 Mbps")
        #expect(WifiSpeedResult(down: 0, up: 0, delay: .milliseconds(0.2)).delayText == "1 ms")
        #expect(WifiSpeedResult(down: 0, up: 0, delay: .milliseconds(11.6)).delayText == "12 ms")
    }

    @Test func theBarIsTimePassedAndNeverQuiteFull() {
        #expect(WifiSpeedTest.progress(elapsed: 0) == 0)
        #expect(WifiSpeedTest.progress(elapsed: -3) == 0)
        #expect(WifiSpeedTest.progress(elapsed: 7.5) == 0.5)
        #expect(WifiSpeedTest.progress(elapsed: 40) == 0.97)
    }

    @Test func ages() {
        #expect(WifiSpeedTest.age(0) == "just now")
        #expect(WifiSpeedTest.age(59) == "just now")
        #expect(WifiSpeedTest.age(125) == "2 min ago")
        #expect(WifiSpeedTest.age(3599) == "59 min ago")
        #expect(WifiSpeedTest.age(3 * 3600 + 5) == "3 h ago")
        #expect(WifiSpeedTest.age(-10) == "just now")
    }

    @Test func aResultIsForgottenOnAnotherNetwork() {
        let result = WifiSpeedResult(down: 1, up: 1, delay: nil), at = Date(timeIntervalSince1970: 0)
        let state = WifiSpeedState.result(result, at: at, network: "wifi:Grove-5G|192.168.150.1")
        #expect(state.on(network: "wifi:Grove-5G|192.168.150.1") == state)
        #expect(state.on(network: "wifi:Cafe|10.0.0.1") == .idle)
        #expect(state.on(network: "offline") == .idle)
        let running = WifiSpeedState.running(since: at)
        #expect(running.on(network: "offline") == running && running.isRunning)
        #expect(WifiSpeedState.failed("x").on(network: "offline") == .failed("x"))
    }

    @Test func theToolIsRunForJSON() {
        #expect(WifiSpeedTest.tool == "/usr/bin/networkQuality")
        #expect(WifiSpeedTest.arguments == ["-c"])
    }
}

@Suite struct WifiAppsTests {
    /// `nettop -P -L 5 -s 1 -x -t external -J bytes_in,bytes_out` on macOS 27.2, 2026-11-12.
    static func readings() throws -> [[WifiApps.Reading]] { WifiApps.parse(try fixture("wifi-nettop.csv")) }

    @Test func theRealOutputParsesIntoItsReadings() throws {
        let readings = try Self.readings()
        #expect(readings.count == 5)
        #expect(readings.allSatisfy { $0.count == 8 })
        #expect(readings[0][0] == WifiApps.Reading(name: "apsd", pid: 378, bytesIn: 160_817, bytesOut: 462_821))
        // Names with spaces and with dots keep them; the pid is what follows the last dot.
        #expect(readings[0].contains { $0.name == "Google Chrome H" && $0.pid == 752 })
        #expect(readings[0].contains { $0.name == "2.1.322" && $0.pid == 9202 })
    }

    @Test func ratesAreTheFirstReadingAgainstTheLast() throws {
        let readings = try Self.readings()
        let rates = WifiApps.rates(readings, seconds: WifiApps.span)
        let first = try #require(readings.first?.first { $0.pid == 483 })
        let last = try #require(readings.last?.first { $0.pid == 483 })
        let moved = Double((last.bytesIn - first.bytesIn) + (last.bytesOut - first.bytesOut))
        #expect(rates.first { $0.reading.pid == 483 }?.rate == moved / 4)
        // apsd moved nothing in those seconds.
        #expect(rates.first { $0.reading.pid == 378 }?.rate == 0)
    }

    @Test func oddLinesAndOddCountsAreLeftOut() {
        let output = """
        ,bytes_in,bytes_out,
        a.1,100,100,
        gone.2,5,5,
        back.3,900,900,
        A, Inc. tool.4,10,0,
        nonsense
        nopid,1,2,
        ,bytes_in,bytes_out,
        a.1,300,200,
        back.3,10,10,
        new.5,7,7,
        A, Inc. tool.4,50,0,
        """
        let readings = WifiApps.parse(output)
        #expect(readings.map(\.count) == [4, 4])
        let rates = WifiApps.rates(readings, seconds: 1)
        #expect(rates.map(\.reading.name) == ["a", "A, Inc. tool"])
        #expect(rates.map(\.rate) == [300, 40])
        #expect(WifiApps.rates([readings[0]], seconds: 1).isEmpty)
        #expect(WifiApps.rates(readings, seconds: 0).isEmpty)
        #expect(WifiApps.parse("").isEmpty)
        // A line before any header belongs to no reading.
        #expect(WifiApps.parse("a.1,1,1,\n").isEmpty)
    }

    @Test func namesAreCleaned() {
        #expect(WifiApps.appName(process: "Google Chrome H") == "Google Chrome")
        #expect(WifiApps.appName(process: "Claude Helper") == "Claude")
        #expect(WifiApps.appName(process: "Code Helper (Renderer)") == "Code")
        #expect(WifiApps.appName(process: "Slack Helper (G") == "Slack")
        #expect(WifiApps.appName(process: "Ghostty") == "Ghostty")
        #expect(WifiApps.appName(process: "mDNSResponder") == "mDNSResponder")
        // Only a name nettop cut at 15 characters loses its " H".
        #expect(WifiApps.appName(process: "Plan H") == "Plan H")
    }

    @Test func thePathSaysWhichAppAHelperBelongsTo() {
        let chrome = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/157.0.8103.51/Helpers/Google Chrome Helper (Aperitif).app/Contents/MacOS/Google Chrome Helper (Aperitif)"
        #expect(WifiApps.appName(process: "Google Chrome H", path: chrome) == "Google Chrome")
        #expect(WifiApps.appName(process: "2.1.322", path: "/Users/someone/.local/share/claude/versions/2.1.322") == "claude")
        #expect(WifiApps.appName(process: "com.apple.WebKi", path: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking") == "com.apple.WebKit.Networking")
        #expect(WifiApps.appName(process: "mDNSResponder", path: "/usr/sbin/mDNSResponder") == "mDNSResponder")
        #expect(WifiApps.appName(process: "apsd", path: nil) == "apsd")
    }

    @Test func helpersAreSummedAndTheTopThreeKept() {
        func reading(_ name: String, _ pid: Int32) -> WifiApps.Reading {
            WifiApps.Reading(name: name, pid: pid, bytesIn: 0, bytesOut: 0)
        }
        let rates: [(reading: WifiApps.Reading, rate: Double)] = [
            (reading("Google Chrome H", 1), 900_000), (reading("Google Chrome", 2), 700_000),
            (reading("2.1.322", 3), 410_000), (reading("Ghostty", 4), 38_000),
            (reading("apsd", 5), 1_000), (reading("idle", 6), 0),
        ]
        let top = WifiApps.top(rates) { $0 == 3 ? "/Users/someone/.local/share/claude/versions/2.1.322" : nil }
        #expect(top == [WifiApps.App(name: "Google Chrome", rate: 1_600_000), WifiApps.App(name: "claude", rate: 410_000),
                        WifiApps.App(name: "Ghostty", rate: 38_000)])
        #expect(top.map { WifiRate.format($0.rate) } == ["1.6 MB/s", "410 KB/s", "38 KB/s"])
        #expect(WifiApps.top([(reading("idle", 6), 0)]).isEmpty)
        #expect(WifiApps.top(rates, count: 1).map(\.name) == ["Google Chrome"])
    }

    @Test func theRealRunHasATopThree() throws {
        let top = WifiApps.top(WifiApps.rates(try Self.readings(), seconds: WifiApps.span))
        #expect(!top.isEmpty && top.count <= 3)
        #expect(top == top.sorted { $0.rate > $1.rate })
        #expect(top.allSatisfy { $0.rate > 0 })
    }

    @Test func theToolIsAskedForCSVPerProcess() {
        #expect(WifiApps.tool == "/usr/bin/nettop")
        #expect(WifiApps.arguments == ["-P", "-L", "5", "-s", "1", "-x", "-t", "external", "-J", "bytes_in,bytes_out"])
    }
}
