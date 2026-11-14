import AppKit
import ApplicationServices
import Combine
import GroveKeysCore
import os

/// The menu-bar tray's one reader (spec 2026-11-14-bar-tray-design): lists
/// the other apps' status items (`StatusItemLocator.allItems`), publishes
/// them with the hidden set for the tray's dropdown, and keeps the bar's
/// count in `$GROVE_STATE/tray` (`TrayBarFile`: the items shown, the hidden
/// ones not counted), rewritten only when it changes, and then the bar is
/// sent `tray_change`. The file goes when Grove Keys stops; without the
/// Accessibility permission there is no file (the bar shows the symbol
/// without a count).
///
/// When it lists, never on a timer: as it starts; an app launching or
/// quitting (NSWorkspace), after the settle (`TraySettle`, Core: 2 s, a
/// burst is one listing); MenuBarAgent saying its bar changed (an
/// Accessibility observer on its app element, if it sends any of the
/// notifications; re-made when its pid changes, removed on stop); and
/// `refresh()`, the dropdown opening.
///
/// Every listing runs on one serial utility queue, one at a time; calls
/// meanwhile fold into one more after it. Only listing runs there: a press
/// (`TrayPresser`, which can wait seconds) must run elsewhere, and the
/// `sketchybar` trigger has a queue of its own.
@MainActor
final class TrayWatcher: ObservableObject {
    static let shared = TrayWatcher()
    private nonisolated static let log = Logger(subsystem: "com.projectgrove.keys", category: "tray")
    private nonisolated static let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    /// What MenuBarAgent is asked to announce (the spec's created,
    /// destroyed, children changed); it may send none of them (then the
    /// count waits for the next launch, quit or opening).
    private nonisolated static let notifications = [
        kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXWindowCreatedNotification,
        "AXChildrenChanged",
    ]

    /// One listing: the items the tray shows (`TrayItems.shown`, left to
    /// right) with their elements to press, the hidden keys
    /// (`TrayHiddenFile`), and whether Grove Keys has Accessibility (without
    /// it `items` is empty). The elements are only messaged off the main
    /// thread, by the presser.
    struct Listing: @unchecked Sendable {
        let items: [(TrayItem, StatusItemLocator.Item)]
        let hidden: Set<String>
        let accessible: Bool

        /// The count on the bar: the items not hidden.
        var count: Int { TrayItems.count(visible: TrayItems.split(items.map(\.0), hidden: hidden).visible) }
    }

    /// The latest listing; nil until the first is in.
    @Published private(set) var latest: Listing?

    private enum Mode { case idle, running, stopped }

    private nonisolated let barURL: URL
    nonisolated let hiddenURL: URL
    private let queue = DispatchQueue(label: "com.projectgrove.keys.tray", qos: .utility)
    private nonisolated let triggerQueue = DispatchQueue(label: "com.projectgrove.keys.tray.trigger", qos: .utility)
    /// Shared with the queue: the bar file is written only between `start`
    /// and `stop` (a listing still on the queue can't put it back after
    /// `stop` removed it; a render, never started, writes nothing).
    private nonisolated let mode = OSAllocatedUnfairLock(initialState: Mode.idle)
    /// MenuBarAgent's pid the observer was made for; the queue's.
    private nonisolated let observedPID = OSAllocatedUnfairLock<pid_t?>(initialState: nil)

    private var settle = TraySettle()
    private var settleTimer: Timer?
    private var workspace: [NSObjectProtocol] = []
    private var observer: AXObserver?
    /// A listing is on the queue; another asked for meanwhile runs after it.
    private var listing = false
    private var again = false
    /// Bumped by `setHidden`: a listing that read the hidden file before
    /// keeps the newer set when it comes in.
    private var hiddenChanges = 0

    private init() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        barURL = TrayBarFile.url(environment: environment, home: home)
        hiddenURL = TrayHiddenFile.url(environment: environment, home: home)
    }

    /// Call once: lists now, then on every launch, quit and bar change.
    func start() {
        guard workspace.isEmpty else { return }
        mode.withLock { $0 = .running }
        let center = NSWorkspace.shared.notificationCenter
        workspace = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TrayWatcher.shared.noted(.launched) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TrayWatcher.shared.noted(.quit) }
            },
        ]
        refresh()
    }

    /// A listing now (the dropdown opening), off the main thread; `latest`
    /// changes when it's in. Covers any settle pending. Nothing before
    /// `start` (a render lists nothing).
    func refresh() {
        guard mode.withLock({ $0 == .running }) else { return }
        settle.listed(at: Date())
        settleTimer?.invalidate()
        settleTimer = nil
        guard !listing else {
            again = true
            return
        }
        listing = true
        let changes = hiddenChanges
        queue.async { [self] in
            let fresh = list()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(fresh, hiddenChanges: changes) } }
        }
    }

    /// Hide or show items (the dropdown's menu): the hidden file is
    /// written and the count follows, from the latest listing (before the
    /// first listing, from that listing, which reads the file after this).
    func setHidden(_ hidden: Set<String>) {
        guard mode.withLock({ $0 == .running }) else { return }
        guard let latest else {
            if listing { again = true }
            queue.async { [self] in writeHidden(hidden) }
            return
        }
        let changed = Listing(items: latest.items, hidden: hidden, accessible: latest.accessible)
        self.latest = changed
        hiddenChanges += 1
        // A listing under way counted with the old set: one more after it.
        if listing { again = true }
        // After any listing under way (the queue is serial): its count, from
        // the old set, is replaced.
        queue.async { [self] in
            writeHidden(hidden)
            write(changed.accessible ? changed.count : nil)
        }
    }

    /// The permission poll (every 2 s, AppModel): Accessibility granted or
    /// taken away since the last listing lists again, so the count comes, or
    /// goes from the bar, without waiting for a launch or the panel.
    func ensure() {
        guard let latest, latest.accessible != AX.trusted else { return }
        refresh()
    }

    /// Every exit path: the observers go, and the file, so the bar never
    /// shows a stale count; the bar is told.
    func stop() {
        for token in workspace { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspace = []
        settleTimer?.invalidate()
        settleTimer = nil
        settle.listed(at: Date())
        install(nil)
        observedPID.withLock { $0 = nil }
        let removed = mode.withLock { mode -> Bool in
            mode = .stopped
            return (try? TrayBarFile.update(nil, at: barURL)) ?? false
        }
        // Waited for (half a second at most): the app may be about to exit.
        if removed { Self.trigger(timeout: 0.5) }
    }

    // MARK: - Settling

    /// An app launched or quit, or MenuBarAgent's bar changed: a listing
    /// once things settle. The timer is one-shot, set for the settle's end.
    private func noted(_ event: TraySettle.Event) {
        guard mode.withLock({ $0 == .running }) else { return }
        schedule(settle.note(event, at: Date()))
    }

    private func schedule(_ due: Date) {
        settleTimer?.invalidate()
        let timer = Timer(fire: due, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { TrayWatcher.shared.settled() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func settled() {
        settleTimer = nil
        if settle.fire(at: Date()) {
            refresh()
        } else if let due = settle.due {
            schedule(due)
        }
    }

    private func finish(_ fresh: Listing, hiddenChanges changes: Int) {
        listing = false
        if changes != hiddenChanges, let latest {
            self.latest = Listing(items: fresh.items, hidden: latest.hidden, accessible: fresh.accessible)
        } else {
            latest = fresh
        }
        if again {
            again = false
            refresh()
        }
    }

    // MARK: - The queue

    private nonisolated func writeHidden(_ hidden: Set<String>) {
        do {
            try TrayHiddenFile.write(hidden, to: hiddenURL)
        } catch {
            Self.log.error("cannot write \(self.hiddenURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// On the queue: the bar read, the hidden set, the count written, and
    /// the observer re-made if MenuBarAgent's pid changed.
    private nonisolated func list() -> Listing {
        let accessible = AX.trusted
        watchAgent(accessible: accessible)
        let items = accessible ? StatusItemLocator.allItems().filter { !TrayItems.shown([$0.0]).isEmpty } : []
        let fresh = Listing(items: items, hidden: TrayHiddenFile.read(hiddenURL), accessible: accessible)
        write(accessible ? fresh.count : nil)
        return fresh
    }

    /// On the queue: the count's file, and the bar told when it changed.
    private nonisolated func write(_ count: Int?) {
        let changed = mode.withLock { mode -> Bool in
            guard mode == .running else { return false }
            do {
                return try TrayBarFile.update(count, at: barURL)
            } catch {
                Self.log.error("cannot write \(self.barURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        if changed { triggerQueue.async { Self.trigger(timeout: 2) } }
    }

    /// On the queue: an observer for MenuBarAgent's pid when it isn't the
    /// one watched (it restarted, or this is the first listing), handed to
    /// the main run loop. Its messages are timed like every other. One that
    /// can't be made leaves none, and the next listing tries again.
    private nonisolated func watchAgent(accessible: Bool) {
        let pid = accessible ? AX.runningPID(bundleID: StatusItems.agentBundleID) : nil
        let changed = observedPID.withLock { observed -> Bool in
            guard observed != pid else { return false }
            observed = pid
            return true
        }
        guard changed else { return }
        guard let pid else {
            DispatchQueue.main.async { MainActor.assumeIsolated { TrayWatcher.shared.install(nil) } }
            return
        }
        /// No observer for `pid`: the old one goes, and the next listing retries.
        let failed = { [self] in
            observedPID.withLock { if $0 == pid { $0 = nil } }
            DispatchQueue.main.async { MainActor.assumeIsolated { TrayWatcher.shared.install(nil) } }
        }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in
            // Delivered on the main run loop, where the source was added.
            MainActor.assumeIsolated { TrayWatcher.shared.noted(.barChanged) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            Self.log.error("no Accessibility observer for MenuBarAgent (pid \(pid))")
            failed()
            return
        }
        let app = AX.app(pid)
        let taken = Self.notifications.filter {
            AXObserverAddNotification(created, app, $0 as CFString, nil) == .success
        }
        Self.log.info("MenuBarAgent (pid \(pid)) observer took \(taken.joined(separator: ", "), privacy: .public)")
        guard !taken.isEmpty else {
            failed()
            return
        }
        let box = ObserverBox(observer: created)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // Stopped meanwhile, or a newer pid's on its way: dropped,
                // and (stopped) the pid forgotten, so a start makes one again.
                let watcher = TrayWatcher.shared
                guard watcher.mode.withLock({ $0 == .running }),
                      watcher.observedPID.withLock({ $0 }) == pid else {
                    watcher.observedPID.withLock { if $0 == pid { $0 = nil } }
                    return
                }
                TrayWatcher.shared.install(box.observer)
            }
        }
    }

    /// The observer on the main run loop, in place of the last; nil: none.
    private func install(_ new: AXObserver?) {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = new
        if let new {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(new), .commonModes)
        }
    }

    /// An observer made on the queue, carried to the main thread, where
    /// alone it is used from then on.
    private struct ObserverBox: @unchecked Sendable {
        let observer: AXObserver
    }

    /// `sketchybar --trigger tray_change`: the bar's `tray` item reads the
    /// file again. Nothing when SketchyBar isn't installed.
    private nonisolated static func trigger(timeout: TimeInterval) {
        guard let sketchybar else { return }
        let run = Subprocess.run(sketchybar, ["--trigger", "tray_change"], timeout: timeout)
        if run.status != 0 {
            log.error("sketchybar --trigger tray_change: status \(run.status), timed out \(run.timedOut)")
        }
    }
}
