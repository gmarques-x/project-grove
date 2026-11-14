import CoreServices
import Darwin
import Foundation

// How the cloud tracker (Grove Keys) looks at the cloud folders without ever
// downloading anything (spec 2026-11-14-bar-cloud-design): a walk that reads
// only lstat, directory listings and resource values, skips online-only
// (dataless) folders, and is paced; the file events it gets, sorted into
// what to do and coalesced so a burst of thousands is a bounded amount of work.

/// What lstat says about one entry.
public struct CloudStat: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case file, directory
        /// A link or anything else: never followed, never read.
        case other
    }

    public var kind: Kind
    /// `SF_DATALESS`: online-only, its contents (a folder's listing, a
    /// file's data) not on this Mac.
    public var isDataless: Bool

    public init(kind: Kind, isDataless: Bool = false) {
        self.kind = kind
        self.isDataless = isDataless
    }

    /// From `st_mode` and `st_flags`.
    public init(mode: mode_t, flags: UInt32) {
        let kind: Kind = switch mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        default: .other
        }
        self.init(kind: kind, isDataless: flags & UInt32(bitPattern: SF_DATALESS) != 0)
    }
}

/// An errno from lstat or a listing.
public struct CloudFSError: Error, Equatable, Sendable {
    public let code: Int32

    public init(code: Int32) { self.code = code }

    /// macOS refused (the provider's files need the owner's permission).
    public var isRefused: Bool { code == EPERM || code == EACCES }
    /// Not there (any more).
    public var isGone: Bool { code == ENOENT || code == ENOTDIR }
}

/// The two things a walk asks of the file system: metadata only.
public protocol CloudFileSystem {
    func lstat(_ path: String) -> Result<CloudStat, CloudFSError>
    func list(_ path: String) -> Result<[String], CloudFSError>
}

/// The real one: `lstat(2)` and `opendir(3)` / `readdir(3)`. Nothing is
/// opened for reading, coordinated, or followed through a link.
public struct CloudPOSIX: CloudFileSystem, Sendable {
    public init() {}

    public func lstat(_ path: String) -> Result<CloudStat, CloudFSError> {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return .failure(CloudFSError(code: errno)) }
        return .success(CloudStat(mode: info.st_mode, flags: info.st_flags))
    }

    public func list(_ path: String) -> Result<[String], CloudFSError> {
        guard let dir = opendir(path) else { return .failure(CloudFSError(code: errno)) }
        defer { closedir(dir) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        // readdir returns nil at the end and on an error, which sets errno.
        if errno != 0 { return .failure(CloudFSError(code: errno)) }
        return .success(names)
    }
}

/// The rules of the walk.
public enum CloudWalk {
    public enum Decision: Equatable, Sendable { case descend, read, skip }

    /// Folders are walked, files read (an online-only one too: only its
    /// resource values, which the thread's policy keeps from downloading
    /// it; a download under way is pending); skipped: names never synced
    /// (and whatever is in such a folder), online-only folders (listing one
    /// would download it, and it can't hold local edits waiting to upload),
    /// links and anything else.
    public static func decide(name: String, _ stat: CloudStat) -> Decision {
        guard !CloudIgnore.ignores(name: name) else { return .skip }
        switch stat.kind {
        case .directory: return stat.isDataless ? .skip : .descend
        case .file: return .read
        case .other: return .skip
        }
    }

    /// The calling thread never materialises a dataless file or folder: an
    /// access that would makes the call fail instead. Thread-scoped, so only
    /// the tracker's own thread is changed. False if macOS refused.
    @discardableResult
    public static func turnOffMaterialization() -> Bool {
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                       IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
            && materializationIsOff
    }

    /// Whether the calling thread has it turned off.
    public static var materializationIsOff: Bool {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
            == IOPOL_MATERIALIZE_DATALESS_FILES_OFF
    }
}

/// One walk of a provider's folder (the first pass, a re-walk after the cap)
/// or of a folder below it (one that appeared), done a few entries at a time
/// so the tracker can pace it and see to file events between steps.
public struct CloudWalker: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Call `step` again.
        case more
        case done
        /// The starting folder can't be read: macOS refused.
        case refused
        /// The starting folder or file isn't there.
        case gone
    }

    /// The provider's folder.
    public let root: URL
    /// Where the walk starts: the root, or a folder or file below it.
    public let start: URL
    /// Each lstat and each listing.
    public private(set) var operations = 0
    /// Files handed to `visit`.
    public private(set) var files = 0
    /// Online-only folders passed over (never listed).
    public private(set) var skippedDataless = 0

    private var begun = false
    /// Folders to list.
    private var folders: [String] = []
    /// Entries listed and not yet looked at.
    private var entries: [String] = []

    public init(root: URL, start: URL? = nil) {
        self.root = root
        self.start = start ?? root
    }

    /// Does up to `budget` operations, handing each file to read to `visit`.
    public mutating func step(budget: Int, fs: some CloudFileSystem, visit: (URL) -> Void) -> Outcome {
        var left = max(1, budget)
        if !begun {
            begun = true
            left -= 1
            operations += 1
            switch fs.lstat(start.path) {
            case .failure(let error): return error.isRefused ? .refused : .gone
            case .success(let stat):
                switch stat.kind {
                case .directory where stat.isDataless:
                    skippedDataless += 1
                    return .done
                case .directory:
                    // The first listing decides refused / gone for the walk.
                    operations += 1
                    left -= 1
                    switch fs.list(start.path) {
                    case .failure(let error): return error.isRefused ? .refused : .gone
                    case .success(let names): entries = names.map { start.path + "/" + $0 }
                    }
                case .file:
                    if !CloudIgnore.ignores(start, root: root) {
                        files += 1
                        visit(start)
                    }
                    return .done
                case .other:
                    return .done
                }
            }
        }
        while left > 0 {
            if let path = entries.popLast() {
                left -= 1
                operations += 1
                guard case .success(let stat) = fs.lstat(path) else { continue }
                if stat.kind == .directory && stat.isDataless { skippedDataless += 1 }
                switch CloudWalk.decide(name: (path as NSString).lastPathComponent, stat) {
                case .descend: folders.append(path)
                case .read:
                    files += 1
                    visit(URL(fileURLWithPath: path))
                case .skip: break
                }
            } else if let folder = folders.popLast() {
                left -= 1
                operations += 1
                // A folder below that can't be listed (refused, gone meanwhile) is left out.
                if case .success(let names) = fs.list(folder) {
                    entries = names.map { folder + "/" + $0 }
                }
            } else {
                return .done
            }
        }
        return entries.isEmpty && folders.isEmpty ? .done : .more
    }
}

/// How fast the tracker may look at files: a cap on lstats, listings and
/// resource-value reads per second, so a huge folder at login is a gentle
/// trickle, not a spike.
public struct CloudPace: Sendable {
    public static let files = CloudPace(perSecond: 2000)

    public let perSecond: Double

    public init(perSecond: Double) { self.perSecond = perSecond }

    /// How long to wait after `done` operations that took `took` seconds.
    public func wait(done: Int, took: TimeInterval) -> TimeInterval {
        max(0, Double(done) / perSecond - took)
    }
}

/// The folders followed, as FSEvents names them (links resolved: /private/var
/// for /var) and as the places spell them (what the items are called).
public struct CloudRoots: Sendable {
    public struct Match: Equatable, Sendable {
        public let root: URL
        /// The path below the root ("" for the root itself).
        public let relative: String
    }

    private let pairs: [(real: String, root: URL)]

    public init(_ roots: [URL]) {
        self.init(pairs: roots.map { (Self.realPath($0), $0) })
    }

    /// The path with every link resolved, as FSEvents reports it: realpath(3)
    /// (Foundation's `resolvingSymlinksInPath` drops a leading /private,
    /// which FSEvents keeps). The path as given when it can't be resolved.
    public static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    init(pairs: [(real: String, root: URL)]) {
        self.pairs = pairs.sorted { $0.real.count > $1.real.count }
    }

    public var urls: [URL] { pairs.map(\.root) }

    /// The root `path` is in (the deepest, should any nest), and the rest.
    public func root(of path: String) -> Match? {
        for pair in pairs {
            if path == pair.real { return Match(root: pair.root, relative: "") }
            if path.hasPrefix(pair.real + "/") {
                return Match(root: pair.root, relative: String(path.dropFirst(pair.real.count + 1)))
            }
        }
        return nil
    }

    /// The item at `relative` below `root`, in the place's spelling.
    func url(_ match: Match) -> URL {
        match.relative.isEmpty ? match.root : URL(fileURLWithPath: match.root.path + "/" + match.relative)
    }
}

/// What a file event asks the tracker to do.
public enum CloudEvent: Equatable, Sendable {
    /// A file changed (or went: the read finds out).
    case read(URL, root: URL)
    /// A folder appeared (made, or moved in): walk it.
    case expand(URL, root: URL)
    /// It went, or is now a name never synced: it and whatever was in it settle.
    case gone(URL, root: URL)
    /// Events under it were lost: walk it again.
    case rescan(URL, root: URL)
    /// The roots may have changed (one moved, went, a volume came or left).
    case roots

    public var url: URL? {
        switch self {
        case .read(let url, _), .expand(let url, _), .gone(let url, _), .rescan(let url, _): return url
        case .roots: return nil
        }
    }

    public var root: URL? {
        switch self {
        case .read(_, let root), .expand(_, let root), .gone(_, let root), .rescan(_, let root): return root
        case .roots: return nil
        }
    }
}

/// FSEvents' (path, flags) sorted into `CloudEvent`s.
public enum CloudEvents {
    private static func has(_ flags: UInt32, _ bit: Int) -> Bool { flags & UInt32(bit) != 0 }

    public static func classify(path: String, flags: UInt32, roots: CloudRoots) -> [CloudEvent] {
        let changed = has(flags, kFSEventStreamEventFlagRootChanged) || has(flags, kFSEventStreamEventFlagMount)
            || has(flags, kFSEventStreamEventFlagUnmount)
        guard let match = roots.root(of: path) else { return changed ? [.roots] : [] }
        if changed { return [.roots] }
        let url = roots.url(match)
        let root = match.root
        let dropped = has(flags, kFSEventStreamEventFlagMustScanSubDirs) || has(flags, kFSEventStreamEventFlagUserDropped)
            || has(flags, kFSEventStreamEventFlagKernelDropped)
        if dropped { return [.rescan(url, root: root)] }
        let isDir = has(flags, kFSEventStreamEventFlagItemIsDir)
        let isFile = has(flags, kFSEventStreamEventFlagItemIsFile)
        let made = has(flags, kFSEventStreamEventFlagItemCreated) || has(flags, kFSEventStreamEventFlagItemRenamed)
        let removed = has(flags, kFSEventStreamEventFlagItemRemoved)
        if match.relative.isEmpty {
            // The root's own metadata says nothing; the root going does.
            return isDir && removed ? [.roots] : []
        }
        if CloudIgnore.ignores(url, root: root) { return isDir || isFile ? [.gone(url, root: root)] : [] }
        if isFile { return [.read(url, root: root)] }
        if isDir {
            if made { return [.expand(url, root: root)] }
            if removed { return [.gone(url, root: root)] }
        }
        return []
    }
}

/// File events waiting for the tracker, one per path (a newer one replaces
/// an older, but a read never replaces a walk or a removal, and nothing
/// replaces a re-walk), in the order they came. A root with more than
/// `limit` waiting becomes one re-walk of that root, and while that waits its
/// other events (but removals) are dropped: a burst of thousands is a bounded
/// amount of memory and of work.
public struct CloudEventBatch: Sendable {
    public static let limit = 10_000

    private var order: [String] = []
    private var head = 0
    private var byPath: [String: CloudEvent] = [:]
    private var perRoot: [String: Int] = [:]
    /// Roots whose re-walk is waiting.
    private var rewalks: Set<String> = []
    public private(set) var rootsChanged = false

    public init() {}

    /// Events waiting (the roots' flag aside).
    public var count: Int { byPath.count }
    public var isEmpty: Bool { byPath.isEmpty && !rootsChanged }

    private static func rank(_ event: CloudEvent) -> Int {
        switch event {
        case .read: return 0
        case .expand, .gone: return 1
        case .rescan: return 2
        case .roots: return 3
        }
    }

    public mutating func add(_ event: CloudEvent) {
        guard let url = event.url, let root = event.root else {
            rootsChanged = true
            return
        }
        let rootKey = root.path
        if rewalks.contains(rootKey) {
            if case .gone = event {} else { return }
        }
        let key = url.path
        if let old = byPath[key] {
            if Self.rank(event) >= Self.rank(old) && !(Self.rank(old) == 2) { byPath[key] = event }
            return
        }
        byPath[key] = event
        order.append(key)
        perRoot[rootKey, default: 0] += 1
        if perRoot[rootKey]! > Self.limit { collapse(root) }
    }

    /// Everything waiting for `root` but removals becomes one re-walk of it.
    private mutating func collapse(_ root: URL) {
        let rootKey = root.path
        for (key, event) in byPath where event.root?.path == rootKey {
            if case .gone = event { continue }
            byPath[key] = nil
            perRoot[rootKey, default: 1] -= 1
        }
        rewalks.insert(rootKey)
        byPath[rootKey] = .rescan(root, root: root)
        order.append(rootKey)
        perRoot[rootKey, default: 0] += 1
    }

    /// Up to `max` events, oldest first (the roots' flag is cleared too:
    /// the caller re-reads the roots when it was set).
    public mutating func take(_ max: Int) -> [CloudEvent] {
        rootsChanged = false
        var out: [CloudEvent] = []
        while out.count < max, head < order.count {
            let key = order[head]
            head += 1
            guard let event = byPath.removeValue(forKey: key) else { continue }
            if let root = event.root?.path {
                perRoot[root, default: 1] -= 1
                if perRoot[root] == 0 { perRoot[root] = nil }
                if case .rescan(let url, _) = event, url.path == root { rewalks.remove(root) }
            }
            out.append(event)
        }
        if head > 1024 && head * 2 > order.count {
            order.removeFirst(head)
            head = 0
        }
        if byPath.isEmpty {
            order.removeAll(keepingCapacity: true)
            head = 0
        }
        return out
    }
}
