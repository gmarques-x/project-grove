import AppKit
import GroveExplorerCore

/// A mounted volume, as the sidebar's Locations lists it.
struct Volume: Equatable, Identifiable, Sendable {
    let url: URL
    /// What macOS calls it ("Macintosh HD").
    let name: String
    /// Whether it has an eject button: any volume but the startup disk's
    /// own that macOS says can be ejected or taken out.
    let ejectable: Bool

    var id: String { url.path }

    /// The volumes Finder would show (hidden ones left out). Reads the
    /// disk: called off the main thread.
    static func mounted() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeIsInternalKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isRoot = values?.volumeIsRootFileSystem ?? (url.path == "/")
            let ejectable = !isRoot
                && (values?.volumeIsEjectable == true || values?.volumeIsRemovable == true || values?.volumeIsInternal == false)
            return Volume(
                url: url, name: values?.volumeLocalizedName ?? values?.volumeName ?? url.lastPathComponent,
                ejectable: ejectable)
        }
    }

    /// Unmounts and ejects the volume; the reason when macOS refuses (it
    /// names the app that holds it when it knows). Blocks until done:
    /// called off the main thread.
    static func eject(_ url: URL) -> String? {
        do {
            try NSWorkspace().unmountAndEjectDevice(at: url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// Tells when a volume was mounted, unmounted or renamed. Made once and
/// kept by the model for the app's life: it never stops observing.
@MainActor
final class MountObserver {

    init(onChange: @escaping @MainActor () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification]
        for name in names {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in onChange() }
            }
        }
    }
}

/// A row of the sidebar.
struct Place: Identifiable, Equatable {
    enum Section: String, CaseIterable {
        case favourites = "Favourites", cloud = "iCloud", locations = "Locations"
        /// The Trash, at the bottom, without a caption.
        case trash = ""
    }

    enum Kind: Equatable {
        case favourite, cloud, trash
        case volume(Volume)
    }

    let id: String
    let kind: Kind
    let section: Section
    let title: String
    let url: URL
}

/// The sidebar: its rows, which one is lit, the keyboard in it, ejecting, favourites.
extension AppModel {
    static let cloudFolder = "Library/Mobile Documents/com~apple~CloudDocs"

    /// The sidebar's rows, top to bottom.
    var places: [Place] {
        var places = config.favourites.map {
            Place(id: "favourite." + $0.id, kind: .favourite, section: .favourites, title: $0.title, url: $0.url)
        }
        if hasCloud {
            places.append(Place(
                id: "cloud", kind: .cloud, section: .cloud, title: "iCloud Drive",
                url: home.appendingPathComponent(Self.cloudFolder, isDirectory: true)))
        }
        places += volumes.map {
            Place(id: "volume." + $0.id, kind: .volume($0), section: .locations, title: $0.name, url: $0.url)
        }
        places.append(Place(
            id: "trash", kind: .trash, section: .trash, title: "Trash",
            url: home.appendingPathComponent(".Trash", isDirectory: true)))
        return places
    }

    /// The row lit for the active pane's folder: the nearest favourite
    /// above it; under no favourite, the nearest of iCloud Drive and the
    /// volumes (the startup disk is above everything). Never the Trash.
    func litPlace(among places: [Place]) -> Int? {
        let folder = browser.activeTab.folder
        func nearest(_ wanted: (Place) -> Bool) -> Int? {
            let rows = places.indices.filter { wanted(places[$0]) }
            return Places.nearest(above: folder, among: rows.map { places[$0].url }).map { rows[$0] }
        }
        return nearest { $0.kind == .favourite } ?? nearest { $0.kind != .favourite && $0.kind != .trash }
    }

    /// A click on a row, or Return on it: the place opens in the active
    /// pane's tab (in a new tab with ⌘); the Trash opens in Finder.
    func open(_ place: Place, inNewTab: Bool = false) {
        switch place.kind {
        case .trash:
            guard live else { return }
            NSWorkspace.shared.open(place.url)
        case .favourite, .cloud, .volume:
            if inNewTab { change { $0.newTab(folder: place.url) } } else { go(to: place.url) }
        }
        focusList()
    }

    // MARK: The keyboard in the sidebar

    /// ⌥⌘←: the keyboard goes to the sidebar, on the lit row. The keys
    /// themselves stay with the active pane's list, which hands them on
    /// (`CommandTable.handle`): so a path field that had them closes, and
    /// the list is asked to take them.
    func focusSidebar() {
        if sidebarHidden { sidebarHidden = false }
        if pathField != nil { pathField = nil }
        let places = places
        sidebarCursor = litPlace(among: places) ?? 0
        listFocus += 1
    }

    /// A key while the keyboard is in the sidebar: ↑ ↓ move, Return opens
    /// the place and returns to the list, → or Escape return without
    /// opening. Every other key is held back from the list.
    func sidebarKey(_ key: String) {
        guard let cursor = sidebarCursor else { return }
        let places = places
        switch key {
        case "↑": sidebarCursor = max(0, cursor - 1)
        case "↓": sidebarCursor = min(places.count - 1, cursor + 1)
        case "Return":
            sidebarCursor = nil
            if places.indices.contains(cursor) { open(places[cursor]) }
        case "→", "Escape": sidebarCursor = nil
        default: break
        }
    }

    func toggleSidebar() {
        sidebarHidden.toggle()
        if sidebarHidden { sidebarCursor = nil }
    }

    // MARK: Volumes

    /// The volumes now, and again whenever one comes or goes.
    func followVolumes() {
        mounts = MountObserver { [weak self] in self?.readVolumes() }
        readVolumes()
    }

    private func readVolumes() {
        // Numbered like a pane's reads: of two on their way the later one answers.
        volumeReads += 1
        let number = volumeReads
        let cloud = home.appendingPathComponent(Self.cloudFolder, isDirectory: true)
        Task {
            let (mounted, hasCloud) = await Task.detached { (Volume.mounted(), Disk.isFolder(cloud)) }.value
            guard number == volumeReads else { return }
            if hasCloud != self.hasCloud { self.hasCloud = hasCloud }
            guard mounted != volumes else { return }
            let gone = Set(volumes.map(\.id)).subtracting(mounted.map(\.id))
            // The icons are asked for here, not while a row is drawn (on
            // the main thread still: left so for now).
            IconCache.shared.forgetVolumes()
            for volume in mounted { _ = IconCache.shared.volumeIcon(volume.url) }
            volumes = mounted
            keepSidebarCursorOnARow()
            ejecting.subtract(gone)
            for id in gone { ejectFailures[id] = nil }
            forgetPathParts()
            // The tabs of a disk that went move to Home (spec §13).
            if !gone.isEmpty { repairGoneFolders() }
        }
    }

    /// Whether `url` is on a volume that is being ejected.
    func isBeingEjected(_ url: URL) -> Bool {
        guard !ejecting.isEmpty else { return false }
        let path = url.standardizedFileURL.path
        return ejecting.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// The eject button: a spinner while macOS works, the reason under the
    /// row when it refuses (gone on the next try). The app first lets go of
    /// the disk itself (the size walks on it and the watchers of the panes
    /// that show it), or it would be the one holding it; if the disk stays,
    /// they start again.
    func eject(_ volume: Volume) {
        guard live, volume.ejectable, !ejecting.contains(volume.id) else { return }
        // Not from under a copy: said under the row, by whichever way it
        // was asked (the button, the row's menu, ⌘E), and nothing is let go of.
        if let refusal = ejectRefusal(for: volume) {
            ejectRefused(volume, because: refusal)
            return
        }
        reach.refusedEjects.remove(volume.id)
        ejecting.insert(volume.id)
        ejectFailures[volume.id] = nil
        // `wantedSizes` leaves out what is on a disk being ejected.
        sizeQueue.keep(Set(wantedSizes()))
        let held = sides.filter { side in browser.tab(side).map { isBeingEjected($0.folder) } ?? false }
        for side in held {
            watchers[side]?.watcher.stop()
            watchers[side] = nil
        }
        let url = volume.url
        Task {
            let failure = await Task.detached { Volume.eject(url) }.value
            ejecting.remove(volume.id)
            guard let failure else { return }  // The unmount notification takes the row away.
            ejectFailures[volume.id] = failure
            // The disk stays: every pane not watching the folder it shows
            // (it was let go of, or went onto the disk meanwhile) watches
            // it and reads it again, for what changed while nobody looked.
            var shown: [Side: URL] = [:]
            for side in sides { shown[side] = browser.tab(side)?.folder }
            for side in WatchPlan.stale(watched: watchers.mapValues(\.path), shown: shown) {
                watchers[side]?.watcher.stop()
                watchers[side] = nil
                load(side)  // Watches the folder too.
            }
            wantSizes()
        }
    }

    // MARK: Favourites

    /// Takes a favourite out of the sidebar.
    func removeFavourite(id: String) {
        changeFavourites { $0.filter { $0.id != id } }
    }

    /// Folders dragged onto the sidebar: each becomes a favourite, at the
    /// end, unless it is one already.
    func addFavourites(_ folders: [URL]) {
        changeFavourites { Favourites.adding(folders, to: $0) }
    }

    /// Changes the favourites and writes the list to `explorer.local.toml`,
    /// the one config file the app writes. The list changed and written is
    /// made from the two files as they are now, every favourite in them:
    /// not from the window's own, which leaves out the folders that weren't
    /// there at launch (a disk not mounted) and knows nothing of what was
    /// added to the files since.
    private func changeFavourites(_ change: ([Favourite]) -> [Favourite]) {
        guard live else { return }
        let folder = home.appendingPathComponent(".config/grove-explorer", isDirectory: true)
        let local = folder.appendingPathComponent("explorer.local.toml")
        do {
            let tracked = try? String(contentsOf: folder.appendingPathComponent("explorer.toml"), encoding: .utf8)
            // A local file that is there and can't be read is not taken for no file.
            let existing = FileManager.default.fileExists(atPath: local.path)
                ? try String(contentsOf: local, encoding: .utf8) : nil
            let before = ExplorerConfig.allFavourites(tracked: tracked, local: existing, home: home)
            let after = change(before)
            guard after != before else { return }
            let text = try ExplorerConfig.localText(favourites: after, home: home, keeping: existing)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: local, options: .atomic)
            // The window's own list: without what went, with what is new.
            let kept = Set(after.map(\.id)), old = Set(before.map(\.id))
            config.favourites = config.favourites.filter { kept.contains($0.id) } + after.filter { !old.contains($0.id) }
            writeProblem = nil
        } catch let refused as ConfigWriteRefused {
            writeProblem = refused.description
        } catch {
            writeProblem = "explorer.local.toml could not be written, so the favourites were not saved: \(error.localizedDescription)"
        }
    }
}
