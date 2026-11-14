import Foundation

/// How giving an item its final name went.
private enum Placed {
    case at(URL)
    /// The name is taken.
    case taken
    /// The name is on another volume than the item.
    case otherVolume
    /// A file of the user's named `._<name>` is at the target (its name is
    /// carried), on a volume where macOS would overwrite it.
    case inTheWay(String)
    case failed(Int32)
}

/// One run of one operation, on the thread it was started on.
final class Worker {
    private let operation: Operation
    /// The targets that were there when the names were looked up, less the
    /// ones already asked about: an answer is for one item.
    private var known: Set<String>
    /// The answers given, by target.
    private var answered: [String: Conflict.Choice] = [:]
    private let files: FileManager
    /// Asked to put an item of `home`'s cloud folders in the Trash when
    /// `files` is refused it for want of permission.
    private let finder: (any FinderTrash)?
    private let home: URL
    private let flag: CancelFlag
    private let watching: (@Sendable (OperationRunner.Stage) -> Void)?
    private let resolve: (URL) -> Conflict.Choice
    private let reporter: Reporter
    private let copier: TreeCopier

    private var changes: [Change] = []
    private var failures: [ItemFailure] = []
    private var done = 0
    private var skipped = 0
    private var cancelled = false
    private var shortage: Shortage?

    init(
        operation: Operation, known: Set<String>, files: FileManager, finder: (any FinderTrash)?, home: URL,
        flag: CancelFlag, watching: (@Sendable (OperationRunner.Stage) -> Void)?,
        resolve: @escaping (URL) -> Conflict.Choice, progress: @escaping (Progress) -> Void
    ) {
        self.operation = operation
        self.known = known
        self.files = files
        self.finder = finder
        self.home = home
        self.flag = flag
        self.watching = watching
        self.resolve = resolve
        reporter = Reporter(send: progress, watching: watching)
        copier = TreeCopier(flag: flag, reporter: reporter, watching: watching)
    }

    func run() -> Outcome {
        switch operation {
        case let .copy(items, folder): transfer(items, to: folder, moving: false)
        case let .move(items, folder): transfer(items, to: folder, moving: true)
        case let .duplicate(items): duplicate(items)
        case let .rename(item, name): rename(item, to: name)
        case let .newFolder(folder, name): makeFolder(in: folder, name: name)
        case let .trash(items): trash(items)
        }
        reporter.finish()
        return Outcome(
            changes: changes, failures: failures, cancelled: cancelled,
            summary: Wording.summary(
                of: operation, done: done, skipped: skipped, failed: failures.count,
                cancelled: cancelled, shortage: shortage))
    }

    // MARK: Putting back, for Undo

    /// Moves `item` to exactly `place`: the folder and the name it had
    /// before (out of the Trash, or back from where it was moved to). It is
    /// a move like any other, to another volume too, but under the name
    /// given, and with nobody to ask: a name that is taken fails it.
    /// Made with a move of `item` as the operation and nothing `known`.
    func put(at place: URL) -> Outcome {
        guard case let .move(items, folder) = operation, let item = items.first else {
            preconditionFailure("put(at:) is for a worker made for one move")
        }
        reporter.begin(bytes: nil, items: 1)
        if let (identity, kind) = FileIdentity.of(folder.path, followingLinks: true), kind == S_IFDIR {
            if let partner = pairedName(of: place, among: [], in: folder) {
                fail(item, Self.cannotBeBeside(partner))
            } else {
                transfer(item, to: folder, on: identity.device, moving: true, named: place.lastPathComponent)
            }
        } else {
            fail(item, "the folder “\(folder.lastPathComponent)” is not there")
        }
        reporter.itemFinished(bytes: 0)
        reporter.finish()
        return Outcome(
            changes: changes, failures: failures, cancelled: cancelled,
            summary: Wording.summary(
                of: operation, done: done, skipped: skipped, failed: failures.count,
                cancelled: cancelled, shortage: shortage))
    }

    // MARK: Copy and move

    private func transfer(_ items: [URL], to folder: URL, moving: Bool) {
        // The volume the target folder is on; nil when there is no such folder.
        var volume: dev_t?
        if let (identity, kind) = FileIdentity.of(folder.path, followingLinks: true), kind == S_IFDIR {
            volume = identity.device
        }
        // Bytes are copied for a copy, and for a move to another volume.
        let sizes = items.map { item -> Int64 in
            guard let volume else { return 0 }
            if moving, FileIdentity.of(item.path)?.identity.device == volume { return 0 }
            return copier.size(of: item.path)
        }
        let bytes = sizes.reduce(0, +)
        reporter.begin(bytes: bytes > 0 ? bytes : nil, items: items.count)

        for (item, size) in zip(items, sizes) {
            if flag.isCancelled {
                cancelled = true
                break
            }
            if volume != nil, let partner = pairedName(of: item, among: items, in: folder) {
                fail(item, Self.cannotBeBeside(partner))
            } else if let volume {
                transfer(item, to: folder, on: volume, moving: moving)
            } else {
                fail(item, "the folder “\(folder.lastPathComponent)” is not there")
            }
            if cancelled || shortage != nil { break }
            reporter.itemFinished(bytes: size)
        }
    }

    /// For an item named `._x` going to a volume that keeps attributes in
    /// files of that name: the `x` it would be beside there, in this
    /// operation or in the folder already. macOS would overwrite it with
    /// `x`'s attributes, or has its own file under the name.
    private func pairedName(of item: URL, among items: [URL], in folder: URL) -> String? {
        let name = item.lastPathComponent
        guard name.hasPrefix("._"), copier.keepsAttributesBesideFiles(at: folder.path) else { return nil }
        let partner = String(name.dropFirst(2))
        // Such volumes take "X.TXT" for "x.txt": so does this.
        let coming = items.contains { OperationRunner.isSameName($0.lastPathComponent, partner) }
        return coming || OperationRunner.exists(folder.appendingPathComponent(partner)) ? partner : nil
    }

    private static func cannotBeBeside(_ partner: String) -> String {
        "it can't be kept beside “\(partner)” on this disk"
    }

    /// Tells what the last copy left out of `item`, each as a failure of
    /// its own. Whether there was anything.
    private func tellLeftOut(of item: URL) -> Bool {
        for inner in copier.leftOut {
            let partner = String((inner as NSString).lastPathComponent.dropFirst(2))
            fail(item.appendingPathComponent(inner), Self.cannotBeBeside(partner))
        }
        return !copier.leftOut.isEmpty
    }

    private func transfer(
        _ item: URL, to folder: URL, on volume: dev_t, moving: Bool, named name: String? = nil
    ) {
        var code: Int32 = 0
        guard let (source, kind) = FileIdentity.of(item.path, code: &code) else {
            fail(item, code: code)
            return
        }
        var target = OperationRunner.target(for: item, in: folder, named: name)
        var replacing = false
        var nextFree: (() -> URL?)?

        if OperationRunner.exists(target) {
            // Not there when the names were looked up: nobody was asked
            // about it, so no answer is about it.
            // And asked about once: a second item of the same name finds
            // the first one's arrival there, which nobody was asked about.
            let key = OperationRunner.key(target)
            guard known.remove(key) != nil else {
                // Asked about already, for an earlier item of this name:
                // skipped as that one was, or failed with what is true.
                switch answered[key] {
                case .skip?: skipped += 1
                case .replace?, .keepBoth?:
                    fail(item, "another item of this operation has that name, and the answer was for it")
                case nil: fail(item, Self.appeared)
                }
                return
            }
            let choice = resolve(target)
            answered[key] = choice
            switch choice {
            case .skip:
                skipped += 1
                return
            case .keepBoth:
                let taken = target
                let next = { Self.freeName(beside: taken, folder: kind == S_IFDIR) }
                guard let free = next() else {
                    fail(item, "no free name was found for it")
                    return
                }
                target = free
                nextFree = next
            case .replace:
                // Either would send the item itself to the Trash.
                guard FileIdentity.of(target.path)?.identity != source else {
                    fail(item, "it can't replace itself")
                    return
                }
                guard !OperationRunner.isInside(item.deletingLastPathComponent(), of: target) else {
                    fail(item, "it is inside the item it would replace")
                    return
                }
                replacing = true
            }
        }

        // Before anything is written.
        if let name = fileInTheWay(of: target) {
            fail(item, Self.inTheWay(name))
            return
        }

        // Where the replaced item is in the Trash, once it is there.
        var replaced: URL?

        // On one volume a move is one rename.
        if moving, source.device == volume {
            if replacing {
                // The old one goes to the Trash before the rename: first
                // what would make the rename fail is looked for, so that it
                // doesn't go for nothing.
                if let reason = Self.whyNotMovable(item, to: folder) {
                    fail(item, reason)
                    return
                }
                guard let inTrash = moveToTrash(target, for: item) else { return }
                replaced = inTrash
            }
            switch place(item.path, at: target, orAt: nextFree) {
            case let .at(final):
                if let replaced { changes.append(.replaced(original: target, inTrash: replaced)) }
                changes.append(.moved(from: item, to: final))
                done += 1
                return
            case .otherVolume:
                break  // Not one volume after all: copied, below.
            case let other:
                fail(item, placed: other, puttingBack: replaced, at: target)
                return
            }
        }

        // Copied whole under a partial name; only then is the old one put
        // in the Trash, and the copy given its name.
        guard let partial = copyToPartial(item, for: target, on: folder, remembering: moving) else {
            if let replaced, !putBack(replaced, at: target) {
                changes.append(.trashed(original: target, inTrash: replaced))
            }
            return
        }
        if replacing, replaced == nil {
            guard let inTrash = moveToTrash(target, for: item) else {
                TreeCopier.removeTemporary(partial.path)
                return
            }
            replaced = inTrash
        }
        switch place(partial.path, at: target, orAt: nextFree) {
        case let .at(final):
            if let replaced { changes.append(.replaced(original: target, inTrash: replaced)) }
            let leftOut = tellLeftOut(of: item)
            guard moving else {
                changes.append(.created(final))
                done += 1
                return
            }
            // The source goes only when the copy is all of it.
            if leftOut {
                changes.append(.created(final))
                fail(item, "it was copied without what can't be kept on this disk, and left where it is")
            } else if !copier.isWhole(final.path, of: item.path) {
                changes.append(.created(final))
                fail(item, "it changed while it was copied: the copy is there, and it was left where it is")
            } else if !copier.removeSource(item.path, copiedTo: final.path) {
                changes.append(.created(final))
                fail(item, "it was copied, but could not be removed from where it was")
            } else {
                changes.append(.moved(from: item, to: final))
                done += 1
            }
        case let other:
            TreeCopier.removeTemporary(partial.path)
            fail(item, placed: other, puttingBack: replaced, at: target)
        }
    }

    /// What would make moving `item` into `folder` fail, as far as it can
    /// be told beforehand; nil when nothing is seen.
    private static func whyNotMovable(_ item: URL, to folder: URL) -> String? {
        var info = stat()
        guard lstat(item.path, &info) == 0 else { return reason(errno) }
        let locks = UInt32(UF_IMMUTABLE | UF_APPEND | SF_IMMUTABLE | SF_APPEND)
        if info.st_flags & locks != 0 { return "it is locked" }
        let from = item.deletingLastPathComponent().path
        guard access(from, W_OK) == 0, access(folder.path, W_OK) == 0 else { return reason(EACCES) }
        // A folder is written to when it moves: its ".." changes.
        if info.st_mode & S_IFMT == S_IFDIR, access(item.path, W_OK) != 0 { return reason(EACCES) }
        return nil
    }

    /// Gives the replaced item, in the Trash at `inTrash`, its name back,
    /// when the item that was to replace it didn't come. Never in place of
    /// another item: when the name is taken meanwhile, it stays in the Trash.
    private func putBack(_ inTrash: URL, at target: URL) -> Bool {
        if case .at = place(inTrash.path, at: target, orAt: nil) { return true }
        return false
    }

    // MARK: Duplicate

    private func duplicate(_ items: [URL]) {
        let sizes = items.map { copier.size(of: $0.path) }
        let bytes = sizes.reduce(0, +)
        reporter.begin(bytes: bytes > 0 ? bytes : nil, items: items.count)

        for (item, size) in zip(items, sizes) {
            if flag.isCancelled {
                cancelled = true
                break
            }
            duplicate(item)
            if cancelled || shortage != nil { break }
            reporter.itemFinished(bytes: size)
        }
    }

    private func duplicate(_ item: URL) {
        var code: Int32 = 0
        guard let (_, kind) = FileIdentity.of(item.path, code: &code) else {
            fail(item, code: code)
            return
        }
        let next = { Self.duplicateName(beside: item, folder: kind == S_IFDIR) }
        guard let target = next() else {
            fail(item, "no free name was found for it")
            return
        }
        if let name = fileInTheWay(of: target) {
            fail(item, Self.inTheWay(name))
            return
        }
        guard let partial = copyToPartial(item, for: target, on: item.deletingLastPathComponent()) else { return }
        switch place(partial.path, at: target, orAt: next) {
        case let .at(final):
            _ = tellLeftOut(of: item)
            changes.append(.created(final))
            done += 1
        case let other:
            TreeCopier.removeTemporary(partial.path)
            fail(item, placed: other)
        }
    }

    // MARK: Rename, new folder, trash

    private func rename(_ item: URL, to name: String) {
        reporter.begin(bytes: nil, items: 1)
        defer { reporter.itemFinished(bytes: 0) }
        var code: Int32 = 0
        guard let (source, _) = FileIdentity.of(item.path, code: &code) else {
            fail(item, code: code)
            return
        }
        let target = OperationRunner.target(for: item, in: item.deletingLastPathComponent(), named: name)
        // Its own name in other capitals is not another item.
        if let there = FileIdentity.of(target.path)?.identity,
            !(there == source && OperationRunner.isSameName(item.lastPathComponent, name))
        {
            fail(item, Self.alreadyThere(name))
            return
        }
        switch place(item.path, at: target, orAt: nil) {
        case let .at(final):
            changes.append(.moved(from: item, to: final))
            done += 1
        case let other:
            fail(item, placed: other)
        }
    }

    private func makeFolder(in folder: URL, name: String) {
        reporter.begin(bytes: nil, items: 1)
        defer { reporter.itemFinished(bytes: 0) }
        let target = folder.appendingPathComponent(name, isDirectory: true)
        if let name = fileInTheWay(of: target) {
            fail(target, Self.inTheWay(name))
            return
        }
        // `mkdir` makes it or fails: it never touches what has the name.
        let code = mkdir(target.path, 0o777) == 0 ? 0 : errno
        switch code {
        case 0:
            changes.append(.created(target))
            done += 1
        case EEXIST: fail(target, Self.alreadyThere(name))
        case ENOENT: fail(target, "the folder “\(folder.lastPathComponent)” is not there")
        default: fail(target, code: code)
        }
    }

    private func trash(_ items: [URL]) {
        reporter.begin(bytes: nil, items: items.count)
        for item in items {
            if flag.isCancelled {
                cancelled = true
                break
            }
            if let inTrash = moveToTrash(item, for: item) {
                changes.append(.trashed(original: item, inTrash: inTrash))
                done += 1
            }
            reporter.itemFinished(bytes: 0)
        }
    }

    // MARK: The steps

    /// Copies `item`, whole, to a partial name beside `target`. Nil when
    /// that stopped: the partial copy is removed, and why is recorded (a
    /// cancel, a full disk, or the item's failure).
    private func copyToPartial(_ item: URL, for target: URL, on folder: URL, remembering: Bool = false) -> URL? {
        let partial = Self.partial(for: target)
        do throws(CopyStop) {
            try copier.copy(item.path, to: partial.path, remembering: remembering)
            return partial
        } catch {
            TreeCopier.removeTemporary(partial.path)
            reporter.itemAbandoned()
            switch error {
            case .cancelled:
                cancelled = true
            case let .failed(inner, code):
                if code == ENOSPC || code == EDQUOT { shortage = Self.shortage(on: folder, needing: reporter.bytesLeft) }
                let reason = Self.reason(code)
                fail(item, inner.map { "“\($0)” in it: \(reason)" } ?? reason)
            case let .otherVolume(inner):
                fail(item, "“\(inner)” in it is another disk, attached there")
            }
            return nil
        }
    }

    /// On a volume that keeps attributes in `._name` files, macOS writes
    /// that file the moment a `name` is made, renamed or copied there, over
    /// whatever has the name. So where nothing is at `target` yet but a
    /// file of the user's is at `._<target's name>` (not an attribute
    /// file, by how it begins), the target's name can't be given: that
    /// file's name is returned. (With an item at `target`, the `._` file
    /// is that item's and goes where it goes: macOS carries it along.)
    private func fileInTheWay(of target: URL) -> String? {
        let folder = target.deletingLastPathComponent()
        guard copier.keepsAttributesBesideFiles(at: folder.path), !OperationRunner.exists(target) else { return nil }
        let name = "._" + target.lastPathComponent
        let path = folder.appendingPathComponent(name, isDirectory: false).path
        return FileIdentity.of(path) != nil && !TreeCopier.isAttributeFile(path) ? name : nil
    }

    private static func inTheWay(_ name: String) -> String {
        "“\(name)” is in the way on this disk"
    }

    /// Gives the item at `path` its final name, never in place of another
    /// item. When the name is taken and `next` is given (a name that only
    /// has to be free: a duplicate, "keep both"), the next free name is tried.
    private func place(_ path: String, at target: URL, orAt next: (() -> URL?)?) -> Placed {
        var target = target
        for _ in 0..<100 {
            watching?(.placing(target))
            if let name = fileInTheWay(of: target) { return .inTheWay(name) }
            var code = renamex_np(path, target.path, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            // ExFAT and FAT have no such rename.
            if code == ENOTSUP { code = placeOverPlaceholder(path, at: target) }
            switch code {
            case 0: return .at(target)
            case EEXIST, ENOTEMPTY:
                guard let free = next?() else { return .taken }
                target = free
            case EXDEV: return .otherVolume
            default: return .failed(code)
            }
        }
        return .taken
    }

    /// `place` on a volume whose rename can't refuse to replace: the name
    /// is first taken by an empty item of the app's own, made by a call
    /// that fails when the name exists (`open` with `O_EXCL`, `mkdir`);
    /// then the item is renamed over that. An item that is there is so
    /// never replaced. What is not excluded: another program writing into
    /// the empty placeholder in the instant between the last look at it and
    /// the rename; that write would be lost. Returns 0 or the error number.
    private func placeOverPlaceholder(_ path: String, at target: URL) -> Int32 {
        let name = target.path
        var code: Int32 = 0
        guard let (item, kind) = FileIdentity.of(path, code: &code) else { return code }
        if let there = FileIdentity.of(name)?.identity {
            // The item's own name in other capitals is one entry of the
            // folder, the item's: nothing else can be under it.
            // That it is the item's own is taken only from all three: the
            // volume says it is the same item, in the same folder, and the
            // names differ by no more than capitals or the form of accents.
            // (A hard link is the same item under another name; an old FAT
            // driver may give every empty file one number.)
            let from = URL(fileURLWithPath: path)
            guard there == item,
                from.deletingLastPathComponent().standardizedFileURL.path
                    == target.deletingLastPathComponent().standardizedFileURL.path,
                OperationRunner.isSameName(from.lastPathComponent, target.lastPathComponent)
            else { return EEXIST }
            return Darwin.rename(path, name) == 0 ? 0 : errno
        }

        if kind == S_IFDIR {
            guard mkdir(name, 0o700) == 0 else { return errno }
        } else {
            let file = open(name, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
            guard file >= 0 else { return errno }
            close(file)
        }
        guard let placeholder = FileIdentity.of(name) else { return ENOENT }
        watching?(.placeholder(target))

        // Used by another program meanwhile: it is theirs now, and stays.
        guard Self.isEmptyPlaceholder(name, placeholder) else { return EEXIST }
        if Darwin.rename(path, name) == 0 { return 0 }
        code = errno
        // The one item at a final name the app removes: its own
        // placeholder, when it is still that and still empty.
        if Self.isEmptyPlaceholder(name, placeholder) {
            if placeholder.kind == S_IFDIR { rmdir(name) } else { unlink(name) }
        }
        return code
    }

    /// Whether what is at `path` is still the placeholder made there (the
    /// same item on the volume, of the same kind) with nothing in it.
    private static func isEmptyPlaceholder(
        _ path: String, _ placeholder: (identity: FileIdentity, kind: mode_t)
    ) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == placeholder.kind,
            FileIdentity(device: info.st_dev, number: info.st_ino) == placeholder.identity
        else { return false }
        if placeholder.kind == S_IFDIR { return TreeCopier.names(in: path) == [] }
        return info.st_size == 0
    }

    /// Puts `url` in the Trash and tells where it is there. Nil when it
    /// could not be: `item` fails with the reason, and `url` is untouched.
    private func moveToTrash(_ url: URL, for item: URL) -> URL? {
        let replacing = url != item
        func failed(_ reason: String) -> URL? {
            fail(item, replacing ? "“\(url.lastPathComponent)” could not be moved to the Trash: \(reason)" : reason)
            return nil
        }
        guard OperationRunner.exists(url) else { return failed(Self.reason(ENOENT)) }
        do {
            var inTrash: NSURL?
            try files.trashItem(at: url, resultingItemURL: &inTrash)
            guard let inTrash = inTrash as URL? else {
                // Gone to the Trash, but the system didn't say where.
                return failed(Self.unknownPlace)
            }
            return inTrash
        } catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain else { return failed(error.localizedDescription) }
            switch error.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return failed(Self.reason(ENOENT))
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                // macOS refuses it for an item of a File Provider domain;
                // Finder may do it.
                guard let finder, CloudTrash.isCloudItem(url, home: home) else { return failed(Self.reason(EACCES)) }
                switch finder.trash(url) {
                case let .success(inTrash): return inTrash
                case .failure(.notAllowed): return failed(CloudTrash.notAllowed)
                case let .failure(.failed(message)): return failed(CloudTrash.finderFailed(message))
                case .failure(.unknownLocation): return failed(Self.unknownPlace)
                }
            case NSFeatureUnsupportedError: return failed("its disk has no Trash")
            default: return failed(error.localizedDescription)
            }
        }
    }

    // MARK: Failures

    private func fail(_ item: URL, _ reason: String) {
        failures.append(ItemFailure(url: item, reason: reason))
    }

    private func fail(_ item: URL, code: Int32) {
        fail(item, Self.reason(code))
    }

    /// The item could not be given its name. When an item was put in the
    /// Trash for it (`replaced`, once at `target`), that one gets its name
    /// back; if it can't, it stays in the Trash, which is told as a change
    /// (so it can be undone) and in the reason.
    private func fail(_ item: URL, placed: Placed, puttingBack replaced: URL? = nil, at target: URL? = nil) {
        let reason: String
        switch placed {
        case .at: return
        case .taken: reason = Self.appeared
        case .otherVolume: reason = Self.reason(EXDEV)
        case let .inTheWay(name): reason = Self.inTheWay(name)
        case let .failed(code): reason = Self.reason(code)
        }
        guard let replaced, let target, !putBack(replaced, at: target) else {
            fail(item, reason)
            return
        }
        changes.append(.trashed(original: target, inTrash: replaced))
        fail(item, "\(reason); “\(target.lastPathComponent)”, which it was to replace, is in the Trash")
    }

    private static let appeared = "an item with that name appeared"

    private static let unknownPlace = "it is in the Trash, but where there is not known"

    private static func alreadyThere(_ name: String) -> String {
        "an item named “\(name)” is already there"
    }

    /// The system's error number as the end of a sentence about the item.
    private static func reason(_ code: Int32) -> String {
        switch code {
        case EACCES, EPERM: "you don't have permission"
        case ENOENT: "it is no longer there"
        case ENOSPC, EDQUOT: "the disk is full"
        case EEXIST, ENOTEMPTY: appeared
        case ENAMETOOLONG: "its name is too long"
        case EROFS: "the disk can't be written to"
        case EFTYPE: "it is not a file, a folder or a link"
        case ENOATTR: "its attributes can't be read"
        default: String(cString: strerror(code)).lowercased()
        }
    }

    /// The full volume's name, and how much more room the rest of the
    /// operation needed than the volume has.
    private static func shortage(on folder: URL, needing needed: Int64) -> Shortage {
        let name = (try? folder.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        var volume = statfs()
        var missing: Int64?
        if statfs(folder.path, &volume) == 0 {
            let free = Int64(volume.f_bavail) * Int64(volume.f_bsize)
            if needed > free { missing = needed - free }
        }
        return Shortage(volume: name ?? folder.lastPathComponent, missing: missing)
    }

    // MARK: Names

    /// The name of a copy while it is written: hidden, beside its target,
    /// and like no other. A very long name is cut, to leave room for the rest.
    private static func partial(for target: URL) -> URL {
        var name = target.lastPathComponent
        while name.utf8.count > 180 { name.removeLast() }
        return target.deletingLastPathComponent()
            .appendingPathComponent(".\(name)\(TreeCopier.partialMark)\(UUID().uuidString)", isDirectory: false)
    }

    /// How far a free name is looked for.
    private static let lastNumber = 10_000

    /// Where an item goes when `url` is taken and both are kept: the first
    /// of `Conflict.freeName`'s names that the volume says nothing has.
    private static func freeName(beside url: URL, folder: Bool) -> URL? {
        let parent = url.deletingLastPathComponent()
        return Conflict.freeName(for: url.lastPathComponent, isFolder: folder, upTo: lastNumber) {
            OperationRunner.exists(parent.appendingPathComponent($0, isDirectory: folder))
        }.map { parent.appendingPathComponent($0, isDirectory: folder) }
    }

    /// Where the duplicate of `url` goes: the first of
    /// `Conflict.duplicateName`'s names that the volume says nothing has.
    private static func duplicateName(beside url: URL, folder: Bool) -> URL? {
        let parent = url.deletingLastPathComponent()
        return Conflict.duplicateName(for: url.lastPathComponent, isFolder: folder, upTo: lastNumber) {
            OperationRunner.exists(parent.appendingPathComponent($0, isDirectory: folder))
        }.map { parent.appendingPathComponent($0, isDirectory: folder) }
    }
}
