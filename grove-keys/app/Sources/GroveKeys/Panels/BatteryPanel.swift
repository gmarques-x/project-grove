import AppKit
import Combine
import GroveKeysCore
import GroveThemesCore
import GroveUI
import IOKit.ps
import SwiftUI

// Battery (spec 2026-11-12-bar-panels-design §6): the charge, its bar and
// one sentence; power, health, temperature; Keep Awake and Ignore Lid; Low
// Power Mode. The words and rules are `BatteryReading`'s and
// `KeepAwakeController`'s (GroveKeysCore); IOKit is `BatterySampler`'s; Keep
// Awake itself is `KeepAwake.shared`, which outlives the panel.

/// The Battery panel's state. `start()` at each opening, `stop()` at each
/// closing; `.sample` is fixed data for `--render-panel`.
@MainActor
final class BatteryModel: ObservableObject, BarPanelModel {
    @Published private(set) var reading: BatteryReading
    @Published private(set) var awake: KeepAwakeState
    @Published private(set) var lowPower: Bool
    /// The clock the time left is counted against.
    @Published private(set) var now: Date

    private let live: Bool
    private var open = false
    /// System Settings' health figure and when it was read.
    private var settingsHealth: (percent: Int?, at: Date)?
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var awakeSink: AnyCancellable?
    private let queue = DispatchQueue(label: "grove.battery-panel", qos: .utility)

    /// The Mac's draw changes by the second; the rest arrives by notification.
    private static let wattsEvery: TimeInterval = 5
    private static let healthEvery: TimeInterval = 6 * 3600

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            live = true
            reading = BatteryReading()
            awake = KeepAwakeState()
            lowPower = false
            now = Date()
        case .sample:
            live = false
            let sample = Self.sample(ProcessInfo.processInfo.environment["GROVE_BATTERY_SAMPLE"] ?? "charging")
            reading = sample.reading
            awake = sample.awake
            lowPower = sample.lowPower
            now = Self.sampleNow
        }
    }

    func start() {
        guard live else { return }
        open = true
        now = Date()
        // The first reading before the panel is drawn (a millisecond or two
        // of IOKit), so it never opens empty; every later one off the main
        // thread.
        apply(BatterySampler.read())
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        awake = KeepAwake.shared.state
        awakeSink = KeepAwake.shared.$state.sink { [weak self] state in self?.awake = state }
        // The truth about Ignore Lid, from `pmset -g`, at every opening.
        KeepAwake.shared.refresh()

        // macOS says when the charge, the state or the adapter changes.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<BatteryModel>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { model.sample() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        let timer = Timer(timeInterval: Self.wattsEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.sample()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if settingsHealth.map({ now.timeIntervalSince($0.at) > Self.healthEvery }) ?? true {
            queue.async { [self] in
                let percent = BatterySampler.settingsHealth()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.settingsHealth = (percent, Date())
                        if let percent, self.reading.present { self.reading.health = percent }
                    }
                }
            }
        }
    }

    func stop() {
        open = false
        timer?.invalidate()
        timer = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
        }
        powerSource = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
        awakeSink = nil
    }

    /// K switches Keep Awake. Ignore Lid has no key: it asks for a password.
    func key(_ key: BarPanelKey) -> Bool {
        guard key == .character("k") else { return false }
        setKeepAwake(!awake.isOn)
        return true
    }

    // MARK: The switches

    func setKeepAwake(_ on: Bool) {
        guard live else {
            awake.isOn = on
            return
        }
        KeepAwake.shared.setOn(on)
    }

    func choose(_ duration: KeepAwakeDuration) {
        guard live else {
            awake.duration = duration
            return
        }
        now = Date()
        KeepAwake.shared.choose(duration)
    }

    func setIgnoreLid(_ on: Bool) {
        guard live else {
            awake.lidIgnored = on
            return
        }
        KeepAwake.shared.setIgnoreLid(on, refused: reading.refusesIgnoreLid)
    }

    // MARK: Reading

    /// One reading off the main thread, published on it; dropped if the
    /// panel closed meanwhile.
    private func sample() {
        queue.async { [self] in
            let reading = BatterySampler.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.open else { return }
                    self.apply(reading)
                }
            }
        }
    }

    /// System Settings' health figure, once known, over the registry's
    /// measured one.
    private func apply(_ fresh: BatteryReading) {
        var fresh = fresh
        if fresh.present, let percent = settingsHealth?.percent { fresh.health = percent }
        if fresh != reading { reading = fresh }
    }

    // MARK: Sample

    private static let sampleNow = Date(timeIntervalSince1970: 1_794_450_000)

    /// The mock-ups' numbers. `GROVE_BATTERY_SAMPLE` picks the state:
    /// `charging` (the default), `battery`, `low`, `full`, `held`, `awake`
    /// (Keep Awake on, 1:42 left), `lid` (Ignore Lid on), `asking` (the
    /// authorization dialog is up), `stuck` (Ignore Lid left on), `refused`
    /// (Keep Awake on, under 20% on battery), `none` (no battery).
    private static func sample(_ name: String) -> (reading: BatteryReading, awake: KeepAwakeState, lowPower: Bool) {
        var reading = BatteryReading()
        reading.percent = 78
        reading.onAdapter = true
        reading.charging = true
        reading.minutesToFull = 13
        reading.adapterWatts = 94
        reading.macWatts = 17.7
        reading.health = 100
        reading.cycles = 96
        reading.celsius = 31
        var awake = KeepAwakeState()
        var lowPower = false

        func onBattery(_ percent: Int, minutes: Int, watts: Double) {
            reading.percent = percent
            reading.onAdapter = false
            reading.charging = false
            reading.minutesToFull = nil
            reading.minutesToEmpty = minutes
            reading.adapterWatts = nil
            reading.macWatts = watts
        }
        func keepAwake(_ duration: KeepAwakeDuration, minutesLeft: Double?) {
            awake.isOn = true
            awake.duration = duration
            awake.endsAt = minutesLeft.map { sampleNow.addingTimeInterval($0 * 60) }
        }

        switch name {
        case "battery":
            onBattery(64, minutes: 260, watts: 9.2)
        case "low":
            onBattery(12, minutes: 41, watts: 9.8)
            lowPower = true
        case "full":
            reading.percent = 100
            reading.charging = false
            reading.charged = true
            reading.minutesToFull = nil
            reading.macWatts = 12.1
        case "held":
            reading.percent = 80
            reading.charging = false
            reading.minutesToFull = nil
            reading.adapterWatts = 30
            reading.macWatts = 31.2
        case "awake":
            keepAwake(.twoHours, minutesLeft: 102)
        case "lid":
            keepAwake(.untilOff, minutesLeft: nil)
            awake.lidIgnored = true
        case "asking":
            keepAwake(.untilOff, minutesLeft: nil)
            awake.lidBusy = true
        case "stuck":
            awake.lidIgnored = true
        case "refused":
            onBattery(12, minutes: 41, watts: 9.8)
            keepAwake(.untilOff, minutesLeft: nil)
        case "none":
            reading = .none
        default:
            break
        }
        return (reading, awake, lowPower)
    }
}

struct BatteryPanel: View {
    static let width: CGFloat = 300
    static let registration = BarPanelRegistration("battery", pill: "pill.battery", width: width,
                                                   model: BatteryModel.init) { BatteryPanel(model: $0) }
    static let settings = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!

    @ObservedObject var model: BatteryModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        let reading = model.reading
        BarPanel(width: Self.width) {
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                PanelHeader(.battery, accent: accent, title: "Battery") {
                    if reading.present { PanelValue("\(reading.percent)%", accent: reading.isLow ? theme.red : nil) }
                }
                if reading.present { PanelMeter(share: reading.share, accent: accent) }
                if reading.isLow {
                    PanelStatus(reading.sentence, accent: theme.red)
                } else {
                    Text(reading.sentence).foregroundStyle(reading.present ? Color(theme.fg) : theme.quiet)
                }
            }
            if reading.power != nil || reading.healthText != nil || reading.temperature != nil {
                PanelRule()
                VStack(alignment: .leading, spacing: GroveSpace.s4) {
                    if let power = reading.power { PanelDetail("Power", power) }
                    if let health = reading.healthText { PanelDetail("Health", health) }
                    if let temperature = reading.temperature { PanelDetail("Temperature", temperature) }
                }
            }
            PanelRule()
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                keepAwake
                ignoreLid
                PanelRows {
                    PanelRow(action: openSettings) {
                        Text("Low Power Mode").font(GroveFont.mono(GroveType.label))
                        Spacer(minLength: GroveSpace.s8)
                        Text(model.lowPower ? "On" : "Off")
                            .foregroundStyle(model.lowPower ? Color(theme.fg) : theme.quiet)
                    }
                    .help("Changed in Battery Settings: macOS lets no app switch it without admin rights")
                }
            }
            PanelRule()
            PanelFooter("Battery Settings…", action: openSettings)
        }
    }

    /// The bar's own colours: the bolt's yellow, red when low and not charging.
    private var accent: RGB { model.reading.isLow ? theme.red : theme.yellow }

    private func openSettings() { panel.open(Self.settings) }

    /// Keep Awake: the duration (the time left while it counts down) and the switch.
    private var keepAwake: some View {
        let awake = model.awake
        let shown = awake.timeLeft(now: model.now) ?? awake.duration.title
        return HStack(alignment: .center, spacing: GroveSpace.s8) {
            Text("Keep Awake").font(GroveFont.mono(GroveType.label)).fixedSize()
            // The row is full with the longest choice: the stack's own gaps are the minimum.
            Spacer(minLength: 0)
            GroveSelect("Keep Awake duration",
                        options: KeepAwakeDuration.allCases.map { GroveSelectOption($0, $0.title) },
                        selection: awake.duration,
                        valueText: shown == awake.duration.title ? nil : "\(awake.duration.title), \(shown)",
                        onSelect: model.choose) {
                GroveSelectPill(shown)
            }
            .fixedSize()
            PanelSwitch("Keep Awake", isOn: Binding(get: { awake.isOn }, set: model.setKeepAwake))
        }
        .lineLimit(1)
        .help("Keeps the Mac and its display from sleeping (K)")
    }

    /// Ignore Lid: a switch while Keep Awake is on; left on without it, a
    /// warning with one click to turn it off.
    @ViewBuilder private var ignoreLid: some View {
        let awake = model.awake
        if awake.lidStuck {
            PanelRows {
                PanelRow(action: { model.setIgnoreLid(false) }) {
                    theme.marked("Ignore Lid is still on", theme.yellow, size: GroveType.label)
                        .font(GroveFont.mono(GroveType.label))
                    Spacer(minLength: GroveSpace.s8)
                    Text("Turn off").foregroundStyle(theme.quiet)
                }
                .accessibilityLabel("Ignore Lid is still on. Turn off")
                .help("The Mac won't sleep with its lid closed. Turning it off asks for your password")
            }
        } else {
            // Off is always allowed; on only with Keep Awake and enough battery.
            let refused = awake.isOn && !awake.lidIgnored && model.reading.refusesIgnoreLid
            let offered = !awake.lidBusy && (awake.lidIgnored || (awake.isOn && !refused))
            HStack(alignment: .center, spacing: GroveSpace.s8) {
                Text("Ignore Lid").font(GroveFont.mono(GroveType.label))
                    .foregroundStyle(offered || awake.lidBusy ? Color(theme.fg) : theme.quiet)
                    .fixedSize()
                Spacer(minLength: 0)
                if awake.lidBusy { PanelCaption("waiting for macOS…") }
                PanelSwitch("Ignore Lid", isOn: Binding(get: { awake.lidIgnored }, set: model.setIgnoreLid))
                    .disabled(!offered)
            }
            .lineLimit(1)
            .help(awake.isOn ? "Keeps the Mac running with its lid closed; asks for your password"
                : "Needs Keep Awake on")
            if let note = refused ? KeepAwakeController.refusedOnBattery : awake.note {
                Text(note).font(GroveFont.mono(GroveType.finePrint)).foregroundStyle(theme.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
