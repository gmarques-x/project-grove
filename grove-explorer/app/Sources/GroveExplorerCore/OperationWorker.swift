import Foundation

/// How giving an item its final name went.
private enum Placed {
    case at(URL)
    /// The name is taken.
    case taken
    /// The name is on another volume than the item.
    case otherVolume
    case failed(Int32)
}

/// One run of one operation, on the thread it was started on.
final class Worker {
    private let operation: Operation
    /// The targets that were there when the names were looked up, less the
    /// ones already asked about: an answer is for one item.
    private var known: Set<String>
    private let files: FileManager
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
        operation: Operation, known: Set<String>, files: FileManager, flag: CancelFlag,
        watching: (@Sendable (OperationRunner.Stage) -> Void)?,
        resolve: @escaping (URL) -> Conflict.Choice, progress: @escaping (Progress) -> Void
    ) {
        self.operation = operation
        self.known = known
        self.files = files
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
            if let volume {
                transfer(item, to: folder, on: volume, moving: moving)
            } else {
                fail(item, "the folder “\(folder.lastPathComponent)” is not there")
            }
            if cancelled || shortage != nil { break }
            reporter.itemFinished(bytes: size)
        }
    }

    private func transfer(_ item: URL, to folder: URL, on volume: dev_t, moving: Bool) {
        var code: Int32 = 0
        guard let (source, kind) = FileIdentity.of(item.path, code: &code) else {
            fail(item, code: code)
            return
        }
        var target = OperationRunner.target(for: item, in: folder)
        var replacing = false
        var nextFree: (() -> URL?)?

        if OperationRunner.exists(target) {
            // Not there when the names were looked up: nobody was asked
            // about it, so no answer is about it.
            // And asked about once: a second item of the same name finds
            // the first one's arrival there, which nobody was asked about.
            guard known.remove(OperationRunner.key(target)) != nil else {
                fail(item, Self.appeared)
                return
            }
            switch resolve(target) {
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
            guard moving else {
                changes.append(.created(final))
                done += 1
                return
            }
            // The source goes only when the copy is all of it.
            if !copier.isWhole(final.path, of: item.path) {
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
        let next = { Self.freeName(beside: item, folder: kind == S_IFDIR, adding: " copy") }
        guard let target = next() else {
            fail(item, "no free name was found for it")
            return
        }
        guard let partial = copyToPartial(item, for: target, on: item.deletingLastPathComponent()) else { return }
        switch place(partial.path, at: target, orAt: next) {
        case let .at(final):
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
        if let there = FileIdentity.of(target.path)?.identity, there != source {
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

    /// Gives the item at `path` its final name, never in place of another
    /// item. When the name is taken and `next` is given (a name that only
    /// has to be free: a duplicate, "keep both"), the next free name is tried.
    private func place(_ path: String, at target: URL, orAt next: (() -> URL?)?) -> Placed {
        var target = target
        for _ in 0..<100 {
            watching?(.placing(target))
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
            guard there == item else { return EEXIST }
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
                return failed("it is in the Trash, but where there is not known")
            }
            return inTrash
        } catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain else { return failed(error.localizedDescription) }
            switch error.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return failed(Self.reason(ENOENT))
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return failed(Self.reason(EACCES))
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

    /// The first name beside `url` that nothing has, counting up: "notes
    /// 2.md", "notes 3.md" (a folder's name is not split: "docs 2"). With
    /// `adding` " copy": "notes copy.md", then "notes copy 2.md".
    ///
    /// Task 9's `Conflict.freeName` takes the place of this.
    private static func freeName(beside url: URL, folder: Bool, adding: String = "") -> URL? {
        let name = url.lastPathComponent
        var stem = name
        var ending = ""
        // An extension: after the last dot, when that isn't the first
        // character, something follows it, and that has no space.
        if !folder, let dot = name.lastIndex(of: "."), dot != name.startIndex,
            name.index(after: dot) != name.endIndex, !name[dot...].contains(where: \.isWhitespace)
        {
            stem = String(name[..<dot])
            ending = String(name[dot...])
        }
        stem += adding
        let parent = url.deletingLastPathComponent()
        for number in (adding.isEmpty ? 2 : 1)...10_000 {
            let candidate = parent.appendingPathComponent(
                (number == 1 ? stem : "\(stem) \(number)") + ending, isDirectory: folder)
            if !OperationRunner.exists(candidate) { return candidate }
        }
        return nil
    }
}
