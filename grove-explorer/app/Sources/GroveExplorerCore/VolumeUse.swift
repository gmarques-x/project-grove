import Foundation

/// Whether a disk is in use by the window's own file commands: ejecting it
/// under a copy would fail the rest of the copy item by item.
public enum VolumeUse {
    /// A file command in hand or waiting, as far as a disk is concerned.
    public enum Command: Equatable, Sendable {
        case operation(Operation)
        /// What an undo or a redo will touch is the undo stack's to know.
        case undo, redo
    }

    /// Which device a path is on: the `st_dev` of what is there, links
    /// followed; nil when nothing is there or it can't be asked. Given to
    /// the functions below so that tests need no disk.
    public typealias DeviceLookup = (String) -> dev_t?

    /// `DeviceLookup` by `stat`.
    public static func device(at path: String) -> dev_t? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return info.st_dev
    }

    /// Whether `url` is on the volume attached at `volume`: the device of
    /// the place (of the nearest folder above it that is there, for a
    /// place that is not there yet; links followed) is the device of the
    /// volume's root. So a folder that is a link to the disk is on the
    /// disk, which its path alone doesn't say.
    ///
    /// When the root can't be asked, the path decides as it always did:
    /// the root or below it, by standardized path, on a whole path
    /// component ("/Volumes/Backup 2" is not on "/Volumes/Backup").
    public static func isOn(_ url: URL, volume: URL, device: DeviceLookup = VolumeUse.device(at:)) -> Bool {
        let path = url.standardizedFileURL.path
        var root = volume.standardizedFileURL.path
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        if let rootDevice = device(root), let placeDevice = nearestDevice(above: path, device) {
            return rootDevice == placeDevice
        }
        if root == "/" { return true }
        return path == root || path.hasPrefix(root + "/")
    }

    /// The device of what is at `path`, or of the nearest folder above it
    /// that is there; nil when not even "/" answers.
    private static func nearestDevice(above path: String, _ device: DeviceLookup) -> dev_t? {
        var path = path
        while true {
            if let found = device(path) { return found }
            let parent = (path as NSString).deletingLastPathComponent
            guard parent != path, !parent.isEmpty else { return nil }
            path = parent
        }
    }

    /// Whether the operation reads from or writes to the volume: any of
    /// its items, or the folder it goes to, is on it. An item is where it
    /// lies (the folder it is in), whatever it leads to: a link is copied
    /// and trashed as a link. One that leads to the volume from elsewhere
    /// counts too, which can only refuse more.
    public static func touches(
        _ operation: Operation, volume: URL, device: DeviceLookup = VolumeUse.device(at:)
    ) -> Bool {
        let items: [URL], folders: [URL]
        switch operation {
        case let .copy(moved, folder), let .move(moved, folder): (items, folders) = (moved, [folder])
        case let .duplicate(made), let .trash(made): (items, folders) = (made, [])
        case let .rename(item, _): (items, folders) = ([item], [])
        case let .newFolder(folder, _): (items, folders) = ([], [folder])
        }
        // The items of one command mostly lie in one folder: asked once.
        var known: [String: Bool] = [:]
        func isOnVolume(_ url: URL) -> Bool {
            let key = url.standardizedFileURL.path
            if let answer = known[key] { return answer }
            let answer = isOn(url, volume: volume, device: device)
            known[key] = answer
            return answer
        }
        return folders.contains(where: isOnVolume)
            || items.contains { isOnVolume($0.deletingLastPathComponent()) || isOnVolume($0) }
    }

    /// Why the volume called `name` is not ejected now, as a sentence for
    /// under its row; nil when it may be. `commands`: the one in hand,
    /// then those waiting. Refused while any of them touches the volume,
    /// and during an undo or a redo whatever it touches.
    public static func ejectRefusal(
        of name: String, at volume: URL, commands: [Command], device: DeviceLookup = VolumeUse.device(at:)
    ) -> String? {
        for command in commands {
            switch command {
            case .undo: return "\(name) can't be ejected during an undo: wait for it"
            case .redo: return "\(name) can't be ejected during a redo: wait for it"
            case let .operation(operation):
                if touches(operation, volume: volume, device: device) {
                    return "\(name) is in use by \(noun(operation)): wait for it or cancel it"
                }
            }
        }
        return nil
    }

    /// A volume whose eject is on its way: what it is called and its root.
    public struct Ejecting: Equatable, Sendable {
        public let name: String
        public let root: URL

        public init(name: String, root: URL) {
            self.name = name
            self.root = root
        }
    }

    /// The other way round: why `command` is not begun while the volumes
    /// in `ejecting` are being ejected, as a sentence for the status bar;
    /// nil when it may be. An operation is refused when it touches one of
    /// them (it would hold the disk, or fail item by item as it goes); an
    /// undo or a redo while any is, since what it touches is not known here.
    public static func commandRefusal(
        for command: Command, ejecting: [Ejecting], device: DeviceLookup = VolumeUse.device(at:)
    ) -> String? {
        switch command {
        case .undo: return ejecting.first.map { "\($0.name) is being ejected: undo when that is done" }
        case .redo: return ejecting.first.map { "\($0.name) is being ejected: redo when that is done" }
        case let .operation(operation):
            return ejecting.first { touches(operation, volume: $0.root, device: device) }
                .map { "\($0.name) is being ejected: wait for it, then try again" }
        }
    }

    private static func noun(_ operation: Operation) -> String {
        switch operation {
        case .copy: "a copy"
        case .move: "a move"
        case .duplicate: "a duplicate"
        case .rename: "a rename"
        case .newFolder: "a new folder"
        case .trash: "a move to the Trash"
        }
    }
}
