import AppKit
import GroveKeysCore
import IOKit.pwr_mgt

// Keep Awake and Ignore Lid, on the real Mac (spec
// 2026-11-12-bar-panels-design §6). The rules are `KeepAwakeController`'s
// (GroveKeysCore, tested with a fake); this file is the Mac's side and the
// one object of the bar's panels that lives while its panel is closed:
// keeping the Mac awake is the feature.

/// The Mac's side of Keep Awake: two IOKit power assertions, the state file
/// for the bar, `pmset -g`, and the change through macOS's own
/// authorization dialog.
final class LiveKeepAwakeSystem: KeepAwakeSystem, @unchecked Sendable {
    /// The assertions held; only touched on the main thread (the controller's).
    private var assertions: [IOPMAssertionID] = []
    private let file: URL

    init(file: URL = KeepAwake.fileURL) {
        self.file = file
    }

    /// The Mac and its display don't sleep from idleness. No admin rights;
    /// the assertions die with the process whatever happens.
    func hold() -> Bool {
        guard assertions.isEmpty else { return true }
        for type in ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"] {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Grove: Keep Awake" as CFString, &id)
            guard result == kIOReturnSuccess else {
                release()
                return false
            }
            assertions.append(id)
        }
        return true
    }

    func release() {
        for id in assertions { IOPMAssertionRelease(id) }
        assertions = []
    }

    func writeState(_ contents: String?) {
        guard let contents else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((contents + "\n").utf8).write(to: file, options: .atomic)
    }

    /// `pmset -g`, read-only: some 10 ms, off the main thread.
    func sleepDisabled() async -> Bool? {
        await Self.offMain {
            let result = Subprocess.run("/usr/bin/pmset", ["-g"], timeout: 3)
            guard result.status == 0 else { return nil }
            return IgnoreLid.sleepDisabled(pmset: result.output)
        }
    }

    /// osascript shows macOS's password / Touch ID dialog and runs pmset as
    /// root once it is answered. Waits for the answer, five minutes at most
    /// (an abandoned dialog is a dismissed one).
    func setSleepDisabled(_ on: Bool) async -> IgnoreLid.Outcome {
        await Self.offMain {
            let result = Subprocess.run(IgnoreLid.osascript, IgnoreLid.arguments(on: on), timeout: 300)
            return IgnoreLid.outcome(status: result.status, output: result.output, timedOut: result.timedOut)
        }
    }

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }
}

/// Keep Awake, app-wide: the battery panel's two switches act on it, and it
/// carries on with the panel closed (the duration's end, the authorization
/// dialog that closed the panel by taking the focus).
///
/// Off, it holds nothing: no timer, no observer, no assertion. On, it holds
/// the two assertions, and with a duration one timer for its end.
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake(system: LiveKeepAwakeSystem())

    @Published private(set) var state = KeepAwakeState()

    private let controller: KeepAwakeController
    private var end: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private init(system: any KeepAwakeSystem) {
        controller = KeepAwakeController(system: system)
        controller.onChange = { [weak self] state in
            self?.state = state
            self?.follow(state)
        }
    }

    /// `$GROVE_STATE/keep-awake` (default `~/.local/state/grove/keep-awake`).
    nonisolated static var fileURL: URL {
        KeepAwakeFile.url(environment: ProcessInfo.processInfo.environment,
                          home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// At launch nothing is kept awake yet: a file left by a run that was
    /// killed would have the bar say otherwise. Call once, early in the
    /// app's start (not in a `--render-panel` run).
    nonisolated static func resetAtLaunch() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func setOn(_ on: Bool) {
        if on { controller.turnOn(now: Date()) } else { Task { await controller.turnOff() } }
    }

    func choose(_ duration: KeepAwakeDuration) {
        controller.choose(duration, now: Date())
    }

    /// `refused`: the battery's rule (`BatteryReading.refusesIgnoreLid`).
    func setIgnoreLid(_ on: Bool, refused: Bool) {
        Task { await controller.setIgnoreLid(on, refused: refused) }
    }

    /// The real `SleepDisabled`, at each opening of the panel.
    func refresh() {
        Task { await controller.refreshLid() }
    }

    /// While on: the timer for the duration's end, a look at the clock after
    /// a sleep (a timer doesn't count the time asleep), and the assertions
    /// given back as the app quits. Off: none of them.
    private func follow(_ state: KeepAwakeState) {
        end?.invalidate()
        end = nil
        guard state.isOn else {
            for observer in observers { observer.center.removeObserver(observer.token) }
            observers = []
            return
        }
        if let endsAt = state.endsAt {
            let timer = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.expire() }
            }
            RunLoop.main.add(timer, forMode: .common)
            end = timer
        }
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }))
        // No dialog can be waited for while quitting: Ignore Lid, if on,
        // stays on and the next opening says so.
        observers.append((.default, NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.releaseNow() }
        }))
    }

    private func expire() {
        Task { await controller.expire(now: Date()) }
    }
}
