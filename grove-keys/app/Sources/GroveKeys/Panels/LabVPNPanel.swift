import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import os
import SwiftUI

// The grove-lab VPN (spec 2026-11-13-bar-vpn-design): the tunnel to the lab,
// a macOS VPN configuration the WireGuard app made, named `grove-lab`. A
// header with the on/off switch (`scutil --nc start|stop`), one status
// line, and "WireGuard…"; when there is no such configuration, how to make
// it and a button opening WireGuard. What scutil's output means is
// GroveKeysCore's (`LabVPNStatus`).

/// The VPN panel's state. Open, it reads `scutil --nc status` at once and
/// every 2 s, off the main thread; closed, it runs nothing. `.sample` is
/// fixed data for `--render-panel` (GROVE_VPN_SAMPLE) and never runs scutil.
@MainActor
final class LabVPNModel: ObservableObject, BarPanelModel {
    /// The last reading; nil until the first one is in.
    @Published private(set) var status: LabVPNStatus?
    /// The switch while scutil starts or stops the tunnel.
    @Published private(set) var pending: LabVPNPendingSwitch?
    /// A start or stop that didn't happen ("Didn't start · see WireGuard"),
    /// in the status line's place until the next switch or opening.
    @Published private(set) var failure: LabVPNFailure?
    /// The zone "since 14:05" is told in.
    let timeZone: TimeZone

    nonisolated static let service = "grove-lab"
    static let wireGuard = "com.wireguard.macos"
    static let appStore = URL(string: "macappstore://apps.apple.com/app/id1451685025")!
    static let every: TimeInterval = 2

    private nonisolated static let log = Logger(subsystem: "com.projectgrove.keys", category: "vpn")
    private nonisolated static let scutil = "/usr/sbin/scutil"
    private nonisolated static let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private let live: Bool
    private var open = false
    private var timer: Timer?
    /// A reading is on the queue; a `refresh()` meanwhile asks for one more.
    private var reading = false
    private var again = false
    /// The number of the last reading started (0: none yet).
    private var started = 0
    /// A start or stop is on the queue.
    private var commanding = false
    /// One queue for readings and commands: a reading asked for after a
    /// start or stop runs after it.
    private let queue = DispatchQueue(label: "com.projectgrove.keys.vpn", qos: .userInitiated)

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            live = true
            timeZone = .current
        case .sample:
            live = false
            timeZone = TimeZone(identifier: "UTC")!
            let name = ProcessInfo.processInfo.environment["GROVE_VPN_SAMPLE"] ?? "connected"
            status = Self.sample(name)
            if name == "refused" { failure = LabVPNFailure(on: true) }
        }
    }

    /// What the panel shows: the pending switch's state over the reading.
    var shown: LabVPNStatus? { pending?.shown ?? status }

    func start() {
        guard live else { return }
        open = true
        // A switch left pending at the last closing: the reading tells now.
        // Not while its command still runs: its end sets the reading to wait for.
        if !commanding { pending = nil }
        failure = nil
        refresh()
        let timer = Timer(timeInterval: Self.every, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        open = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: Reading

    /// A fresh reading off the main thread; calls while one is under way are
    /// folded into one more after it.
    private func refresh() {
        guard live, open else { return }
        guard !reading else {
            again = true
            return
        }
        reading = true
        started += 1
        let number = started
        queue.async { [self] in
            let text = Self.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(text, number: number) }
            }
        }
    }

    private func finish(_ text: String?, number: Int) {
        reading = false
        // A reading that timed out still counts toward the pending switch's cap.
        if open { took(text.map { LabVPNStatus.parse(scutilStatus: $0) }, number: number) }
        if again {
            again = false
            if open { refresh() }
        }
    }

    /// A reading (nil: it timed out): shown, unless the switch is still
    /// waiting (`LabVPNPendingSwitch.settle`). A failure line goes once the
    /// tunnel got where it was asked after all. When the icon changed, the
    /// bar is told (a tunnel that came up while the panel was open turns the
    /// pill purple at once, not at the bar's next 10 s reading).
    private func took(_ fresh: LabVPNStatus?, number: Int) {
        if var pending {
            let outcome = pending.settle(with: fresh, reading: number)
            self.pending = pending
            guard let outcome else { return }
            self.pending = nil
            if outcome == .failed { failure = LabVPNFailure(on: pending.on) }
        }
        guard let fresh else { return }
        if let failure, failure.cleared(by: fresh) { self.failure = nil }
        let before = status
        if fresh != status { status = fresh }
        if let before, LabVPNIcon.icon(for: before) != LabVPNIcon.icon(for: fresh) {
            queue.async { Self.triggerBar() }
        }
    }

    /// `scutil --nc status "grove-lab"`; nil when it hangs. Not on the main
    /// thread.
    private nonisolated static func read() -> String? {
        let run = Subprocess.run(scutil, ["--nc", "status", service], timeout: 2, includeErrors: false)
        guard !run.timedOut else {
            log.error("scutil --nc status \(service, privacy: .public): timed out")
            return nil
        }
        return run.output
    }

    // MARK: The switch

    /// Starts or stops the tunnel: `scutil --nc start|stop "grove-lab"` off
    /// the main thread, the bar told (`vpn_change`), then a fresh reading.
    /// Only live, and only while the tunnel is up or down (not on the way).
    func setOn(_ on: Bool) {
        guard live, pending == nil, let status, status.switchEnabled, on != status.switchOn else { return }
        pending = LabVPNPendingSwitch(on: on, from: status)
        failure = nil
        commanding = true
        queue.async { [weak self] in
            let verb = on ? "start" : "stop"
            let run = Subprocess.run(Self.scutil, ["--nc", verb, Self.service], timeout: 10)
            if run.status != 0 || run.timedOut {
                let service = Self.service, output = run.output
                Self.log.error("""
                    scutil --nc \(verb, privacy: .public) \(service, privacy: .public): status \(run.status), \
                    timed out \(run.timedOut), \(output, privacy: .public)
                    """)
            }
            let failed = run.status != 0 || run.timedOut
            Self.triggerBar()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.commanding = false
                    if failed {
                        // scutil said no: the reading shows where it is.
                        self.pending = nil
                        self.failure = LabVPNFailure(on: on)
                    } else {
                        // Readings started from now on saw the command's effect.
                        self.pending?.changed(afterReading: self.started)
                    }
                    self.refresh()
                }
            }
        }
    }

    /// `sketchybar --trigger vpn_change`: the bar's `vpn.lab` reads scutil
    /// again. Nothing when SketchyBar isn't installed. Not on the main thread.
    private nonisolated static func triggerBar() {
        guard let sketchybar else { return }
        let run = Subprocess.run(sketchybar, ["--trigger", "vpn_change"], timeout: 2)
        if run.status != 0 {
            log.error("sketchybar --trigger vpn_change: status \(run.status), timed out \(run.timedOut)")
        }
    }

    // MARK: The sample

    /// GROVE_VPN_SAMPLE picks the state: `connected` (the default: 10.0.0.2,
    /// since 14:05 UTC), `connecting`, `disconnecting`, `disconnected`,
    /// `notsetup` (no grove-lab service), `refused` (disconnected, a start
    /// that didn't happen). The address is the docs' stand-in,
    /// never the lab's (the repo is public).
    private static func sample(_ name: String) -> LabVPNStatus {
        switch name {
        case "connecting": return .connecting
        case "disconnecting": return .disconnecting
        case "disconnected", "refused": return .disconnected
        case "notsetup": return .notSetUp
        default: return .connected(address: "10.0.0.2", since: Date(timeIntervalSince1970: 1_794_578_700))
        }
    }
}

struct LabVPNPanel: View {
    static let width: CGFloat = 300
    static let registration = BarPanelRegistration("vpn", pill: "pill.vpn", width: width,
                                                   model: LabVPNModel.init) { LabVPNPanel(model: $0) }

    @ObservedObject var model: LabVPNModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        let status = model.shown
        BarPanel(width: Self.width) {
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                PanelHeader(.vpn, accent: accent(status), title: "grove-lab VPN") {
                    if let status, status.showsSwitch {
                        PanelSwitch("grove-lab VPN", isOn: Binding(get: { status.switchOn }, set: model.setOn))
                            .disabled(!status.switchEnabled)
                            .help(status.switchOn ? "Stops the tunnel to the lab" : "Starts the tunnel to the lab")
                    }
                }
                if let failure = model.failure {
                    // A warning in yellow, as the Bluetooth section's refusal.
                    theme.marked(failure.line, theme.yellow)
                } else {
                    Text(status.map { LabVPNStatus.line(for: $0, timeZone: model.timeZone) } ?? "Reading…")
                        .foregroundStyle(theme.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if status == .notSetUp {
                    PanelButton("Open WireGuard", action: openWireGuard)
                        .help("Opens WireGuard, or its App Store page when it isn't installed")
                }
            }
            // Not set up, the button above opens the same app.
            if status != .notSetUp {
                PanelRule()
                PanelFooter("WireGuard…", action: openWireGuard)
            }
        }
    }

    /// The bar's colours: purple connected, yellow on the way, dim off.
    private func accent(_ status: LabVPNStatus?) -> RGB {
        switch status.map(LabVPNIcon.icon(for:)) {
        case .on?: return theme.purple
        case .connecting?: return theme.yellow
        case .off?, nil: return theme.dim
        }
    }

    /// WireGuard, or its App Store page when it isn't installed; the panel
    /// is put away (nothing happens in a render).
    private func openWireGuard() {
        panel.leave {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LabVPNModel.wireGuard) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(),
                                                   completionHandler: nil)
            } else {
                NSWorkspace.shared.open(LabVPNModel.appStore)
            }
        }
    }
}
