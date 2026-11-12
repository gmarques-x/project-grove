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

    /// ⌥⌘←: the keyboard goes to the sidebar, on the lit row.
    func focusSidebar() {
        if sidebarHidden { sidebarHidden = false }
        let places = places
        sidebarCursor = litPlace(among: places) ?? 0
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
        hasCloud = Disk.isFolder(home.appendingPathComponent(Self.cloudFolder, isDirectory: true))
        mounts = MountObserver { [weak self] in self?.readVolumes() }
        readVolumes()
    }

    private func readVolumes() {
        Task {
            let mounted = await Task.detached { Volume.mounted() }.value
            guard mounted != volumes else { return }
            let gone = Set(volumes.map(\.id)).subtracting(mounted.map(\.id))
            // The icons are asked for here, not while a row is drawn.
            IconCache.shared.forgetVolumes()
            for volume in mounted { _ = IconCache.shared.volumeIcon(volume.url) }
            volumes = mounted
            ejecting.subtract(gone)
            for id in gone { ejectFailures[id] = nil }
            forgetPathParts()
            // The tabs of a disk that went move to Home (spec §13).
            if !gone.isEmpty { repairGoneFolders() }
        }
    }

    /// The eject button: a spinner while macOS works, the reason under the
    /// row when it refuses (gone on the next try).
    func eject(_ volume: Volume) {
        guard live, volume.ejectable, !ejecting.contains(volume.id) else { return }
        ejecting.insert(volume.id)
        ejectFailures[volume.id] = nil
        let url = volume.url
        Task {
            let failure = await Task.detached { Volume.eject(url) }.value
            ejecting.remove(volume.id)
            if let failure { ejectFailures[volume.id] = failure }
            // On success the unmount notification takes the row away.
        }
    }

    // MARK: Favourites

    /// Takes a favourite out of the sidebar and writes the list to
    /// `explorer.local.toml`, the one config file the app writes.
    func removeFavourite(id: String) {
        saveFavourites(config.favourites.filter { $0.id != id })
    }

    /// Keeps `favourites` in `explorer.local.toml`, beside whatever else the
    /// file holds, in one step. A file that can't be read as it is is left
    /// alone: the banner says why, and the sidebar stays as it was.
    func saveFavourites(_ favourites: [Favourite]) {
        guard live else { return }
        let file = home.appendingPathComponent(".config/grove-explorer/explorer.local.toml")
        do {
            let existing: String?
            if FileManager.default.fileExists(atPath: file.path) {
                existing = try String(contentsOf: file, encoding: .utf8)
            } else {
                existing = nil
            }
            let text = try ExplorerConfig.localText(favourites: favourites, home: home, keeping: existing)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
            config.favourites = favourites
            writeProblem = nil
        } catch let refused as ConfigWriteRefused {
            writeProblem = refused.description
        } catch {
            writeProblem = "explorer.local.toml could not be written, so the favourites were not saved: \(error.localizedDescription)"
        }
    }
}
