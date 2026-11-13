import AppKit
import GroveExplorerCore
import NetFS

/// Mounts shares as Finder's Connect to Server does, through NetFS: macOS
/// shows its own password sheet (and keeps the password in the Keychain),
/// picks the mount point under /Volumes and says where the share landed.
/// The app never sees a password.
///
/// One request per share (`SharedServers.key`): a second `mount` of the same
/// address joins the first. There is no timer of the app's own (spec): the
/// answer comes when everything is over, the password sheet included, and
/// macOS's own timeout ends a server that doesn't answer; `cancel` ends it
/// sooner. Answers come on the main actor.
@MainActor
final class Mounter {
    private struct Request {
        /// Which request this is: an answer for one cancelled or replaced is dropped.
        let number: Int
        let server: URL
        /// NetFS's `AsyncRequestID`, as its bits (0 until NetFS gives it).
        var id: UInt
        var waiting: [(MountOutcome) -> Void]
    }

    private var requests: [String: Request] = [:]
    private var count = 0
    /// Where NetFS delivers its answer; it is taken to the main actor from there.
    private let queue = DispatchQueue(label: "grove-explorer.mounts", qos: .userInitiated)

    /// Mounts `url` with the default options, and calls `completion` with
    /// what it ended in (`.quiet` when cancelled, here or in the password sheet).
    func mount(_ url: URL, completion: @escaping (MountOutcome) -> Void) {
        let key = SharedServers.key(url)
        if requests[key] != nil {
            requests[key]?.waiting.append(completion)
            return
        }
        count += 1
        let number = count
        requests[key] = Request(number: number, server: url, id: 0, waiting: [completion])
        let (status, id) = Self.start(url, on: queue) { [weak self] status, paths in
            Task { @MainActor in self?.finished(key, number: number, status: status, paths: paths) }
        }
        // Refused before it began: NetFS sends no answer of its own then.
        guard status == 0 else {
            finished(key, number: number, status: status, paths: [])
            return
        }
        requests[key]?.id = id
    }

    /// Gives up the mount of `url`: its waiters hear `.quiet` (NetFS sends
    /// no answer for a cancelled request).
    func cancel(_ url: URL) {
        let key = SharedServers.key(url)
        guard let request = requests.removeValue(forKey: key) else { return }
        if let id = UnsafeMutableRawPointer(bitPattern: request.id) { _ = NetFSMountURLCancel(id) }
        for waiter in request.waiting { waiter(.quiet) }
    }

    private func finished(_ key: String, number: Int, status: Int32, paths: [String]) {
        guard let request = requests[key], request.number == number else { return }
        requests[key] = nil
        let point = paths.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let outcome = SharedServers.outcome(status: status, mountPoint: point, server: request.server)
        for waiter in request.waiting { waiter(outcome) }
    }

    /// `NetFSMountURLAsync` (nil mount path, user, password and options:
    /// macOS's defaults, its authentication UI included). Not on the main
    /// actor, so the answer block isn't taken for the main actor's.
    nonisolated private static func start(
        _ url: URL, on queue: DispatchQueue, report: @escaping @Sendable (Int32, [String]) -> Void
    ) -> (status: Int32, id: UInt) {
        var requestID: AsyncRequestID?
        let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil, nil, nil, &requestID, queue) { status, _, mountpoints in
            let paths = (mountpoints as NSArray?) as? [String] ?? []
            report(status, paths)
        }
        return (status, UInt(bitPattern: requestID))
    }
}

/// A share this window just mounted: its row is connected at `point`
/// until a read of the volumes begun after the mount (`read` counts them) lands.
struct PendingMount: Equatable {
    let point: URL
    let read: Int
}

/// The saved shares in the sidebar's Locations: connecting, saving and forgetting them.
extension AppModel {
    // MARK: What the rows show

    /// Each saved share's mounted volume, by the share's id. A volume this
    /// window mounted is the share it mounted; any other network volume is
    /// matched by its address (`SharedServers.match`). One volume per share,
    /// the first: a second mount of a share stays in Locations.
    func shareVolumes() -> [String: Volume] {
        let servers = config.servers
        guard !servers.isEmpty else { return [:] }
        let saved = Set(servers.map(\.id))
        var found: [String: Volume] = [:]
        for volume in volumes where volume.isNetwork || volume.remountURL != nil || sharesMountedHere[volume.id] != nil {
            let id = sharesMountedHere[volume.id].flatMap { saved.contains($0) ? $0 : nil }
                ?? SharedServers.match(mountedRemountURL: volume.remountURL, volumeName: volume.name, among: servers)?.id
            if let id, found[id] == nil { found[id] = volume }
        }
        return found
    }

    /// A share's row: connected (at its place's folder), connecting or not.
    func shareState(_ place: Place) -> SharedRowState? {
        guard case .share(let server) = place.kind else { return nil }
        return SharedServers.state(saved: server, mounted: place.url, connecting: connectingShares.contains(server.id))
    }

    func isConnecting(_ place: Place) -> Bool { shareState(place) == .connecting }

    // MARK: Connecting

    /// A click on a share that is not connected: it mounts and, mounted,
    /// opens in the active pane. A failure is said in that pane's notice
    /// line; a cancelled password sheet says nothing.
    func connect(_ server: SharedServer) {
        guard live, !connectingShares.contains(server.id), shareVolumes()[server.id] == nil else { return }
        connectingShares.insert(server.id)
        mounter.mount(server.url) { [weak self] outcome in
            guard let self else { return }
            self.connectingShares.remove(server.id)
            switch outcome {
            case .mounted(let point):
                self.mounted(server.id, at: point)
                self.go(to: point)
            case .quiet:
                break
            case .alreadyMounted:
                Task { @MainActor in
                    if let volume = await self.alreadyMountedVolume(server.url) {
                        self.mounted(server.id, at: volume.url)
                        self.go(to: volume.url)
                    } else {
                        self.say(SharedServers.couldNotConnect(to: server.url, status: EEXIST), in: self.browser.active)
                    }
                }
            case .failed(let sentence):
                self.say(sentence, in: self.browser.active)
            }
        }
    }

    /// The spinner on a share's row (or Esc on it): the mount is given up, quietly.
    func cancelConnect(_ server: SharedServer) {
        guard live, connectingShares.contains(server.id) else { return }
        mounter.cancel(server.url)
    }

    /// The Connect to Server sheet's Connect: `text` is mounted, and saved
    /// only once it has (a typo isn't kept), then opened in the active pane.
    /// Nil when it was: the sheet closes. Otherwise the sentence for under
    /// the field; empty when there is nothing to say (the password sheet
    /// was cancelled, or the sheet's Cancel gave the mount up).
    func connectNew(_ text: String) async -> String? {
        let url: URL
        switch SharedAddress.parse(text) {
        case .success(let address): url = address
        case .failure(let problem): return problem.sentence
        }
        guard live else { return "" }
        // Mounted already (by Finder, the command line): kept, and opened as
        // it is. Only by the address macOS mounted it by, never by its name
        // alone: smb://other/media is not another server's "media".
        let share = SharedServer(url: url)
        if let volume = volumes.first(where: { volume in
            guard let remount = volume.remountURL else { return false }
            return SharedServers.match(mountedRemountURL: remount, volumeName: volume.name, among: [share]) != nil
        }) {
            if let saved = keepShare(url) { sharesMountedHere[volume.id] = saved.id }
            opened(volume.url)
            return nil
        }
        sheetMount = url
        let outcome = await withCheckedContinuation { (answer: CheckedContinuation<MountOutcome, Never>) in
            mounter.mount(url) { answer.resume(returning: $0) }
        }
        if sheetMount == url { sheetMount = nil }
        switch outcome {
        case .mounted(let point):
            if let saved = keepShare(url) { mounted(saved.id, at: point) }
            opened(point)
            return nil
        case .quiet:
            return ""
        case .alreadyMounted:
            guard let volume = await alreadyMountedVolume(url) else {
                return SharedServers.couldNotConnect(to: url, status: EEXIST)
            }
            if let saved = keepShare(url) { sharesMountedHere[volume.id] = saved.id }
            opened(volume.url)
            return nil
        case .failed(let sentence):
            return sentence
        }
    }

    /// NetFS says `url` is mounted already (EEXIST), as macOS spells its
    /// server another way (`grove-lab.local`): the volumes read again, and
    /// the one that is it (`SharedServers.alreadyMounted`); nil when none is.
    private func alreadyMountedVolume(_ url: URL) async -> Volume? {
        await readVolumes().value
        let network = volumes.filter { $0.isNetwork || $0.remountURL != nil }
        return SharedServers.alreadyMounted(url, remountURLs: network.map(\.remountURL)).map { network[$0] }
    }

    /// The sheet's Cancel while it connects: the mount is given up.
    func cancelConnectNew() {
        guard live, let url = sheetMount else { return }
        mounter.cancel(url)
    }

    /// ⌘K, File ▸ Connect to Server…, the LOCATIONS header's +.
    func showConnectSheet() {
        sidebarCursor = nil
        if pathField != nil { pathField = nil }
        showsConnectSheet = true
    }

    /// The sheet closes and the share opens in the active pane.
    private func opened(_ point: URL) {
        showsConnectSheet = false
        go(to: point)
        focusList()
    }

    /// `id` was mounted at `point` by this window: that volume is the
    /// share's, and its row is connected until the volumes are read again.
    private func mounted(_ id: String, at point: URL) {
        sharesMountedHere[point.standardizedFileURL.path] = id
        pendingMounts[id] = PendingMount(point: point, read: volumeReads)
        readVolumes()
    }

    // MARK: The saved list

    /// "Remove from Sidebar": the share is forgotten, not ejected; mounted,
    /// it is listed in Locations again.
    func removeShare(_ id: String) {
        if let server = config.servers.first(where: { $0.id == id }) { cancelConnect(server) }
        // Mounted, its row becomes its volume's: the keyboard goes with it.
        let mounted = shareVolumes()[id]
        guard changeServers({ SharedServers.removing(id: id, from: $0) }) != nil else { return }
        pendingMounts[id] = nil
        sharesMountedHere = sharesMountedHere.filter { $0.value != id }
        keepSidebarCursorOnARow(renamed: mounted.map { ["share." + id: "volume." + $0.id] } ?? [:])
    }

    /// "Keep in Sidebar" on a mounted network volume of Locations: its
    /// address (any password left out) is saved, and the volume moves to
    /// its share's row (after the disks).
    func keepInSidebar(_ volume: Volume) {
        guard let url = SharedServers.keepable(remountURL: volume.remountURL, among: config.servers),
            let saved = keepShare(url)
        else { return }
        sharesMountedHere[volume.id] = saved.id
        keepSidebarCursorOnARow(renamed: ["volume." + volume.id: "share." + saved.id])
    }

    /// Saves `url` (unless it is saved already); the share saved, or nil
    /// when the file couldn't be written (the banner says why).
    private func keepShare(_ url: URL) -> SharedServer? {
        let key = SharedServers.key(url)
        return changeServers { SharedServers.adding(url, to: $0) }?.first { SharedServers.key($0.url) == key }
    }

    /// Changes the saved shares and writes them to `explorer.local.toml`
    /// (its favourites and everything else left as they are). The list
    /// changed is the file's as it is now. The list written, or nil when
    /// it wasn't (the banner says why).
    private func changeServers(_ change: ([SharedServer]) -> [SharedServer]) -> [SharedServer]? {
        guard live else { return nil }
        let folder = home.appendingPathComponent(".config/grove-explorer", isDirectory: true)
        let local = folder.appendingPathComponent("explorer.local.toml")
        do {
            // A local file that is there and can't be read is not taken for no file.
            let existing = FileManager.default.fileExists(atPath: local.path)
                ? try String(contentsOf: local, encoding: .utf8) : nil
            let loaded = ExplorerConfig.load(tracked: nil, local: existing, home: home, exists: { _ in true })
            // A local file with a mistake in it (made since the window read
            // it) gives no shares: changing that empty list would empty
            // the saved shares. Refused instead, the banner saying where, the shares as they are.
            if loaded.problem != nil {
                // Its refusal names the line; the second is for a mistake it would let through.
                _ = try ExplorerConfig.localText(favourites: nil, servers: loaded.servers, home: home, keeping: existing)
                throw ConfigWriteRefused(
                    description: "explorer.local.toml can't be read, so it was left as it is and the shared folders were not saved")
            }
            let before = loaded.servers
            let after = change(before)
            if after != before {
                let text = try ExplorerConfig.localText(favourites: nil, servers: after, home: home, keeping: existing)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data(text.utf8).write(to: local, options: .atomic)
            }
            if config.servers != after { config.servers = after }
            writeProblem = nil
            return after
        } catch let refused as ConfigWriteRefused {
            writeProblem = refused.description
        } catch {
            writeProblem = "explorer.local.toml could not be written, so the shared folders were not saved: \(error.localizedDescription)"
        }
        return nil
    }
}
