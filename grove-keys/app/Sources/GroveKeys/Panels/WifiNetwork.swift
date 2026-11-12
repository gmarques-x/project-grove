import AppKit
import CoreWLAN
import Darwin
import GroveKeysCore
import SystemConfiguration

// What the Wi-Fi panel reads from the Mac and runs on it: the link and its
// addresses, the interface's byte counters, the Wi-Fi switch, the speed
// test's process and nettop's. Everything here works off the main thread
// and answers on it; what it parses and computes is in GroveKeysCore
// (`WifiLink`, `WifiRate`, `WifiSpeedTest`, `WifiApps`, `WifiPower`).

/// The network as the panel shows it, at one moment.
struct WifiSnapshot: Equatable, Sendable {
    var link: WifiLink
    var ip: WifiAddress?
    var router: WifiAddress?
    var dns: WifiAddress?
    /// The default route's interface ("en0"); nil when offline.
    var primaryInterface: String?
    /// The Wi-Fi interface; nil on a Mac without Wi-Fi (no switch then).
    var wifiInterface: String?
    var wifiOn: Bool

    /// Which network a speed test's result belongs to.
    var network: String { link.identity(router: router?.shown) }

    /// Reads it: the dynamic store (a local call to configd), CoreWLAN for
    /// the Wi-Fi interface and its power, and the network's name from the
    /// file `WifiNameWriter` keeps for the bar (the one place that asks
    /// macOS for the name, which needs Location). Not on the main thread.
    static func read() -> WifiSnapshot {
        let store = SCDynamicStoreCreate(nil, "com.projectgrove.keys.wifi-panel" as CFString, nil, nil)
        func value(_ key: String) -> [String: Any] {
            guard let store else { return [:] }
            return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] ?? [:]
        }
        let global = value("State:/Network/Global/IPv4")
        let primary = global["PrimaryInterface"] as? String
        let wifi = CWWiFiClient.shared().interface()
        let wifiInterface = wifi?.interfaceName
        let wifiOn = wifi?.powerOn() ?? false
        let isWifi = primary != nil && primary == wifiInterface
        let isTunnel = primary.map(WifiLink.isTunnel) ?? false
        let service = isTunnel ? (global["PrimaryService"] as? String).flatMap {
            value("Setup:/Network/Service/\($0)")["UserDefinedName"] as? String
        } : nil
        let facts = WifiLink.Facts(primaryInterface: primary, wifiInterface: wifiInterface, wifiOn: wifiOn,
                                   wifiName: isWifi ? wifiName() : nil, serviceName: service)
        let addresses = primary.map { value("State:/Network/Interface/\($0)/IPv4")["Addresses"] as? [String] ?? [] }
        return WifiSnapshot(
            link: WifiLink(facts),
            ip: WifiAddress(addresses ?? []),
            router: WifiAddress([global["Router"] as? String ?? ""]),
            dns: WifiAddress(value("State:/Network/Global/DNS")["ServerAddresses"] as? [String] ?? []),
            primaryInterface: primary, wifiInterface: wifiInterface, wifiOn: wifiOn)
    }

    /// `$GROVE_STATE/wifi-name`, as `WifiNameWriter` wrote it; nil without it.
    private static func wifiName() -> String? {
        let url = WifiName.url(environment: ProcessInfo.processInfo.environment,
                               home: FileManager.default.homeDirectoryForCurrentUser)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return WifiName.sanitize(text.split(whereSeparator: \.isNewline).first.map(String.init))
    }

    /// An interface's bytes in and out since it came up, from `sysctl`
    /// NET_RT_IFLIST2: one small system call. Its fields are 64-bit, but
    /// macOS hands an app the counts cut to 32 bits and rounded to a
    /// kilobyte (measured on 27.2 against `netstat -ib`), so they wrap every
    /// 4 GB: `WifiRate.delta` counts across the wrap.
    static func counters(interface: String) -> (bytesIn: UInt64, bytesOut: UInt64)? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> (UInt64, UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { return nil }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if UInt32(info.ifm_index) == index { return (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes) }
                }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
    }
}

/// Keeps the panel current while it is open: the snapshot again whenever
/// the dynamic store says the network changed, and the primary interface's
/// rates once a second. Everything on one queue; the two handlers are
/// called on the main thread. `start()` and `stop()` pair with the panel's
/// opening and closing: stopped, nothing is left running.
final class WifiWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.projectgrove.keys.wifi-panel", qos: .utility)
    // On `queue` only.
    private var store: SCDynamicStore?
    private var timer: DispatchSourceTimer?
    private var run = 0
    private var interface: String?
    private var last: (interface: String, bytesIn: UInt64, bytesOut: UInt64, at: DispatchTime)?
    private var onSnapshot: (@MainActor (WifiSnapshot) -> Void)?
    private var onTick: (@MainActor ((down: Double, up: Double)?) -> Void)?

    /// - `onSnapshot`: the network, now and after each change.
    /// - `onTick`: once a second, the rates in bytes a second; nil for the
    ///   first tick and when there is no interface to count on.
    func start(onSnapshot: @escaping @MainActor (WifiSnapshot) -> Void,
               onTick: @escaping @MainActor ((down: Double, up: Double)?) -> Void) {
        queue.async { [self] in
            teardown()
            run += 1
            self.onSnapshot = onSnapshot
            self.onTick = onTick
            watchStore()
            refresh()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [self] in teardown() }
    }

    /// The snapshot again, soon (after the Wi-Fi switch was flipped).
    func refreshSoon() {
        queue.async { [self] in
            let run = self.run
            queue.asyncAfter(deadline: .now() + 1) { [self] in
                if run == self.run, timer != nil { refresh() }
            }
        }
    }

    private func teardown() {
        timer?.cancel()
        timer = nil
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
            self.store = nil
        }
        run += 1
        last = nil
        onSnapshot = nil
        onTick = nil
    }

    private func watchStore() {
        // The store keeps `self` until `teardown` lets the store go.
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { UnsafeRawPointer(Unmanaged<WifiWatcher>.fromOpaque($0).retain().toOpaque()) },
            release: { Unmanaged<WifiWatcher>.fromOpaque($0).release() },
            copyDescription: nil)
        let changed: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<WifiWatcher>.fromOpaque(info).takeUnretainedValue().storeChanged()
        }
        guard let store = SCDynamicStoreCreate(nil, "com.projectgrove.keys.wifi-panel.watch" as CFString, changed,
                                               &context) else { return }
        let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/DNS"] as CFArray
        // An address, a link going up or down, Wi-Fi's power and network.
        let patterns = ["State:/Network/Interface/[^/]+/(IPv4|Link|AirPort)"] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns),
              SCDynamicStoreSetDispatchQueue(store, queue) else { return }
        self.store = store
    }

    /// On `queue`. The name's file is rewritten by `WifiNameWriter` a
    /// moment after the same change: look again a second later.
    private func storeChanged() {
        guard timer != nil else { return }
        refresh()
        let run = self.run
        queue.asyncAfter(deadline: .now() + 1) { [self] in
            if run == self.run { refresh() }
        }
    }

    private func refresh() {
        let snapshot = WifiSnapshot.read()
        interface = snapshot.primaryInterface
        guard let onSnapshot else { return }
        DispatchQueue.main.async { onSnapshot(snapshot) }
    }

    private func tick() {
        guard let onTick else { return }
        var rates: (down: Double, up: Double)?
        if let interface, let now = WifiSnapshot.counters(interface: interface) {
            let at = DispatchTime.now()
            if let last, last.interface == interface {
                let seconds = Double(at.uptimeNanoseconds - last.at.uptimeNanoseconds) / 1e9
                rates = (WifiRate.rate(from: last.bytesIn, to: now.bytesIn, seconds: seconds),
                         WifiRate.rate(from: last.bytesOut, to: now.bytesOut, seconds: seconds))
            }
            last = (interface, now.bytesIn, now.bytesOut, at)
        } else {
            last = nil
        }
        DispatchQueue.main.async { onTick(rates) }
    }
}

// MARK: The Wi-Fi switch

/// CoreWLAN's own switch; throws where the system wants rights for it.
struct WifiCoreWLANSwitch: WifiPowerSwitch {
    struct NoInterface: Error {}

    func setPower(_ on: Bool, interface: String) throws {
        guard let wifi = CWWiFiClient.shared().interface(withName: interface) else { throw NoInterface() }
        try wifi.setPower(on)
    }
}

/// `/usr/sbin/networksetup -setairportpower <interface> on|off`, the
/// fallback. It says nothing when it worked.
struct WifiNetworksetupSwitch: WifiPowerSwitch {
    struct Refused: Error {}

    func setPower(_ on: Bool, interface: String) throws {
        guard WifiPower.isInterfaceName(interface) else { throw Refused() }
        let result = Subprocess.run("/usr/sbin/networksetup", WifiPower.networksetupArguments(on, interface: interface),
                                    timeout: 5)
        let said = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !result.timedOut, said.isEmpty else { throw Refused() }
    }
}

// MARK: The speed test

/// The speed test, app-wide: `/usr/bin/networkQuality -c` as a child
/// process that outlives the panel (which closes at any click elsewhere;
/// reopened, it shows the test still running, or its result). The last
/// result is kept in memory with its time and its network. Nothing starts
/// a test but `start`; the child is ended on Cancel, after a minute, and
/// when the app quits.
@MainActor
final class WifiSpeedController: ObservableObject {
    static let shared = WifiSpeedController(state: .idle, live: true)

    @Published private(set) var state: WifiSpeedState
    private var process: Process?
    /// Counts runs, so a child that was cancelled can't report.
    private var run = 0
    /// What a cancelled run comes back to.
    private var before = WifiSpeedState.idle
    private var quitting: NSObjectProtocol?

    /// `live` false: a fixed state for the sample render; it runs nothing.
    init(state: WifiSpeedState, live: Bool) {
        self.state = state
        guard live else { return }
        quitting = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.process?.terminate() }
        }
    }

    /// Starts a test on `network` (see `WifiSnapshot.network`), unless one
    /// is running.
    func start(network: String) {
        guard !state.isRunning, quitting != nil else { return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: WifiSpeedTest.tool)
        child.arguments = WifiSpeedTest.arguments
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            state = .failed(WifiSpeedTest.failureLine)
            return
        }
        run += 1
        let run = self.run
        before = state
        process = child
        state = .running(since: Date())
        let handle = pipe.fileHandleForReading
        let box = ProcessBox(child)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = handle.readDataToEndOfFile()
            box.process.waitUntilExit()
            DispatchQueue.main.async { [weak self] in self?.ended(run, output: output, network: network) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + WifiSpeedTest.timeout) { [weak self] in
            guard let self, self.run == run, self.state.isRunning else { return }
            self.run += 1
            self.process?.terminate()
            self.process = nil
            self.state = .failed(WifiSpeedTest.failureLine)
        }
    }

    /// Ends the running test; the panel shows what it showed before it.
    func cancel() {
        guard state.isRunning else { return }
        run += 1
        process?.terminate()
        process = nil
        state = before
    }

    /// The Mac is on `network` now: a result measured on another goes.
    func networkIs(_ network: String) {
        let next = state.on(network: network)
        if next != state { state = next }
        before = before.on(network: network)
    }

    private func ended(_ run: Int, output: Data, network: String) {
        guard run == self.run else { return }
        process = nil
        if let result = WifiSpeedResult(json: output) {
            state = .result(result, at: Date(), network: network)
        } else {
            state = .failed(WifiSpeedTest.failureLine)
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }
}

// MARK: Who is using the network

/// Runs `nettop` over and over while "Show apps" is open, and hands each
/// run's top three to the main thread (one run, one update: about 5 s).
/// `stop()` ends the child at once; stopped, nothing runs.
final class WifiAppsSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.projectgrove.keys.wifi-apps", qos: .utility)
    private let lock = NSLock()
    // Under `lock`.
    private var run = 0
    private var process: Process?

    func start(_ handler: @escaping @MainActor ([WifiApps.App]) -> Void) {
        let run: Int = lock.withLock {
            self.run += 1
            process?.terminate()
            return self.run
        }
        queue.async { [self] in
            while isCurrent(run) {
                guard let output = sample(run) else {
                    // The tool didn't run or was stopped: not in a tight loop.
                    Thread.sleep(forTimeInterval: 2)
                    continue
                }
                let rates = WifiApps.rates(WifiApps.parse(output), seconds: WifiApps.span)
                let apps = WifiApps.top(rates, path: Self.path)
                guard isCurrent(run) else { return }
                DispatchQueue.main.async { handler(apps) }
            }
        }
    }

    func stop() {
        lock.withLock {
            run += 1
            process?.terminate()
            process = nil
        }
    }

    private func isCurrent(_ run: Int) -> Bool {
        lock.withLock { run == self.run }
    }

    /// One run of nettop; nil when it couldn't run, failed or was stopped.
    private func sample(_ run: Int) -> String? {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: WifiApps.tool)
        child.arguments = WifiApps.arguments
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        let started: Bool = lock.withLock {
            guard run == self.run, (try? child.run()) != nil else { return false }
            process = child
            return true
        }
        guard started else { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        lock.withLock { if process === child { process = nil } }
        guard child.terminationStatus == 0, child.terminationReason == .exit, !output.isEmpty else { return nil }
        return String(decoding: output, as: UTF8.self)
    }

    /// A process's executable, for its app's name; nil for one that isn't
    /// the user's (macOS doesn't say).
    private static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
