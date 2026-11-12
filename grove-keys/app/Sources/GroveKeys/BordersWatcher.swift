import AppKit
import ApplicationServices
import GroveKeysCore

/// Hides the window borders while Mission Control, App Exposé or Show
/// Desktop is up, and puts them back when it ends (why: `Borders`). The
/// Dock says when, in Accessibility notifications on its application
/// element; what to do then is `BordersMachine`'s, and this runs it.
///
/// It needs the Accessibility permission Grove Keys has anyway. Until that
/// is granted there is no observer; `ensure()` (called with the permission
/// poll) installs it then, and again when the Dock restarts. If macOS never
/// posts the notifications, nothing here does anything.
///
/// The log says once which it is: "borders watcher: watching the Dock (pid
/// N) for Mission Control" or "borders watcher: not installed: <why>".
@MainActor
final class BordersWatcher {
    static let shared = BordersWatcher()

    private var machine = BordersMachine()
    private var observer: AXObserver?
    private var dockPID: pid_t?
    /// What the log last said, so each state is said once.
    private var logged: String?
    private let runner = Runner()

    /// At launch: the borders show (an earlier run may have left them
    /// hidden), then the observer if it can be had.
    func start() {
        perform(machine.handle(.started))
        ensure()
    }

    /// Installs the observer if there is none, or if the Dock is a new process.
    func ensure() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            log("not installed: the Dock isn't running")
            return
        }
        let pid = dock.processIdentifier
        if observer != nil, pid == dockPID { return }
        if observer != nil {
            remove()
            perform(machine.handle(.dockRestarted))
        }
        guard AXIsProcessTrusted() else {
            log("not installed: Accessibility isn't granted yet")
            return
        }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, _ in
            let name = notification as String
            // Delivered on the main run loop, where the source was added.
            MainActor.assumeIsolated { BordersWatcher.shared.received(name) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            log("not installed: no observer for the Dock (pid \(pid))")
            return
        }
        let element = AXUIElementCreateApplication(pid)
        let names = Borders.enterNotifications + [Borders.exitNotification]
        let refused = names.filter { AXObserverAddNotification(created, element, $0 as CFString, nil) != .success }
        guard refused.count < names.count else {
            log("not installed: the Dock (pid \(pid)) took none of the notifications")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        dockPID = pid
        log("watching the Dock (pid \(pid)) for Mission Control"
            + (refused.isEmpty ? "" : "; refused: " + refused.joined(separator: ", ")))
    }

    /// Every exit path: borders hidden by this run come back, before the app goes.
    func shutdown() {
        if machine.handle(.shuttingDown) == .restore { runner.restoreNow() }
        remove()
    }

    private func remove() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        dockPID = nil
    }

    private func received(_ notification: String) {
        if notification == Borders.exitNotification {
            perform(machine.handle(.exited))
        } else if Borders.enterNotifications.contains(notification) {
            perform(machine.handle(.entered))
            // The last resort, counted from this enter.
            let enter = machine.enters
            DispatchQueue.main.asyncAfter(deadline: .now() + Borders.lastResort) { [self] in
                perform(machine.handle(.timedOut(enter: enter)))
            }
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
