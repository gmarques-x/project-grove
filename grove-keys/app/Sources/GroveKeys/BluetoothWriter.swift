import AppKit
import Combine
import GroveKeysCore
import os

/// The one Bluetooth reader in Grove Keys (spec 2026-11-13-bar-wifi-bluetooth):
/// `system_profiler SPBluetoothDataType -json` every 30 s while the app
/// runs, after a wake, and whenever `refresh()` is called (the Wi-Fi
/// dropdown, as it opens). `state` is the latest reading, for the dropdown's
/// Bluetooth section; `$GROVE_STATE/bluetooth` is the bar's icon (`off`,
/// `on`, `connected`), rewritten only when the icon changes, and then the
/// bar is sent `bluetooth_change`.
///
/// `system_profiler` takes about a second, so it runs on a queue of its own,
/// one reading at a time, and never on the main thread. A reading that fails
/// (the tool stops with an error or hangs) keeps the last one.
@MainActor
final class BluetoothWriter: ObservableObject {
    static let shared = BluetoothWriter()
    static let interval: TimeInterval = 30
    private nonisolated static let log = Logger(subsystem: "com.projectgrove.keys", category: "bluetooth")
    private nonisolated static let profiler = "/usr/sbin/system_profiler"
    private nonisolated static let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// The latest reading; nil until the first one is in.
    @Published private(set) var state: BluetoothState?

    private enum Mode { case idle, running, stopped }

    private nonisolated let url: URL
    private let queue = DispatchQueue(label: "com.projectgrove.keys.bluetooth", qos: .utility)
    private var timer: Timer?
    private var wake: NSObjectProtocol?
    /// A reading is on the queue; a `refresh()` meanwhile asks for one more.
    private var reading = false
    private var again = false
    /// Shared with the queue: the file is written only between `start` and
    /// `stop`, so a reading still on the queue can't put it back after
    /// `stop` removed it (and a render run, never started, writes nothing).
    private nonisolated let mode = OSAllocatedUnfairLock(initialState: Mode.idle)

    private init() {
        url = BluetoothBarFile.url(environment: ProcessInfo.processInfo.environment,
                                   home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Call once: reads now, then every 30 s and after each wake.
    func start() {
        guard timer == nil else { return }
        mode.withLock { $0 = .running }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { BluetoothWriter.shared.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BluetoothWriter.shared.refresh() }
        }
        refresh()
    }

    /// A fresh reading, off the main thread; `state` changes when it's in.
    /// Calls while one is under way are folded into one more after it.
    func refresh() {
        guard !reading else {
            again = true
            return
        }
        reading = true
        queue.async { [self] in
            let fresh = Self.read()
            if let fresh { write(BluetoothIcon.icon(for: fresh)) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(fresh) } }
        }
    }

    /// Every exit path: the file goes, so the bar never shows a stale icon
    /// (no file is `off`), and the bar is told.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        wake = nil
        let removed = mode.withLock { mode -> Bool in
            mode = .stopped
            return (try? BluetoothBarFile.update(nil, at: url)) ?? false
        }
        if removed { Self.trigger(timeout: 0.5) }
    }

    private func finish(_ fresh: BluetoothState?) {
        reading = false
        if let fresh, fresh != state { state = fresh }
        if again {
            again = false
            refresh()
        }
    }

    /// On the queue: the icon's file, and the bar told when it changed.
    private nonisolated func write(_ icon: BluetoothIcon) {
        let changed = mode.withLock { mode -> Bool in
            guard mode == .running else { return false }
            do {
                return try BluetoothBarFile.update(icon, at: url)
            } catch {
                Self.log.error("cannot write \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        if changed { Self.trigger(timeout: 2) }
    }

    /// Not on the main thread (it waits for the tool). Standard error is
    /// left out: a warning there would spoil the JSON.
    private nonisolated static func read() -> BluetoothState? {
        let run = Subprocess.run(profiler, ["SPBluetoothDataType", "-json"], timeout: 20, includeErrors: false)
        guard run.status == 0, !run.timedOut else {
            log.error("system_profiler SPBluetoothDataType: status \(run.status), timed out \(run.timedOut)")
            return nil
        }
        return BluetoothState.parse(systemProfilerJSON: Data(run.output.utf8))
    }

    /// `sketchybar --trigger bluetooth_change`: the bar's `bt` item reads the
    /// file again. Nothing when SketchyBar isn't installed.
    private nonisolated static func trigger(timeout: TimeInterval) {
        guard let sketchybar else { return }
        let run = Subprocess.run(sketchybar, ["--trigger", "bluetooth_change"], timeout: timeout)
        if run.status != 0 {
            log.error("sketchybar --trigger bluetooth_change: status \(run.status), timed out \(run.timedOut)")
        }
    }
}
