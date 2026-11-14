import AppKit
import Combine
import CoreServices
import GroveKeysCore
import GroveThemesCore
import os

/// The one cloud tracker in Grove Keys (spec 2026-11-14-bar-cloud-design):
/// whether iCloud Drive and the providers in `~/Library/CloudStorage` have
/// finished syncing. `summary` is every provider's section and the pill, for
/// the cloud dropdown; `$GROVE_STATE/cloud` is the bar's cloud (`checking`,
/// `synced`, `syncing <n>`, `problem`), rewritten only when it changes, and
/// then the bar is sent `cloud_change`; removed when Grove Keys stops.
///
/// The work is `CloudEngine`'s, on a thread of its own; this is the main
/// thread's side: the published summary and which provider apps are running.
@MainActor
final class CloudTracker: ObservableObject {
    static let shared = CloudTracker()

    /// The latest summary: checking, with no providers, until the engine's first.
    @Published private(set) var summary = CloudSummary(
        places: [], pending: CloudPending(), access: { _ in .ok }, firstPassDone: false)

    private let engine: CloudEngine
    private var started = false
    private var apps: NSKeyValueObservation?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        engine = CloudEngine(
            home: home,
            barFile: CloudBarFile.url(environment: ProcessInfo.processInfo.environment, home: home),
            sketchybar: CloudEngine.installedSketchybar)
    }

    /// Call once (a stopped tracker isn't started again).
    func start() {
        guard !started else { return }
        started = true
        engine.onSummary = { summary in
            DispatchQueue.main.async { MainActor.assumeIsolated { CloudTracker.shared.summary = summary } }
        }
        // OneDrive's process, for "OneDrive isn't running" (iCloud's is always there).
        apps = NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { CloudTracker.shared.appsChanged() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { CloudTracker.shared.appsChanged() } }
            }
        }
        engine.start()
    }

    private func appsChanged() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        engine.setRunning(ids.intersection([CloudProviderSummary.oneDriveBundleID]))
    }

    /// Every exit path: the file goes, so the bar never shows a stale cloud
    /// (no file is a grey one), and the bar is told.
    func stop() {
        apps?.invalidate()
        apps = nil
        engine.stop()
    }
}

/// The tracker's work, on one thread (`run`) with materialisation turned
/// off: every lstat, listing and resource-value read of a cloud folder
/// happens there, paced by `CloudPace.files`. FSEvents (one stream per
/// provider's folder, file-level, coalesced over a second) and a watch on
/// CloudStorage itself only put events in the inbox (`CloudEventBatch`,
/// bounded), which the thread takes a batch at a time.
///
/// The thread: re-reads the roots when they may have changed; handles a
/// batch of events (a file read, a folder walked, a removal settled); takes
/// one step of the walk under way (the first pass, a folder that appeared, a
/// re-walk after the cap or a refusal); re-reads the pending items due; lets
/// those unchanged for 30 minutes turn into problems; publishes the summary
/// and the bar's line when they change; waits for the pace, and for more to
/// do (the next re-read, events, or a minute at most).
final class CloudEngine: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.projectgrove.keys", category: "cloud")
    static let installedSketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// FSEvents' coalescing: a burst within a second is one callback.
    static let latency: CFTimeInterval = 1
    /// The longest the thread sleeps (the 30 minutes are checked, the roots re-read).
    static let tick: TimeInterval = 60
    /// A provider that refused its files is tried again this rarely.
    static let refusedRetry: TimeInterval = 600
    /// A root's re-walk after the cap is not repeated sooner than this.
    static let rescanGap: TimeInterval = 60
    /// Per turn of the loop: entries a walk looks at, events, re-reads.
    static let walkBudget = 200
    static let eventsPerTurn = 500
    static let rereadsPerTurn = 500
    /// A walk asked for by events waits until they've been quiet this long
    /// (a burst, an unzip, is walked once at its end), but no longer than `settleMost`.
    static let settle: TimeInterval = 2
    static let settleMost: TimeInterval = 30

    private enum Mode { case idle, running, stopped }

    /// What the engine has done, for the log and a look from outside.
    struct Stats: Equatable, Sendable {
        var events = 0
        var reads = 0
        var walked = 0
        var walksDone = 0
    }

    private let counted = OSAllocatedUnfairLock(initialState: Stats())
    var stats: Stats { counted.withLock { $0 } }

    private struct Walk {
        enum Kind { case first, expand, rescan, retry }
        var walker: CloudWalker
        let kind: Kind
        /// Not started before (events asked for it: they settle first).
        var notBefore = Date.distantPast
        var asked = Date.distantPast
        /// An item it found couldn't join (the set was full).
        var dropped = false
        var root: URL { walker.root }
        var isWholeRoot: Bool { walker.start.standardizedFileURL == walker.root.standardizedFileURL }
    }

    private let home: URL
    private let barFile: URL
    private let sketchybar: String?
    private let fs = CloudPOSIX()
    private let pace = CloudPace.files
    /// Set before `start`; called on the engine's thread.
    var onSummary: (@Sendable (CloudSummary) -> Void)?

    // Shared with the event queue and the main thread, under `condition`.
    private let condition = NSCondition()
    private var inbox = CloudEventBatch()
    private var roots = CloudRoots([])
    private var running: Set<String> = []
    private var runningChanged = false
    private var stopping = false
    /// The file is written only between `start` and `stop`.
    private let mode = OSAllocatedUnfairLock(initialState: Mode.idle)

    // The engine thread's own.
    private var places: [CloudProviders.CloudPlace] = []
    private var pending = CloudPending()
    private var walks: [Walk] = []
    private var refused: [String: Date] = [:]
    private var loggedRefused: Set<String> = []
    private var firstPassLeft: Set<String> = []
    private var firstPassDone = false
    private var lastRescan: [String: Date] = [:]
    private var nextRootsCheck = Date.distantPast
    private var streams: [String: FSEventStreamRef] = [:]
    private var storageWatch: DispatchSourceFileSystemObject?
    private var published: CloudSummary?
    private var lastLine: String?
    private var thread: Thread?

    private let eventQueue = DispatchQueue(label: "com.projectgrove.keys.cloud.events", qos: .utility)
    private let triggerQueue = DispatchQueue(label: "com.projectgrove.keys.cloud.trigger", qos: .utility)

    init(home: URL, barFile: URL, sketchybar: String?) {
        self.home = home
        self.barFile = barFile
        self.sketchybar = sketchybar
    }

    private var storage: URL { home.appendingPathComponent(CloudProviders.cloudStorage, isDirectory: true) }

    func start() {
        guard thread == nil else { return }
        mode.withLock { $0 = .running }
        let thread = Thread { [self] in run() }
        thread.name = "Grove Keys cloud"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    /// The provider apps running (bundle ids).
    func setRunning(_ ids: Set<String>) {
        condition.withLock {
            guard ids != running else { return }
            running = ids
            runningChanged = true
            condition.signal()
        }
    }

    func stop() {
        condition.withLock {
            stopping = true
            condition.signal()
        }
        let removed = mode.withLock { mode -> Bool in
            mode = .stopped
            return (try? CloudBarFile.update(nil, at: barFile)) ?? false
        }
        if removed { trigger(timeout: 0.5) }
    }

    /// From FSEvents (the event queue): sorted and coalesced into the inbox.
    fileprivate func received(_ events: [(String, UInt32)]) {
        condition.withLock {
            for (path, flags) in events {
                for event in CloudEvents.classify(path: path, flags: flags, roots: roots) { inbox.add(event) }
            }
            condition.signal()
        }
    }

    /// CloudStorage itself changed: a provider's folder came or went.
    private func storageChanged() {
        condition.withLock {
            inbox.add(.roots)
            condition.signal()
        }
    }

    // MARK: The engine's thread

    private func run() {
        guard CloudWalk.turnOffMaterialization() else {
            // Never walk without it: the pill stays grey, "checking".
            Self.log.error("cannot turn off materialisation of dataless files; not following the clouds")
            publish()
            return
        }
        refreshRoots(at: Date())
        publish()
        while true {
            condition.lock()
            while !stopping && inbox.isEmpty && !runningChanged && !walks.contains(where: { $0.notBefore <= Date() }) {
                if !condition.wait(until: nextDeadline()) { break }
            }
            if stopping {
                condition.unlock()
                break
            }
            let rootsChanged = inbox.rootsChanged
            let events = inbox.take(Self.eventsPerTurn)
            runningChanged = false
            condition.unlock()

            let began = Date()
            var done = 0
            if rootsChanged || began >= nextRootsCheck { done += refreshRoots(at: began) }
            for event in events { done += handle(event, at: began) }
            done += stepWalk(at: began)
            done += reread(at: began)
            pending.expire(at: began)
            scheduleWalks(at: began)
            publish()
            counted.withLock { $0.events += events.count }
            let wait = pace.wait(done: done, took: Date().timeIntervalSince(began))
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        for root in Array(streams.keys) { stopStream(root) }
        storageWatch?.cancel()
        storageWatch = nil
    }

    private func nextDeadline() -> Date {
        let now = Date()
        var next = min(now + Self.tick, nextRootsCheck)
        if let read = pending.nextRead { next = min(next, read) }
        for walk in walks { next = min(next, walk.notBefore) }
        for at in refused.values { next = min(next, at + Self.refusedRetry) }
        if pending.hasRoom {
            for root in pending.rootsNeedingRescan {
                next = min(next, (lastRescan[root.path] ?? .distantPast) + Self.rescanGap)
            }
        }
        return next
    }

    /// The places: iCloud Drive's folder when it's there, then each folder
    /// in CloudStorage. A new one gets its stream and its first walk; one
    /// gone takes its items, stream and walks with it.
    @discardableResult
    private func refreshRoots(at now: Date) -> Int {
        nextRootsCheck = now + Self.tick
        let iCloud = home.appendingPathComponent(CloudProviders.iCloudDrive, isDirectory: true)
        let iCloudPresent = (try? fs.lstat(iCloud.path).get())?.kind == .directory
        let names = ((try? fs.list(storage.path).get()) ?? []).filter {
            (try? fs.lstat(storage.path + "/" + $0).get())?.kind == .directory
        }
        let fresh = CloudSummary.places(iCloudPresent: iCloudPresent, cloudStorage: names, home: home)
        let old = Set(places.map(\.url.path))
        let new = Set(fresh.map(\.url.path))
        for place in places where !new.contains(place.url.path) {
            Self.log.info("cloud folder gone: \(place.title, privacy: .private)")
            pending.removeRoot(place.url)
            stopStream(place.url.path)
            walks.removeAll { $0.root.path == place.url.path }
            refused[place.url.path] = nil
            firstPassLeft.remove(place.url.path)
            lastRescan[place.url.path] = nil
        }
        pending.retainRoots(fresh.map(\.url))
        places = fresh
        if old != new {
            condition.withLock { roots = CloudRoots(fresh.map(\.url)) }
        }
        for place in fresh where !old.contains(place.url.path) {
            startStream(place.url)
            walks.append(Walk(walker: CloudWalker(root: place.url), kind: .first))
            if !firstPassDone { firstPassLeft.insert(place.url.path) }
        }
        if firstPassLeft.isEmpty && walks.allSatisfy({ $0.kind != .first }) { firstPassDone = true }
        watchStorage()
        return 2 + names.count
    }

    /// One watch on CloudStorage's own listing (not its contents).
    private func watchStorage() {
        if storageWatch?.isCancelled == true { storageWatch = nil }
        guard storageWatch == nil else { return }
        let fd = open(storage.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: eventQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                // CloudStorage itself went: watch again once it's back.
                source.cancel()
                self.condition.withLock { self.inbox.add(.roots); self.condition.signal() }
                return
            }
            self.storageChanged()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        // Cancelled when CloudStorage goes; made again on the next roots check.
        storageWatch = source
    }

    private func startStream(_ root: URL) {
        guard streams[root.path] == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            // FSEvents watches real paths (no links on the way).
            kCFAllocatorDefault, cloudEventsCallback, &context, [CloudRoots.realPath(root)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags)
        else {
            Self.log.error("cannot watch a cloud folder: FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Self.log.error("cannot watch a cloud folder: FSEventStreamStart failed")
            return
        }
        streams[root.path] = stream
    }

    private func stopStream(_ path: String) {
        guard let stream = streams.removeValue(forKey: path) else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(_ event: CloudEvent, at now: Date) -> Int {
        guard let url = event.url, let root = event.root, places.contains(where: { $0.url.path == root.path })
        else { return 0 }
        // A provider that refused its files isn't asked again until its retry.
        guard refused[root.path] == nil else { return 0 }
        switch event {
        case .read:
            // A walk of a folder it's in, not begun yet, will read it fresh.
            let path = url.standardizedFileURL.path
            if walks.contains(where: { $0.walker.operations == 0 && path.hasPrefix($0.walker.start.path + "/") }) {
                return 0
            }
            read(url, root: root, at: now, touched: true)
            return 1
        case .expand:
            addWalk(Walk(walker: CloudWalker(root: root, start: url), kind: .expand), at: now)
        case .rescan:
            let whole = url.standardizedFileURL == root.standardizedFileURL
            addWalk(Walk(walker: CloudWalker(root: root, start: url), kind: whole ? .rescan : .expand), at: now)
        case .gone:
            settle(under: url)
        case .roots:
            break
        }
        return 0
    }

    /// A walk events asked for: it waits for them to settle. One of the
    /// same folder (or of the whole root) already waiting covers it, and
    /// waits a little longer.
    private func addWalk(_ walk: Walk, at now: Date) {
        if let index = walks.firstIndex(where: {
            $0.root.path == walk.root.path && ($0.walker.start.path == walk.walker.start.path || $0.isWholeRoot)
                && $0.walker.operations == 0
        }) {
            // A pass waiting to start (the first, a re-walk) isn't held back by events.
            if walks[index].asked != .distantPast {
                walks[index].notBefore = min(now + Self.settle, walks[index].asked + Self.settleMost)
            }
            return
        }
        var walk = walk
        walk.asked = now
        walk.notBefore = now + Self.settle
        walks.append(walk)
    }

    /// One step of a walk: a folder that appeared before the passes (they
    /// are small, and what the owner just did), then in order.
    private func stepWalk(at now: Date) -> Int {
        guard let index = walks.firstIndex(where: { $0.kind == .expand && $0.notBefore <= now })
            ?? walks.firstIndex(where: { $0.notBefore <= now })
        else { return 0 }
        var walk = walks.remove(at: index)
        let root = walk.root
        let before = walk.walker.operations
        // A retry starts hopeful: a refusal on the way marks it again (and
        // the next try is ten minutes on).
        if walk.kind == .retry && before == 0 { refused[root.path] = nil }
        var dropped = false
        var reads = 0
        let outcome = walk.walker.step(budget: Self.walkBudget, fs: fs) { url in
            reads += 1
            if read(url, root: root, at: now, touched: false) == .dropped { dropped = true }
        }
        walk.dropped = walk.dropped || dropped
        let used = walk.walker.operations - before + reads
        let walked = walk.walker.operations - before
        counted.withLock {
            $0.walked += walked
            if outcome != .more { $0.walksDone += 1 }
        }
        if refused[root.path] != nil || outcome == .refused {
            // Refused on the way (a file's read, or the folder's listing).
            if outcome == .refused, walk.isWholeRoot { markRefused(root, at: now) }
            finished(walk)
            return used
        }
        if walk.kind == .retry && outcome == .done { loggedRefused.remove(root.path) }
        switch outcome {
        case .more:
            walks.insert(walk, at: index)
        case .done, .refused:
            finished(walk)
        case .gone:
            if walk.isWholeRoot {
                nextRootsCheck = .distantPast
            } else {
                settle(under: walk.walker.start)
            }
            finished(walk)
        }
        return used
    }

    private func finished(_ walk: Walk) {
        let root = walk.root
        if walk.kind == .first || walk.kind == .retry, walk.isWholeRoot {
            firstPassLeft.remove(root.path)
            if firstPassLeft.isEmpty && !walks.contains(where: { $0.kind == .first }) { firstPassDone = true }
        }
        // A whole re-walk that kept everything it found accounts for the dropped items.
        if walk.isWholeRoot, !walk.dropped, refused[root.path] == nil, pending.needsRescan(root) {
            pending.rescanned(root: root)
        }
    }

    /// Pending items due a re-read, a fresh read each.
    private func reread(at now: Date) -> Int {
        let due = pending.due(at: now).prefix(Self.rereadsPerTurn)
        guard !due.isEmpty else { return 0 }
        let byPath = Dictionary(pending.entries.map { ($0.url.path, $0.root) }, uniquingKeysWith: { a, _ in a })
        for url in due {
            guard let root = byPath[url.path] else { continue }
            read(url, root: root, at: now, touched: false)
        }
        return due.count
    }

    /// Room again after the cap: re-walk the roots whose items were dropped.
    /// A refused provider: try again, rarely.
    private func scheduleWalks(at now: Date) {
        if pending.hasRoom {
            for root in pending.rootsNeedingRescan where refused[root.path] == nil {
                guard !walks.contains(where: { $0.root.path == root.path && $0.isWholeRoot }),
                      now.timeIntervalSince(lastRescan[root.path] ?? .distantPast) >= Self.rescanGap
                else { continue }
                lastRescan[root.path] = now
                walks.append(Walk(walker: CloudWalker(root: root), kind: .rescan))
            }
        }
        for (path, at) in refused where now.timeIntervalSince(at) >= Self.refusedRetry {
            guard let place = places.first(where: { $0.url.path == path }),
                  !walks.contains(where: { $0.root.path == path })
            else { continue }
            refused[path] = now
            walks.append(Walk(walker: CloudWalker(root: place.url), kind: .retry))
        }
    }

    private enum ReadOutcome { case kept, dropped, gone, refused, failed }

    /// One item, read fresh (a new URL, no cached values), into the set.
    @discardableResult
    private func read(_ url: URL, root: URL, at now: Date, touched: Bool) -> ReadOutcome {
        counted.withLock { $0.reads += 1 }
        do {
            let state = CloudItemState(try CloudItemValues.read(path: url.path))
            let dropped = state != .settled && !pending.hasRoom && !pending.contains(url)
            pending.update(url, root: root, state: state, at: now, touched: touched)
            return dropped ? .dropped : .kept
        } catch {
            switch Self.posixCode(error) {
            case ENOENT?, ENOTDIR?:
                settle(under: url)
                return .gone
            case EPERM?, EACCES?:
                markRefused(root, at: now)
                return .refused
            default:
                // Left as it was, counted as read: the next re-read (on the
                // backoff, not at once) tries again.
                if let entry = pending.entries.first(where: { $0.url.path == url.standardizedFileURL.path }) {
                    pending.update(url, root: root, state: entry.read, at: now)
                }
                return .failed
            }
        }
    }

    private static func posixCode(_ error: Error) -> Int32? {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain { return Int32(error.code) }
        if let under = error.userInfo[NSUnderlyingErrorKey] as? NSError, under.domain == NSPOSIXErrorDomain {
            return Int32(under.code)
        }
        guard error.domain == NSCocoaErrorDomain else { return nil }
        switch error.code {
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return ENOENT
        case NSFileReadNoPermissionError: return EPERM
        default: return nil
        }
    }

    /// macOS refused the provider's files: "can't see", the pill ignores
    /// it, its walks stop and it's tried again in ten minutes.
    private func markRefused(_ root: URL, at now: Date) {
        if refused[root.path] == nil { refused[root.path] = now }
        if loggedRefused.insert(root.path).inserted {
            Self.log.info("macOS refused a cloud folder's files; trying again in \(Int(Self.refusedRetry)) s")
        }
        pending.removeRoot(root)
        walks.removeAll { $0.root.path == root.path && $0.kind != .retry }
        firstPassLeft.remove(root.path)
        if firstPassLeft.isEmpty && !walks.contains(where: { $0.kind == .first }) { firstPassDone = true }
    }

    /// The item, and anything that was in it, left the set.
    private func settle(under url: URL) {
        let path = url.standardizedFileURL.path
        pending.settle(url)
        for entry in pending.entries where entry.url.standardizedFileURL.path.hasPrefix(path + "/") {
            pending.settle(entry.url)
        }
    }

    private func access(_ place: CloudProviders.CloudPlace, running: Set<String>) -> CloudProviderAccess {
        if let id = CloudProviderSummary.bundleID(for: place), !running.contains(id) { return .notRunning }
        return refused[place.url.path] == nil ? .ok : .cantSee
    }

    private func publish() {
        let running = condition.withLock { self.running }
        let summary = CloudSummary(
            places: places, pending: pending, access: { self.access($0, running: running) },
            firstPassDone: firstPassDone)
        if summary != published {
            published = summary
            onSummary?(summary)
        }
        guard summary.pill.line != lastLine else { return }
        lastLine = summary.pill.line
        let changed = mode.withLock { mode -> Bool in
            guard mode == .running else { return false }
            do {
                return try CloudBarFile.update(summary.pill, at: barFile)
            } catch {
                Self.log.error("cannot write \(self.barFile.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        if changed { triggerQueue.async { self.trigger(timeout: 2) } }
    }

    /// `sketchybar --trigger cloud_change`: the bar's `cloud` item reads the
    /// file again. Nothing when SketchyBar isn't installed.
    private func trigger(timeout: TimeInterval) {
        guard let sketchybar else { return }
        let run = Subprocess.run(sketchybar, ["--trigger", "cloud_change"], timeout: timeout)
        if run.status != 0 {
            Self.log.error("sketchybar --trigger cloud_change: status \(run.status), timed out \(run.timedOut)")
        }
    }
}

/// FSEvents' callback (a C function): the engine is the stream's context,
/// alive as long as the app (a singleton's).
private func cloudEventsCallback(
    _ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int,
    _ paths: UnsafeMutableRawPointer, _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let engine = Unmanaged<CloudEngine>.fromOpaque(info).takeUnretainedValue()
    let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
    var events: [(String, UInt32)] = []
    events.reserveCapacity(count)
    for i in 0..<min(count, list.count) {
        if let path = list[i] as? String { events.append((path, flags[i])) }
    }
    engine.received(events)
}
