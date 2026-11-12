import AppKit
import ApplicationServices
import CoreGraphics
import GroveKeysCore

/// Hides the window borders while Mission Control, App Exposé or Show
/// Desktop is up, and puts them back when it ends (why: `Borders`). macOS
/// doesn't announce an overview, so this looks for it (`Borders
/// .overviewIsUp`): when one of WindowManager's parked icon windows comes on
/// screen (asked twenty times a second; nearly free, see `Borders
/// .probeInterval`), when the Dock or WindowManager post one of a few
/// general Accessibility notifications (they come late, but also for Show
/// Desktop, which has no icons), and ten times a second while one is up.
/// What to do then is `BordersMachine`'s, and this runs it.
///
/// It needs the Accessibility permission Grove Keys has anyway. Until that
/// is granted there are no observers; `ensure()` (called with the
/// permission poll) installs them then, and again when either process
/// restarts.
///
/// The log says once which it is: "borders watcher: watching the Dock and
/// WindowManager for an overview" or "borders watcher: not installed: <why>".
@MainActor
final class BordersWatcher {
    static let shared = BordersWatcher()

    private var machine = BordersMachine()
    /// One observer per process watched, by its pid.
    private var observers: [pid_t: AXObserver] = [:]
    /// The overview was up at the last look.
    private var up = false
    /// A look is already queued (several notifications arrive together).
    private var lookQueued = false
    private var recheck: Timer?
    /// The icon windows asked about, and the timers that ask and re-pick.
    private var probes: [CGWindowID] = []
    private var probeTimer: Timer?
    private var refreshTimer: Timer?
    /// What the log last said, so each state is said once.
    private var logged: String?
    private let runner = Runner()

    /// At launch: the borders show (an earlier run may have left them
    /// hidden), then the observers if they can be had, and a first look.
    func start() {
        perform(machine.handle(.started))
        ensure()
        look()
        pickProbes()
        probeTimer = repeating(Borders.probeInterval) { $0.probe() }
        refreshTimer = repeating(Borders.probeRefresh) { $0.pickProbes() }
    }

    private func repeating(_ interval: TimeInterval, _ action: @escaping @MainActor (BordersWatcher) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action(BordersWatcher.shared) }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Picks the icon windows to ask about, from every window there is. Not
    /// while an overview is up: they are on screen then.
    private func pickProbes() {
        guard !up else { return }
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        probes = Borders.probes(in: list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32 else { return nil }
            let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            return Borders.Window(id: id,
                                  owner: info[kCGWindowOwnerName as String] as? String ?? "",
                                  layer: info[kCGWindowLayer as String] as? Int ?? 0,
                                  onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                                  width: bounds["Width"] as? Double ?? 0, height: bounds["Height"] as? Double ?? 0)
        })
    }

    /// Is one of the icon windows on screen? Then an overview is starting:
    /// look. One that is gone (its app quit) is a reason to pick again.
    private func probe() {
        guard !up, !probes.isEmpty else { return }
        var gone = false
        for id in probes {
            guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first else {
                gone = true
                continue
            }
            if info[kCGWindowIsOnscreen as String] as? Bool == true {
                look()
                return
            }
        }
        if gone { pickProbes() }
    }

    /// Installs the observers that are missing, and drops those of a process
    /// that has gone (the Dock or WindowManager restarted).
    func ensure() {
        guard AXIsProcessTrusted() else {
            log("not installed: Accessibility isn't granted yet")
            return
        }
        let running = Borders.triggerApps.compactMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier
        }
        let gone = observers.keys.filter { !running.contains($0) }
        for pid in gone { remove(pid) }
        if !gone.isEmpty { perform(machine.handle(.dockRestarted)); up = false }
        for pid in running where observers[pid] == nil {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, _ in
                // Delivered on the main run loop, where the source was added.
                MainActor.assumeIsolated { BordersWatcher.shared.queueLook() }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else { continue }
            let element = AXUIElementCreateApplication(pid)
            let taken = Borders.triggerNotifications.filter {
                AXObserverAddNotification(created, element, $0 as CFString, nil) == .success
            }
            guard !taken.isEmpty else { continue }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observers[pid] = created
        }
        if observers.isEmpty {
            log("not installed: neither the Dock nor WindowManager took a notification")
        } else {
            log("watching the Dock and WindowManager for an overview (\(observers.count) of \(Borders.triggerApps.count))")
        }
    }

    /// Every exit path: borders hidden by this run come back, before the app goes.
    func shutdown() {
        if machine.handle(.shuttingDown) == .restore { runner.restoreNow() }
        remove()
    }

    private func remove(_ pid: pid_t? = nil) {
        for (key, observer) in observers where pid == nil || key == pid {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[key] = nil
        }
        if pid == nil {
            for timer in [recheck, probeTimer, refreshTimer] { timer?.invalidate() }
            recheck = nil
            probeTimer = nil
            refreshTimer = nil
        }
    }

    /// A notification came: look once, shortly (they arrive in bursts).
    private func queueLook() {
        guard !lookQueued else { return }
        lookQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
            lookQueued = false
            look()
        }
    }

    /// Is an overview on screen? Tells the machine when that changed, and
    /// keeps looking for the end while one is up.
    private func look() {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.map {
            (owner: $0[kCGWindowOwnerName as String] as? String ?? "", layer: $0[kCGWindowLayer as String] as? Int ?? 0)
        }
        let now = Borders.overviewIsUp(windows: windows)
        guard now != up else { return }
        up = now
        perform(machine.handle(now ? .entered : .exited))
        recheck?.invalidate()
        recheck = nil
        if now {
            let timer = Timer(timeInterval: Borders.recheck, repeats: true) { _ in
                MainActor.assumeIsolated { BordersWatcher.shared.look() }
            }
            RunLoop.main.add(timer, forMode: .common)
            recheck = timer
        } else {
            // The overview may have made or dropped icon windows.
            pickProbes()
        }
    }

    private func perform(_ command: BordersMachine.Command?) {
        if let command { runner.run(command) }
    }

    private func log(_ line: String) {
        guard line != logged else { return }
        logged = line
        NSLog("Grove Keys: borders watcher: %@", line)
    }

    /// Runs `borders` off the main thread, one command at a time, without
    /// the caller waiting. Only the newest command not yet started is run:
    /// a quick swipe in and out ends with the borders as the last event
    /// left them.
    private final class Runner: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.projectgrove.keys.borders")
        private let lock = NSLock()
        private var pending: BordersMachine.Command?

        func run(_ command: BordersMachine.Command) {
            lock.lock()
            pending = command
            lock.unlock()
            queue.async { [self] in
                lock.lock()
                let next = pending
                pending = nil
                lock.unlock()
                if let next { Self.execute(next) }
            }
        }

        /// For the shutdown path: after anything still running, and waited for.
        func restoreNow() {
            lock.lock()
            pending = nil
            lock.unlock()
            queue.sync { Self.execute(.restore) }
        }

        /// Nothing when `borders` isn't installed or isn't running: run
        /// without one, the config would start it, and that is AeroSpace's to do.
        private static func execute(_ command: BordersMachine.Command) {
            let environment = MenuShell.environment(from: ProcessInfo.processInfo.environment,
                                                    home: FileManager.default.homeDirectoryForCurrentUser)
            guard let binary = Borders.binary(environment: environment,
                                              isExecutable: FileManager.default.isExecutableFile(atPath:)),
                  Subprocess.run("/usr/bin/pgrep", ["-x", "borders"], timeout: 2).status == 0 else { return }
            switch command {
            case .hide:
                _ = Subprocess.run(binary, Borders.hideArguments, timeout: 3)
            case .restore:
                let config = Borders.config(home: FileManager.default.homeDirectoryForCurrentUser,
                                            environment: ProcessInfo.processInfo.environment)
                guard FileManager.default.isReadableFile(atPath: config.path) else { return }
                // /bin/sh with a PATH that has Homebrew: the config calls `borders` by name.
                let shell = Process()
                shell.executableURL = URL(fileURLWithPath: "/bin/sh")
                shell.arguments = [config.path]
                shell.environment = environment
                shell.standardInput = FileHandle.nullDevice
                shell.standardOutput = FileHandle.nullDevice
                shell.standardError = FileHandle.nullDevice
                let done = DispatchSemaphore(value: 0)
                shell.terminationHandler = { _ in done.signal() }
                guard (try? shell.run()) != nil else { return }
                if done.wait(timeout: .now() + 3) != .success { shell.terminate() }
            }
        }
    }
}
