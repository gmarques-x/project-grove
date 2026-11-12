import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// Wi-Fi & network (spec 2026-11-12-bar-panels-design §6): "am I online, how
// fast, what's my address?". The link's name and the Wi-Fi switch; the live
// rates over one chart; IP, Router and DNS, which copy on a click; the speed
// test; who is using the network, on request. What it reads and runs is in
// WifiNetwork.swift; what it computes is in GroveKeysCore (Wifi*.swift).

/// The Wi-Fi panel's state. Open, it follows the network (a dynamic-store
/// notification) and reads the primary interface's counters once a second;
/// with "Show apps" open it also runs nettop. Closed, it runs nothing; the
/// speed test belongs to the app (`WifiSpeedController`) and goes on.
@MainActor
final class WifiModel: ObservableObject, BarPanelModel {
    @Published private(set) var snapshot: WifiSnapshot
    /// The last minute, a reading a second; empty at each opening.
    @Published private(set) var history = WifiHistory()
    /// Bytes a second, now; nil until the second reading.
    @Published private(set) var rates: (down: Double, up: Double)?
    /// The panel's clock, a tick a second: the test's bar and its result's age.
    @Published private(set) var now: Date
    @Published private(set) var appsShown = false
    /// The top three; nil while the first reading is being taken.
    @Published private(set) var apps: [WifiApps.App]?
    /// Neither way of switching Wi-Fi worked: said in one line until one does.
    @Published private(set) var switchFailed = false
    /// The address row drawn as under the pointer, in a render ("ip").
    let sampleHover: String?

    let speed: WifiSpeedController
    private let live: Bool
    private var read = false
    private let watcher = WifiWatcher()
    private let appsSampler = WifiAppsSampler()
    private let switching = DispatchQueue(label: "com.projectgrove.keys.wifi-switch", qos: .userInitiated)

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            live = true
            speed = .shared
            now = Date()
            sampleHover = nil
            // Until the first reading (`start()`, before the panel is drawn).
            snapshot = WifiSnapshot(link: .offline(wifiOn: false), ip: nil, router: nil, dns: nil,
                                    primaryInterface: nil, wifiInterface: nil, wifiOn: false)
        case .sample:
            live = false
            // The mock-ups' network. GROVE_WIFI_SAMPLE picks the state: idle
            // (the default), hover (the pointer on IP), running, result,
            // failed, apps, measuring, dns (three servers), ethernet, vpn,
            // offline, off, refused (the switch didn't work).
            let state = ProcessInfo.processInfo.environment["GROVE_WIFI_SAMPLE"] ?? "idle"
            let sample = Self.sample(state)
            now = Self.sampleNow
            snapshot = sample.snapshot
            speed = WifiSpeedController(state: sample.speed, live: false)
            history = Self.sampleHistory
            rates = (2_100_000, 348_000)
            appsShown = state == "apps" || state == "measuring"
            apps = state == "measuring" ? nil : [WifiApps.App(name: "Google Chrome", rate: 1_600_000),
                                                 WifiApps.App(name: "claude", rate: 410_000),
                                                 WifiApps.App(name: "Ghostty", rate: 38_000)]
            switchFailed = state == "refused"
            sampleHover = state == "hover" ? "IP" : nil
        }
    }

    // MARK: Opening and closing

    func start() {
        guard live else { return }
        now = Date()
        history = WifiHistory()
        rates = nil
        appsShown = false
        apps = nil
        if !read {
            // The first opening only: read before the panel is drawn and
            // measured, so it doesn't open as "Offline" and then grow (a
            // few local calls). Later openings start from the last reading.
            took(WifiSnapshot.read())
            read = true
        }
        watcher.start(
            onSnapshot: { [weak self] in self?.took($0) },
            onTick: { [weak self] in self?.ticked($0) })
    }

    func stop() {
        watcher.stop()
        appsSampler.stop()
        appsShown = false
        apps = nil
    }

    private func took(_ snapshot: WifiSnapshot) {
        if snapshot.primaryInterface != self.snapshot.primaryInterface {
            // Another interface's minute isn't this one's.
            history = WifiHistory()
            rates = nil
        }
        if snapshot != self.snapshot { self.snapshot = snapshot }
        speed.networkIs(snapshot.network)
    }

    private func ticked(_ rates: (down: Double, up: Double)?) {
        now = Date()
        self.rates = rates
        if let rates { history.add(down: rates.down, up: rates.up) }
    }

    // MARK: What the controls ask

    /// Switches Wi-Fi: CoreWLAN, then `networksetup`. When neither works
    /// the panel says so and `orElse` opens Wi-Fi Settings.
    func setWifi(_ on: Bool, orElse openSettings: @escaping @MainActor () -> Void) {
        guard live, let interface = snapshot.wifiInterface, on != snapshot.wifiOn else { return }
        snapshot.wifiOn = on
        let watcher = watcher
        switching.async { [weak self] in
            let outcome = WifiPower.set(on, interface: interface,
                                        using: [WifiCoreWLANSwitch(), WifiNetworksetupSwitch()])
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.switchFailed = outcome == .failed
                if outcome == .failed {
                    self.snapshot.wifiOn = !on
                    openSettings()
                } else {
                    watcher.refreshSoon()
                }
            }
        }
    }

    func runSpeedTest() {
        guard live, snapshot.link.isOnline else { return }
        speed.start(network: snapshot.network)
    }

    func cancelSpeedTest() { speed.cancel() }

    /// "Show apps": nettop runs only while it is open (and the panel is).
    func toggleApps() {
        guard live else { return }
        appsShown.toggle()
        apps = nil
        if appsShown {
            appsSampler.start { [weak self] apps in
                guard let self, self.appsShown else { return }
                self.apps = apps
            }
        } else {
            appsSampler.stop()
        }
    }

    func copy(_ text: String) {
        guard live else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: The sample

    /// The day the mock-ups were approved on.
    private static let sampleNow = Date(timeIntervalSince1970: 1_794_449_580)

    private static func sample(_ state: String) -> (snapshot: WifiSnapshot, speed: WifiSpeedState) {
        var link = WifiLink.wifi(name: "Grove-5G"), wifiOn = true
        var dns = ["192.168.150.1"]
        var speed = WifiSpeedState.idle
        let result = WifiSpeedResult(down: 412_000_000, up: 38_000_000, delay: .milliseconds(12))
        switch state {
        case "running": speed = .running(since: sampleNow.addingTimeInterval(-6))
        case "result", "apps", "measuring":
            speed = .result(result, at: sampleNow.addingTimeInterval(-130), network: "")
        case "failed": speed = .failed(WifiSpeedTest.failureLine)
        case "dns": dns = ["192.168.150.1", "1.1.1.1", "9.9.9.9"]
        case "ethernet": (link, wifiOn) = (.ethernet, false)
        case "vpn": link = .vpn(name: "Grove-5G")
        case "offline": link = .offline(wifiOn: true)
        case "off": (link, wifiOn) = (.offline(wifiOn: false), false)
        default: break
        }
        let online = link.isOnline
        return (WifiSnapshot(link: link, ip: online ? WifiAddress(["192.168.150.158"]) : nil,
                             router: online ? WifiAddress(["192.168.150.1"]) : nil,
                             dns: online ? WifiAddress(dns) : nil,
                             primaryInterface: online ? "en0" : nil, wifiInterface: "en0", wifiOn: wifiOn), speed)
    }

    /// A minute that wanders about 0.6 MB/s down with a burst to 2.1, and a
    /// tenth of it up: repeatable (a fixed seed), newest last.
    private static var sampleHistory: WifiHistory {
        var state: UInt64 = 3
        func wander() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 1000) / 1000 - 0.5
        }
        let bursts: [Int: Double] = [27: 0.6, 28: 1.2, 29: 1.5, 30: 1.1, 31: 0.3, 50: 0.4, 51: 0.5, 52: 0.2]
        var down: [Double] = [], up: [Double] = []
        var level = 0.6
        for index in 0..<WifiHistory.length {
            level = min(0.8, max(0.4, level + wander() * 0.12))
            let burst = bursts[index] ?? 0
            down.append((level + burst) * 1_000_000)
            up.append((0.16 + wander() * 0.06 + burst * 0.15) * 1_000_000)
        }
        return WifiHistory(down: down, up: up)
    }
}

struct WifiPanel: View {
    static let width: CGFloat = 320
    static let registration = BarPanelRegistration("wifi", pill: "pill.wifi", width: width,
                                                   model: WifiModel.init) { WifiPanel(model: $0) }

    @ObservedObject var model: WifiModel
    @ObservedObject private var speed: WifiSpeedController
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: WifiModel) {
        self.model = model
        speed = model.speed
    }

    private var link: WifiLink { model.snapshot.link }

    var body: some View {
        BarPanel(width: Self.width) {
            PanelHeader(icon, accent: link.isOnline ? theme.blue : theme.dim, title: link.title) {
                if model.snapshot.wifiInterface != nil {
                    PanelSwitch("Wi-Fi", isOn: Binding(
                        get: { model.snapshot.wifiOn },
                        set: { model.setWifi($0, orElse: openSettings) }))
                }
            }
            if model.switchFailed { theme.marked(WifiPower.failureLine, theme.red) }
            if let note = link.note {
                Text(note).foregroundStyle(theme.quiet)
            } else {
                throughput
                PanelRule()
                addresses
                PanelRule()
                speedTest
                PanelRule()
                apps
            }
            PanelRule()
            PanelFooter(link.settings.title, action: openSettings)
        }
    }

    private var icon: GroveIcon.Name {
        switch link {
        case .wifi: return .wifi
        case .ethernet: return .ethernet
        case .vpn: return .vpn
        case .offline: return .offline
        }
    }

    private func openSettings() {
        guard let url = URL(string: link.settings.url) else { return }
        panel.open(url)
    }

    // MARK: Rates

    private var throughput: some View {
        let lines = model.history.normalized
        return VStack(alignment: .leading, spacing: GroveSpace.s8) {
            HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s16) {
                rate(.down, model.rates?.down, theme.blue, "Download")
                rate(.up, model.rates?.up, theme.purple, "Upload")
                Spacer(minLength: GroveSpace.s8)
                PanelCaption("last 60 s")
            }
            // Down over up: it is the line read first.
            WifiChart(lines: [(lines.up, theme.purple), (lines.down, theme.blue)])
        }
    }

    /// An arrow in the line's colour and the rate; a dash until there is one.
    private func rate(_ icon: GroveIcon.Name, _ value: Double?, _ accent: RGB, _ label: String) -> some View {
        let text = value.map(WifiRate.format) ?? "–"
        return (GroveIcon.text(icon, size: GroveType.label, weight: .bold).foregroundColor(Color(accent))
            + Text(verbatim: " " + text))
            .font(GroveFont.mono(GroveType.label))
            .lineLimit(1)
            .accessibilityElement()
            .accessibilityLabel("\(label) \(value == nil ? "not measured yet" : text)")
    }

    // MARK: Addresses

    private var addresses: some View {
        PanelRows {
            WifiAddressRow(label: "IP", address: model.snapshot.ip, lit: model.sampleHover == "IP", copy: model.copy)
            WifiAddressRow(label: "Router", address: model.snapshot.router, lit: false, copy: model.copy)
            WifiAddressRow(label: "DNS", address: model.snapshot.dns, lit: false, copy: model.copy)
        }
    }

    // MARK: Speed test

    @ViewBuilder private var speedTest: some View {
        switch speed.state {
        case .idle:
            speedHead { PanelButton("Run speed test", action: model.runSpeedTest) }
        case .running(let since):
            let progress = WifiSpeedTest.progress(elapsed: model.now.timeIntervalSince(since))
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Testing…")
                    Spacer(minLength: GroveSpace.s8)
                    PanelButton("Cancel", action: model.cancelSpeedTest)
                }
                PanelMeter(share: progress, accent: theme.blue)
                    // The clock ticks once a second: the bar moves between.
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                PanelCaption("about 15 s, at the network's full speed")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Speed test running")
        case .result(let result, let at, _):
            VStack(alignment: .leading, spacing: GroveSpace.s4) {
                speedHead {
                    PanelCaption(WifiSpeedTest.age(model.now.timeIntervalSince(at)))
                    PanelButton("Run again", icon: .again, action: model.runSpeedTest)
                }
                self.result(result)
            }
        case .failed(let why):
            VStack(alignment: .leading, spacing: GroveSpace.s4) {
                speedHead { PanelButton("Run again", icon: .again, action: model.runSpeedTest) }
                theme.marked(why, theme.red)
            }
        }
    }

    private func speedHead<Trailing: View>(@ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
            Text("Speed test").foregroundStyle(theme.quiet)
            Spacer(minLength: GroveSpace.s8)
            trailing()
        }
        .lineLimit(1)
    }

    /// "↓ 412 Mbps  ↑ 38 Mbps  12 ms".
    private func result(_ result: WifiSpeedResult) -> some View {
        let gap = Text(verbatim: "  ")
        let delay = result.delayText.map { gap + Text(verbatim: $0).foregroundColor(theme.quiet) } ?? Text(verbatim: "")
        return (GroveIcon.text(.down, size: GroveType.label, weight: .bold).foregroundColor(Color(theme.blue))
            + Text(verbatim: " " + result.downText) + gap
            + GroveIcon.text(.up, size: GroveType.label, weight: .bold).foregroundColor(Color(theme.purple))
            + Text(verbatim: " " + result.upText) + delay)
            .font(GroveFont.mono(GroveType.label))
            .lineLimit(1)
            .accessibilityElement()
            .accessibilityLabel("Download \(result.downText), upload \(result.upText)"
                + (result.delayText.map { ", delay \($0)" } ?? ""))
    }

    // MARK: Apps

    /// Closed until asked for: who is using the network is a second question.
    private var apps: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            PanelRows {
                PanelRow(action: model.toggleApps) {
                    Text(model.appsShown ? "Apps using the network" : "Show apps")
                    Spacer(minLength: GroveSpace.s8)
                    GroveIcon(model.appsShown ? .menu : .forward, size: GroveType.body).foregroundStyle(theme.quiet)
                }
                .accessibilityLabel(model.appsShown ? "Hide apps" : "Show apps")
            }
            if model.appsShown {
                if let apps = model.apps {
                    if apps.isEmpty {
                        Text("No app is using the network").foregroundStyle(theme.quiet)
                    } else {
                        PanelPairs(apps.map { ($0.name, WifiRate.format($0.rate)) })
                    }
                } else {
                    Text("Measuring…").foregroundStyle(theme.quiet)
                }
            }
        }
    }
}

/// IP, Router or DNS: the label quiet, the value at the right, and a click
/// copies it. Under the pointer the row says "copy" before the value, and
/// "copied" for a moment after a click. Without a value: "none", no click.
private struct WifiAddressRow: View {
    let label: String
    let address: WifiAddress?
    /// Drawn as under the pointer (a render).
    let lit: Bool
    let copy: (String) -> Void
    @Environment(\.theme) private var theme
    // The `@State` macro needs a plugin the Command Line Tools don't ship.
    private var hovering = State(initialValue: false)
    private var copied = State(initialValue: 0)

    init(label: String, address: WifiAddress?, lit: Bool, copy: @escaping (String) -> Void) {
        self.label = label
        self.address = address
        self.lit = lit
        self.copy = copy
    }

    var body: some View {
        if let address {
            let said = copied.wrappedValue > 0
            PanelRow(action: { clicked(address) }) {
                Text(label).foregroundStyle(theme.quiet)
                Spacer(minLength: GroveSpace.s8)
                if said || hovering.wrappedValue || lit {
                    (GroveIcon.text(said ? .current : .copy, size: GroveType.finePrint)
                        + Text(verbatim: said ? " copied" : " copy"))
                        .font(GroveFont.mono(GroveType.finePrint)).foregroundStyle(theme.quiet)
                }
                Text(address.shown)
                if let more = address.more { Text(more).foregroundStyle(theme.quiet) }
            }
            .background {
                // A render has no pointer: the row's fill, drawn.
                if lit {
                    RoundedRectangle(cornerRadius: GroveRadius.control).fill(theme.hoverFill(on: .base))
                        .padding(.horizontal, -GroveSpace.s8)
                }
            }
            .onHover { hovering.wrappedValue = $0 }
            .help(address.more == nil ? "Copy the \(label) address" : "Copy all \(label) addresses")
            .accessibilityLabel("\(label) \(address.copied.replacingOccurrences(of: "\n", with: ", ")), copy")
        } else {
            PanelDetail(label) { Text("none").foregroundStyle(theme.quiet) }
                .padding(.vertical, GroveSpace.s4)
        }
    }

    private func clicked(_ address: WifiAddress) {
        copy(address.copied)
        copied.wrappedValue += 1
        let mark = copied.wrappedValue
        // "copied" for a moment; a second click starts the moment again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copied.wrappedValue == mark { copied.wrappedValue = 0 }
        }
    }
}

/// The rates' chart: `Sparkline`'s drawing for lines that may have gaps (a
/// second with no reading yet is absent, not zero). Values 0...1, oldest
/// first, both lines over one 1 pt baseline. Should move to GroveUI as
/// `Sparkline`'s optional-values form.
private struct WifiChart: View {
    let lines: [(values: [Double?], accent: RGB)]
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            for line in lines {
                let points = SparklineGeometry.points(line.values.map { $0 ?? 0 }, in: size)
                for run in WifiHistory.runs(line.values) where run.count > 1 && run.upperBound <= points.count {
                    var path = Path()
                    path.move(to: points[run.lowerBound])
                    for index in run.dropFirst() { path.addLine(to: points[index]) }
                    context.stroke(path, with: .color(Color(line.accent)),
                                   style: StrokeStyle(lineWidth: PanelMetrics.chartLine, lineJoin: .round))
                }
            }
        }
        .frame(height: PanelMetrics.chart)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .accessibilityHidden(true)
    }
}
