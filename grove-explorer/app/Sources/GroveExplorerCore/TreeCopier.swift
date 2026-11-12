import Foundation

/// Why a copy stopped.
enum CopyStop: Error, Equatable {
    case cancelled
    /// `inner` is the path inside the item of what failed, nil for the item
    /// itself; `code` is the system's error number.
    case failed(inner: String?, code: Int32)
    /// Another volume is attached at `inner`, a folder inside the item.
    case otherVolume(inner: String)
}

/// What is on the disk at a path, without following a link there.
struct FileIdentity: Equatable {
    var device: dev_t
    var number: ino_t

    static func of(_ path: String, followingLinks: Bool = false) -> (identity: FileIdentity, kind: mode_t)? {
        var code: Int32 = 0
        return of(path, followingLinks: followingLinks, code: &code)
    }

    /// With the system's error number in `code` when there is no answer.
    static func of(
        _ path: String, followingLinks: Bool = false, code: inout Int32
    ) -> (identity: FileIdentity, kind: mode_t)? {
        var info = stat()
        guard (followingLinks ? stat(path, &info) : lstat(path, &info)) == 0 else {
            code = errno
            return nil
        }
        return (FileIdentity(device: info.st_dev, number: info.st_ino), info.st_mode & S_IFMT)
    }
}

/// The work on files under a copy: writing an item, with all that is in it,
/// to a new path; telling whether such a copy is whole; removing the source
/// of a move once it is; and removing the app's own half-written copies.
///
/// A link is copied as a link, never followed. Dates, permissions, flags,
/// extended attributes (tags are one) and access lists are kept, by
/// `copyfile`. On one volume a file is cloned, which takes no room and no time.
///
/// An item is what is on its own volume: a folder inside it where another
/// volume is attached is not gone into, and stops the copy.
///
/// On a volume that can't hold extended attributes (ExFAT, FAT), macOS
/// keeps a file's in a second file beside it, `._name`, which it makes,
/// overwrites and removes with the file. Such a file (told by how its
/// contents begin, not by its name) is not an item: it is not copied,
/// counted or removed here; the attributes go with the file itself. Any
/// other file named `._name` is an item like any other. Because macOS
/// would overwrite it, a `._name` can't be kept beside a `name` on such a
/// volume: copied there, it is left out and told (`leftOut`).
final class TreeCopier {
    /// What a half-written copy has in its name. Only paths with it are
    /// ever removed by `removeTemporary`.
    static let partialMark = ".grove-partial-"

    /// A file as it was when it was copied.
    private struct Stamp: Equatable {
        var size: off_t
        var seconds: Int
        var nanoseconds: Int

        init(_ info: stat) {
            size = info.st_size
            seconds = info.st_mtimespec.tv_sec
            nanoseconds = info.st_mtimespec.tv_nsec
        }
    }

    private let flag: CancelFlag
    private let reporter: Reporter
    private let watching: (@Sendable (OperationRunner.Stage) -> Void)?
    /// The files of the copy last made with `remembering`, by source path.
    private var stamps: [String: Stamp] = [:]
    /// Whether a volume keeps attributes in `._name` files, by its number.
    private var besideFiles: [dev_t: Bool] = [:]
    /// What the last copy left out, as paths inside the item: each a
    /// `._name` that can't be kept beside its `name` on the target volume.
    private(set) var leftOut: [String] = []

    init(flag: CancelFlag, reporter: Reporter, watching: (@Sendable (OperationRunner.Stage) -> Void)?) {
        self.flag = flag
        self.reporter = reporter
        self.watching = watching
    }

    // MARK: Copying

    /// Copies the item at `source` to `destination`, a path where nothing
    /// is. A cancel is seen between two files, not inside one. Whatever
    /// stops it, what was written so far is still at `destination`: the
    /// caller removes it.
    ///
    /// With `remembering`, each file's length and modification time as they
    /// were when it was copied are kept, for `isWhole` and `removeSource`.
    ///
    /// Afterwards `leftOut` tells what of the item could not go to the
    /// target volume; the rest is copied.
    func copy(_ source: String, to destination: String, remembering: Bool = false) throws(CopyStop) {
        stamps = [:]
        leftOut = []
        var info = stat()
        guard lstat(source, &info) == 0 else { throw .failed(inner: nil, code: errno) }
        let pairs = keepsAttributesBesideFiles(at: (destination as NSString).deletingLastPathComponent)
        try copy(
            source, to: destination, inner: nil, on: info.st_dev, remembering: remembering, withoutPairs: pairs)
    }

    private func copy(
        _ source: String, to destination: String, inner: String?, on volume: dev_t, remembering: Bool,
        withoutPairs: Bool
    ) throws(CopyStop) {
        if flag.isCancelled { throw .cancelled }
        var info = stat()
        guard lstat(source, &info) == 0 else { throw .failed(inner: inner, code: errno) }
        guard info.st_dev == volume else { throw .otherVolume(inner: inner ?? "") }

        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            guard var names = items(in: source) else { throw .failed(inner: inner, code: errno) }
            if withoutPairs {
                // Before anything of the folder is written, and whatever
                // the order of its names: a `._name` with its `name` can't
                // both be kept there, so it is the one left out.
                let all = Set(names)
                let pairs = names.filter { Self.isBeside($0, in: all) }
                leftOut += pairs.map { name in inner.map { $0 + "/" + name } ?? name }
                names.removeAll { pairs.contains($0) }
            }
            guard mkdir(destination, 0o700) == 0 else { throw .failed(inner: inner, code: errno) }
            for name in names {
                try copy(
                    source + "/" + name, to: destination + "/" + name,
                    inner: inner.map { $0 + "/" + name } ?? name, on: volume, remembering: remembering,
                    withoutPairs: withoutPairs)
            }
            // Last: its date would change with every item put in it, and a
            // folder that can't be written to could not be filled.
            guard copyfile(source, destination, nil, Self.metadata) == 0 else {
                throw .failed(inner: inner, code: errno)
            }

        case S_IFLNK:
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
            let length = readlink(source, &buffer, Int(PATH_MAX))
            guard length >= 0 else { throw .failed(inner: inner, code: errno) }
            buffer[length] = 0
            guard symlink(buffer, destination) == 0 else { throw .failed(inner: inner, code: errno) }
            guard copyfile(source, destination, nil, Self.metadata) == 0 else {
                throw .failed(inner: inner, code: errno)
            }
            watching?(.fileCopied(source))

        case S_IFREG:
            if remembering { stamps[source] = Stamp(info) }
            let state = copyfile_state_alloc()
            defer { copyfile_state_free(state) }
            copyfile_state_set(
                state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(Self.dataCopied, to: UnsafeRawPointer.self))
            copyfile_state_set(
                state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(reporter).toOpaque())
            guard copyfile(source, destination, state, Self.everything) == 0 else {
                throw .failed(inner: inner, code: errno)
            }
            reporter.fileFinished(bytes: Int64(info.st_size))
            watching?(.fileCopied(source))

        default:
            // A pipe, a socket, a device: nothing a copy can be made of.
            throw .failed(inner: inner, code: EFTYPE)
        }
    }

    /// Dates, permissions, flags, extended attributes and the access list,
    /// of the item itself when it is a link.
    private static let metadata = copyfile_flags_t(
        COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_NOFOLLOW)

    /// The data too. A clone where the volume can make one (that implies:
    /// never onto something that exists, never through a link); a plain
    /// copy otherwise.
    private static let everything = copyfile_flags_t(
        COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_DATA | COPYFILE_NOFOLLOW
            | COPYFILE_EXCL | COPYFILE_CLONE)

    /// `copyfile` tells how far a file's data is. A clone tells nothing: it
    /// is done at once. An error ends the copy: told to continue, `copyfile`
    /// would try the same write again without end (on a full disk, for one).
    private static let dataCopied: copyfile_callback_t = { what, stage, state, _, _, context in
        if stage == COPYFILE_ERR { return COPYFILE_QUIT }
        if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let context {
            var copied: off_t = 0
            if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                Unmanaged<Reporter>.fromOpaque(context).takeUnretainedValue().fileProgress(bytes: Int64(copied))
            }
        }
        return COPYFILE_CONTINUE
    }

    // MARK: Measuring and listing

    /// The lengths of all the files at and under `path`, on its volume.
    /// What can't be read counts nothing here; the copy will say so.
    func size(of path: String) -> Int64 {
        var info = stat()
        guard lstat(path, &info) == 0 else { return 0 }
        return size(of: path, on: info.st_dev)
    }

    private func size(of path: String, on volume: dev_t) -> Int64 {
        guard !flag.isCancelled else { return 0 }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_dev == volume else { return 0 }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            return Int64(info.st_size)
        case S_IFDIR:
            return (items(in: path) ?? []).reduce(0) { $0 + size(of: path + "/" + $1, on: volume) }
        default:
            return 0
        }
    }

    /// The names in a folder, nil (with `errno` set) when it can't be read,
    /// or not to its end: a list cut short must not pass for the whole.
    static func names(in folder: String) -> [String]? {
        guard let directory = opendir(folder) else { return nil }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else { break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name != ".", name != ".." { names.append(name) }
        }
        let code = errno
        closedir(directory)
        errno = code
        return code == 0 ? names : nil
    }

    /// The items of a folder: its names, less the attribute files macOS
    /// keeps there on a volume without attributes of its own: a `._name`
    /// beside a `name` whose contents begin as such a file's do. Nil as `names`.
    func items(in folder: String) -> [String]? {
        guard let names = Self.names(in: folder) else { return nil }
        guard names.contains(where: { $0.hasPrefix("._") }), keepsAttributesBesideFiles(at: folder) else {
            return names
        }
        let all = Set(names)
        return names.filter { !(Self.isBeside($0, in: all) && Self.isAttributeFile(folder + "/" + $0)) }
    }

    /// Whether `name` is a `._x` with its `x` among `names`.
    static func isBeside(_ name: String, in names: Set<String>) -> Bool {
        name.hasPrefix("._") && names.contains(String(name.dropFirst(2)))
    }

    /// Whether the file begins as the attribute files macOS writes do (the
    /// AppleDouble format: 00 05 16 07). A file that can't be read is not one.
    static func isAttributeFile(_ path: String) -> Bool {
        let file = open(path, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { return false }
        defer { close(file) }
        var start = [UInt8](repeating: 0, count: 4)
        return read(file, &start, 4) == 4 && start == [0x00, 0x05, 0x16, 0x07]
    }

    /// `keepsAttributesBesideFiles` for the volume of the folder at `path`,
    /// asked once per volume.
    func keepsAttributesBesideFiles(at path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        if let known = besideFiles[info.st_dev] { return known }
        let beside = Self.keepsAttributesBesideFiles(path)
        besideFiles[info.st_dev] = beside
        return beside
    }

    /// Whether the volume `path` is on has no extended attributes of its
    /// own, by what the volume says of itself. Not known counts as no.
    static func keepsAttributesBesideFiles(_ path: String) -> Bool {
        struct Answer {
            var length: UInt32 = 0
            var capabilities = vol_capabilities_attr_t()
        }
        var asked = attrlist()
        asked.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        // ATTR_VOL_INFO, which every question about a volume carries, and the capabilities.
        asked.volattr = 0x8000_0000 | attrgroup_t(ATTR_VOL_CAPABILITIES)
        var answer = Answer()
        guard getattrlist(path, &asked, &answer, MemoryLayout<Answer>.size, 0) == 0 else { return false }
        let bit = UInt32(VOL_CAP_INT_EXTENDED_ATTR)
        // The second word is the interfaces.
        return answer.capabilities.valid.1 & bit != 0 && answer.capabilities.capabilities.1 & bit == 0
    }

    // MARK: The source of a move to another volume

    /// Whether what is at `copy` is the same item as at `source`, looked at
    /// by themselves and not at what is in them: each on the volume its
    /// tree is on; the same kind; a file of the same length, and the source
    /// with the very length and modification time it had when it was
    /// copied (so a source written to since doesn't pass, whatever the
    /// target volume does to times); a link with the same destination.
    private func matches(_ copy: String, _ source: String, on volumes: (copy: dev_t, source: dev_t)) -> Bool {
        var theCopy = stat()
        var theSource = stat()
        guard lstat(copy, &theCopy) == 0, lstat(source, &theSource) == 0,
            theCopy.st_dev == volumes.copy, theSource.st_dev == volumes.source,
            theCopy.st_mode & S_IFMT == theSource.st_mode & S_IFMT
        else { return false }
        switch theSource.st_mode & S_IFMT {
        case S_IFREG:
            return theCopy.st_size == theSource.st_size && stamps[source] == Stamp(theSource)
        case S_IFLNK:
            let files = FileManager.default
            guard let one = try? files.destinationOfSymbolicLink(atPath: copy),
                let other = try? files.destinationOfSymbolicLink(atPath: source)
            else { return false }
            return one == other
        case S_IFDIR:
            return true
        default:
            return false
        }
    }

    private static func volumes(_ copy: String, _ source: String) -> (copy: dev_t, source: dev_t)? {
        guard let theCopy = FileIdentity.of(copy), let theSource = FileIdentity.of(source) else { return nil }
        return (theCopy.identity.device, theSource.identity.device)
    }

    /// Whether `copy`, made by the last `copy(_:to:remembering:)` of
    /// `source`, has all of it: every item of the source, at every depth,
    /// is in the copy under its name and matches (see `matches`), and no
    /// folder of the copy holds another number of items than the source's.
    /// Contents are not read again.
    func isWhole(_ copy: String, of source: String) -> Bool {
        guard let volumes = Self.volumes(copy, source) else { return false }
        return isWhole(copy, of: source, on: volumes)
    }

    private func isWhole(_ copy: String, of source: String, on volumes: (copy: dev_t, source: dev_t)) -> Bool {
        guard matches(copy, source, on: volumes) else { return false }
        guard let (_, kind) = FileIdentity.of(source), kind == S_IFDIR else { return true }
        guard let names = items(in: source), let copied = items(in: copy), names.count == copied.count
        else { return false }
        return names.allSatisfy { isWhole(copy + "/" + $0, of: source + "/" + $0, on: volumes) }
    }

    /// Removes the source of a move whose copy is whole: each file and link
    /// is looked at once more against its copy just before it goes, and a
    /// folder is removed only by `rmdir`. So what was changed in the source
    /// since the copy was made is never removed, and what was added to it
    /// stays, with the folders it is in; the answer is then false.
    ///
    /// On a volume that keeps attributes in `._name` files, macOS removes a
    /// `._name` with its `name`, and with the folder when only such files
    /// are left in it, whatever is in them. So there a `._name` goes before
    /// any other item of its folder, when it has been looked at itself; but
    /// one that is added after the folder was listed goes with the folder,
    /// unseen.
    func removeSource(_ source: String, copiedTo copy: String) -> Bool {
        guard let volumes = Self.volumes(copy, source) else { return false }
        // A `._name` beside the item itself that is not its attribute file
        // would go with it, and it is not part of what was copied.
        let folder = (source as NSString).deletingLastPathComponent
        let beside = folder + "/._" + (source as NSString).lastPathComponent
        if keepsAttributesBesideFiles(at: folder), FileIdentity.of(beside) != nil, !Self.isAttributeFile(beside) {
            return false
        }
        return removeSource(source, copiedTo: copy, on: volumes)
    }

    private func removeSource(
        _ source: String, copiedTo copy: String, on volumes: (copy: dev_t, source: dev_t)
    ) -> Bool {
        var code: Int32 = 0
        guard let (_, kind) = FileIdentity.of(source, code: &code) else {
            // Gone already: there is nothing left of it to remove.
            return code == ENOENT
        }
        guard matches(copy, source, on: volumes) else { return false }
        guard kind == S_IFDIR else { return unlink(source) == 0 }
        guard let names = items(in: source) else { return false }
        // Any `._name` first: see above.
        let ordered = names.filter { $0.hasPrefix("._") } + names.filter { !$0.hasPrefix("._") }
        for name in ordered {
            guard removeSource(source + "/" + name, copiedTo: copy + "/" + name, on: volumes) else { return false }
        }
        return rmdir(source) == 0
    }

    // MARK: The app's own half-written copies

    /// Removes a half-written copy. Nothing happens for a path whose name
    /// doesn't carry the mark of one.
    static func removeTemporary(_ path: String) {
        guard (path as NSString).lastPathComponent.contains(partialMark) else { return }
        remove(path)
    }

    /// Of a half-written copy only: see `removeTemporary`.
    private static func remove(_ path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        // A copy carries its source's flags and permissions: a locked file
        // or a read-only folder would otherwise stay.
        if info.st_flags != 0 { lchflags(path, 0) }
        if info.st_mode & S_IFMT == S_IFDIR {
            chmod(path, 0o700)
            for name in names(in: path) ?? [] { remove(path + "/" + name) }
            rmdir(path)
        } else {
            unlink(path)
        }
    }
}
