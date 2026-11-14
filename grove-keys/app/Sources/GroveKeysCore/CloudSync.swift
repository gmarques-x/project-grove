import Foundation
import GroveThemesCore

// The cloud pill (spec 2026-11-14-bar-cloud-design): whether iCloud Drive and
// the CloudStorage providers have finished syncing. The rules live here; the
// tracker (Grove Keys) watches the folders, reads each changed item's URL
// resource values and keeps the pending set below until its items settle.

/// One item's URL resource values, as the tracker reads them.
public struct CloudItemValues: Equatable, Sendable {
    /// `ubiquitousItemDownloadingStatus`.
    public enum DownloadingStatus: Equatable, Sendable {
        /// Online-only: normal, never pending.
        case notDownloaded
        /// A local copy, with a newer version on the server not being fetched.
        case downloaded
        /// The local copy is the latest.
        case current
    }

    public var isUbiquitous: Bool
    public var isDirectory: Bool
    public var isUploading: Bool
    public var isUploaded: Bool
    public var isDownloading: Bool
    public var downloadingStatus: DownloadingStatus?
    /// The upload / download error's message, when there is one.
    public var uploadError: String?
    public var downloadError: String?
    public var hasConflicts: Bool

    public init(
        isUbiquitous: Bool, isDirectory: Bool = false, isUploading: Bool, isUploaded: Bool, isDownloading: Bool,
        downloadingStatus: DownloadingStatus?, uploadError: String?, downloadError: String?, hasConflicts: Bool
    ) {
        self.isUbiquitous = isUbiquitous
        self.isDirectory = isDirectory
        self.isUploading = isUploading
        self.isUploaded = isUploaded
        self.isDownloading = isDownloading
        self.downloadingStatus = downloadingStatus
        self.uploadError = uploadError
        self.downloadError = downloadError
        self.hasConflicts = hasConflicts
    }

    /// The keys read for an item.
    public static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .isDirectoryKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemUploadingErrorKey,
        .ubiquitousItemDownloadingErrorKey, .ubiquitousItemHasUnresolvedConflictsKey,
    ]

    public init(_ values: URLResourceValues) {
        let status: DownloadingStatus? = switch values.ubiquitousItemDownloadingStatus {
        case .notDownloaded?: .notDownloaded
        case .downloaded?: .downloaded
        case .current?: .current
        default: nil
        }
        self.init(
            isUbiquitous: values.isUbiquitousItem ?? false, isDirectory: values.isDirectory ?? false,
            isUploading: values.ubiquitousItemIsUploading ?? false,
            isUploaded: values.ubiquitousItemIsUploaded ?? false,
            isDownloading: values.ubiquitousItemIsDownloading ?? false, downloadingStatus: status,
            uploadError: values.ubiquitousItemUploadingError.map(\.localizedDescription),
            downloadError: values.ubiquitousItemDownloadingError.map(\.localizedDescription),
            hasConflicts: values.ubiquitousItemHasUnresolvedConflicts ?? false)
    }

    /// The values at `path`, read fresh: a new URL each time, so nothing
    /// cached from an earlier read is returned (an upload finishing may
    /// make no file event; only a fresh read sees it). Reads metadata only.
    public static func read(path: String) throws -> CloudItemValues {
        var url = URL(fileURLWithPath: path)
        url.removeAllCachedResourceValues()
        return CloudItemValues(try url.resourceValues(forKeys: keys))
    }
}

/// What an item is doing.
public enum CloudItemState: Equatable, Sendable {
    case settled, uploading, notUploaded, downloading
    /// An upload/download error (its message), an unresolved conflict, or
    /// stuck (`CloudPending.stuckMessage` / `stuckDownloadMessage`).
    case problem(String)

    /// Pending: uploading, or ubiquitous and not uploaded, or a download
    /// actually under way; files only. Online-only (`notDownloaded`) and
    /// `.downloaded` are never pending. An error or a conflict is a problem.
    public init(_ values: CloudItemValues) {
        guard !values.isDirectory else {
            self = .settled
            return
        }
        if let error = values.uploadError {
            self = .problem(Self.message(error, else: "couldn't upload"))
        } else if let error = values.downloadError {
            self = .problem(Self.message(error, else: "couldn't download"))
        } else if values.hasConflicts {
            self = .problem("unresolved conflict")
        } else if values.isUploading {
            self = .uploading
        } else if values.isDownloading {
            self = .downloading
        } else if values.isUbiquitous && !values.isUploaded && values.downloadingStatus != .notDownloaded {
            // An online-only file can't hold a local edit waiting to upload.
            self = .notUploaded
        } else {
            self = .settled
        }
    }

    private static func message(_ text: String, else fallback: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    public var isPending: Bool {
        switch self {
        case .uploading, .notUploaded, .downloading: return true
        case .settled, .problem: return false
        }
    }

    public var isProblem: Bool {
        if case .problem = self { return true }
        return false
    }

    /// The problem's words, when it is one.
    public var problem: String? {
        if case .problem(let text) = self { return text }
        return nil
    }
}

/// Names the providers never sync, ignored outright (they would be
/// pending forever).
public enum CloudIgnore {
    /// `.DS_Store`, `._*`, `*.nosync`, `~$*` (Office's lock files), `*.tmp`;
    /// the suffixes in any case.
    public static func ignores(name: String) -> Bool {
        let lower = name.lowercased()
        return name == ".DS_Store" || name.hasPrefix("._") || name.hasPrefix("~$")
            || lower.hasSuffix(".nosync") || lower.hasSuffix(".tmp")
    }

    /// An item below `root` whose name, or any folder's between, is ignored
    /// (nothing inside a `.nosync` folder syncs).
    public static func ignores(_ url: URL, root: URL) -> Bool {
        let base = root.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else {
            return ignores(name: url.lastPathComponent)
        }
        return parts.dropFirst(base.count).contains { ignores(name: $0) }
    }
}

/// The pending set: items that are pending or have a problem, re-read on a
/// backoff until they settle. The clock is passed in.
public struct CloudPending: Sendable {
    /// Re-read every 5 s for the first 2 minutes since the item last
    /// changed, then every 60 s.
    public static let fastInterval: TimeInterval = 5
    public static let fastPeriod: TimeInterval = 120
    public static let slowInterval: TimeInterval = 60
    /// Pending this long without a change: a problem.
    public static let stuckAfter: TimeInterval = 30 * 60
    public static let stuckMessage = "not uploading for 30 min"
    public static let stuckDownloadMessage = "not downloading for 30 min"
    /// The most items kept; past it the count reads "2000+".
    public static let cap = 2000

    public struct Entry: Equatable, Sendable {
        public let url: URL
        /// The provider's folder.
        public let root: URL
        /// As last read.
        public fileprivate(set) var read: CloudItemState
        /// When it joined the set (rows: most recent first).
        public let added: Date
        /// When it last changed (its state, or a file event).
        public fileprivate(set) var changed: Date
        public fileprivate(set) var lastRead: Date
        /// Pending past `stuckAfter` with no change.
        public fileprivate(set) var stuck: Bool

        /// What it shows: stuck is a problem, a download's in its own words.
        public var state: CloudItemState {
            guard stuck else { return read }
            return .problem(read == .downloading ? CloudPending.stuckDownloadMessage : CloudPending.stuckMessage)
        }

        public var nextRead: Date {
            let fast = lastRead.timeIntervalSince(changed) < CloudPending.fastPeriod
            return lastRead + (fast ? CloudPending.fastInterval : CloudPending.slowInterval)
        }
    }

    private var items: [String: Entry] = [:]
    /// The roots (by path) an item of which couldn't join because the set
    /// was full. Kept until the caller says it re-walked the root
    /// (`rescanned(root:)`): the dropped items were never kept, so room
    /// again says nothing about them.
    private var overflow: [String: URL] = [:]

    public init() {}

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    /// Every item, in path order.
    public var entries: [Entry] { items.keys.sorted().map { items[$0]! } }
    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    /// Whether `url` is kept (a re-walk tells a drop at the cap by it).
    public func contains(_ url: URL) -> Bool { items[Self.key(url)] != nil }
    /// Some item was dropped at the cap and its root not yet re-walked.
    public var overflowed: Bool { !overflow.isEmpty }
    /// The roots to re-walk (once there's room), in path order.
    public var rootsNeedingRescan: [URL] { overflow.keys.sorted().map { overflow[$0]! } }
    public func needsRescan(_ root: URL) -> Bool { overflow[Self.key(root)] != nil }
    /// Under the cap: a re-walk can add items.
    public var hasRoom: Bool { items.count < Self.cap }

    /// The caller re-walked `root` (reading every item into the set): its
    /// dropped items are accounted for.
    public mutating func rescanned(root: URL) { overflow[Self.key(root)] = nil }

    /// Items pending (not problems, not stuck).
    public var pendingCount: Int { items.values.count { $0.state.isPending } }

    /// An item was read (after a file event on it, or on its re-read).
    /// Settled leaves the set; anything else joins it (unless full) or
    /// updates it. Only a different state is a change: it restarts the fast
    /// reads and the 30 minutes, and clears stuck. A file event that reads
    /// the same state is no change (a provider rewriting the item's metadata
    /// mustn't keep a stalled upload from ever being "not uploading").
    public mutating func update(_ url: URL, root: URL, state: CloudItemState, at now: Date) {
        let key = Self.key(url)
        guard state != .settled else {
            settle(url)
            return
        }
        guard var entry = items[key] else {
            guard items.count < Self.cap else {
                overflow[Self.key(root)] = root
                return
            }
            items[key] = Entry(url: url, root: root, read: state, added: now, changed: now, lastRead: now, stuck: false)
            return
        }
        if state != entry.read {
            entry.read = state
            entry.changed = now
            entry.stuck = false
        }
        entry.lastRead = now
        items[key] = entry
    }

    /// The item left: settled, deleted or now ignored.
    public mutating func settle(_ url: URL) {
        items[Self.key(url)] = nil
    }

    /// The item left, and anything that was in it (a folder removed). An
    /// item in the set is a file, so it ends there; otherwise one pass over
    /// the set, unsorted.
    public mutating func settle(under url: URL) {
        let key = Self.key(url)
        guard items.removeValue(forKey: key) == nil else { return }
        let prefix = key.hasSuffix("/") ? key : key + "/"
        items = items.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Pending items unchanged for 30 minutes become problems. True when one did.
    @discardableResult
    public mutating func expire(at now: Date) -> Bool {
        var any = false
        for (key, entry) in items where !entry.stuck && entry.read.isPending
            && now.timeIntervalSince(entry.changed) >= Self.stuckAfter {
            items[key]?.stuck = true
            any = true
        }
        return any
    }

    /// The items due a re-read at `now`, in path order.
    public func due(at now: Date) -> [URL] {
        entries.filter { $0.nextRead <= now }.map(\.url)
    }

    /// The soonest re-read; nil when the set is empty.
    public var nextRead: Date? { items.values.map(\.nextRead).min() }

    /// A provider's folder went away (signed out, removed): its items go too.
    public mutating func removeRoot(_ root: URL) {
        let key = Self.key(root)
        items = items.filter { Self.key($0.value.root) != key }
        overflow[key] = nil
    }

    /// Keeps only the items of these providers' folders.
    public mutating func retainRoots(_ roots: [URL]) {
        let keys = Set(roots.map(Self.key))
        items = items.filter { keys.contains(Self.key($0.value.root)) }
        overflow = overflow.filter { keys.contains($0.key) }
    }
}

/// Whether a provider's files can be followed.
public enum CloudProviderAccess: Equatable, Sendable {
    case ok
    /// Its folder is there but its app isn't running (OneDrive; iCloud never).
    case notRunning
    /// macOS refused Grove Keys its files; the pill ignores it.
    case cantSee
}

/// One pending or failed file, as a row of the dropdown.
public struct CloudRow: Equatable, Sendable, Identifiable {
    /// The file's path.
    public let id: String
    public let url: URL
    public let name: String
    /// Its folder below the provider's (the provider's title at the top).
    public let folder: String
    public let state: CloudItemState
    /// The problem line; nil while just pending.
    public var problem: String? { state.problem }
}

/// The copy the cloud pill's dropdown says.
public enum CloudWords {
    public static let upToDate = "Up to date"
    public static let openInExplorer = "Open in Grove Explorer"
    public static let settings = "Settings…"
    public static let oneDriveSettingsFallback = "Open OneDrive's settings from its activity window"

    public static func notRunning(_ name: String) -> String { "\(name) isn't running" }
    public static func cantSee(_ name: String) -> String { "Grove Keys can't see \(name)'s files" }

    /// Worst first: "1 problem" / "N problems"; else "Uploading N files ·
    /// Downloading M" (a part left out at 0, "files" after the first);
    /// else "Up to date".
    public static func status(uploading: Int, downloading: Int, problems: Int) -> String {
        if problems > 0 { return problems == 1 ? "1 problem" : "\(problems) problems" }
        func files(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }
        switch (uploading, downloading) {
        case (0, 0): return upToDate
        case (_, 0): return "Uploading \(files(uploading))"
        case (0, _): return "Downloading \(files(downloading))"
        default: return "Uploading \(files(uploading)) · Downloading \(downloading)"
        }
    }
}

/// One provider's section of the dropdown.
public struct CloudProviderSummary: Equatable, Sendable, Identifiable {
    public static let rowLimit = 5

    public let place: CloudProviders.CloudPlace
    public let access: CloudProviderAccess
    public let uploading: Int
    public let downloading: Int
    public let problems: Int
    /// Up to five: problems first, then the most recently pending; within
    /// each, by id (so rows don't jump while counts change).
    public let rows: [CloudRow]
    /// Items were dropped at the cap and the folder not re-walked yet: its
    /// counts may be short (the pill is never synced meanwhile).
    public let needsRescan: Bool

    public var id: String { place.url.path }

    /// "iCloud Drive", or the provider's name ("OneDrive" for every OneDrive account).
    public static func name(of place: CloudProviders.CloudPlace) -> String {
        switch place.kind {
        case .iCloudDrive: return CloudProviders.iCloudDriveName
        case .provider(let name): return name
        }
    }

    public var name: String { Self.name(of: place) }

    /// The app whose process says the provider is running; nil for iCloud
    /// (always running) and the providers without a known app.
    public static func bundleID(for place: CloudProviders.CloudPlace) -> String? {
        guard place.kind != .iCloudDrive else { return nil }
        // Who the provider is comes from its folder in CloudStorage
        // ("OneDrive-…"), by the shared rule, not from the words shown.
        let folder = place.url.standardizedFileURL
        guard folder.deletingLastPathComponent().path.hasSuffix("/" + CloudProviders.cloudStorage),
              let provider = CloudProviders.provider(folderName: folder.lastPathComponent)
        else { return nil }
        return provider.name == oneDriveFolder ? oneDriveBundleID : nil
    }

    /// OneDrive's folders in CloudStorage start "OneDrive" ("OneDrive-Personal").
    static let oneDriveFolder = "OneDrive"
    public static let oneDriveBundleID = "com.microsoft.OneDrive"

    /// iCloud and OneDrive have "Settings…"; others only "Open in Grove Explorer".
    public static func hasSettings(_ place: CloudProviders.CloudPlace) -> Bool {
        place.kind == .iCloudDrive || bundleID(for: place) != nil
    }

    public var statusLine: String {
        switch access {
        case .cantSee: return CloudWords.cantSee(name)
        case .notRunning: return CloudWords.notRunning(name)
        case .ok: return CloudWords.status(uploading: uploading, downloading: downloading, problems: problems)
        }
    }

    /// Turns the pill red (not when it can't be seen: then it's ignored).
    public var isProblem: Bool { access == .notRunning || (access == .ok && problems > 0) }
    public var pending: Int { access == .cantSee ? 0 : uploading + downloading }

    public init(
        place: CloudProviders.CloudPlace, access: CloudProviderAccess, entries: [CloudPending.Entry],
        needsRescan: Bool = false
    ) {
        self.place = place
        self.access = access
        self.needsRescan = access != .cantSee && needsRescan
        let entries = access == .cantSee ? [] : entries
        uploading = entries.count { $0.state == .uploading || $0.state == .notUploaded }
        downloading = entries.count { $0.state == .downloading }
        problems = entries.count { $0.state.isProblem }
        let newest: (CloudPending.Entry, CloudPending.Entry) -> Bool = { a, b in
            a.added != b.added ? a.added > b.added : a.url.path < b.url.path
        }
        let failed = entries.filter { $0.state.isProblem }.sorted(by: newest).prefix(Self.rowLimit)
        let waiting = entries.filter { $0.state.isPending }.sorted(by: newest)
            .prefix(Self.rowLimit - failed.count)
        let byID: (CloudRow, CloudRow) -> Bool = { $0.id < $1.id }
        let root = place.url.standardizedFileURL.pathComponents
        let title = place.title
        func row(_ entry: CloudPending.Entry) -> CloudRow {
            let parent = entry.url.standardizedFileURL.deletingLastPathComponent().pathComponents
            let below = parent.count > root.count && Array(parent.prefix(root.count)) == root
                ? parent.dropFirst(root.count).joined(separator: "/") : title
            return CloudRow(id: entry.url.path, url: entry.url, name: entry.url.lastPathComponent,
                            folder: below, state: entry.state)
        }
        rows = failed.map(row).sorted(by: byID) + waiting.map(row).sorted(by: byID)
    }
}

/// The bar's cloud: the raw value of each case is the bar file's word.
public enum CloudPillState: Equatable, Sendable {
    /// The first pass hasn't finished.
    case checking
    case synced
    /// The pending files; over `CloudPending.cap` reads "2000+".
    case syncing(Int)
    case problem

    /// The count as the label shows it.
    public var countText: String {
        guard case .syncing(let n) = self else { return "" }
        return n > CloudPending.cap ? "\(CloudPending.cap)+" : "\(n)"
    }

    /// The bar file's line (without its newline).
    public var line: String {
        switch self {
        case .checking: return "checking"
        case .synced: return "synced"
        case .syncing: return "syncing \(countText)"
        case .problem: return "problem"
        }
    }
}

/// Every provider's section and the pill.
public struct CloudSummary: Equatable, Sendable {
    /// In the order of the places given (iCloud Drive first, see `places`).
    public let providers: [CloudProviderSummary]
    public let pill: CloudPillState

    /// The pending files of the providers it can see (`CloudPending.cap + 1`
    /// when over the cap).
    public var count: Int {
        guard case .syncing(let n) = pill else { return providers.reduce(0) { $0 + $1.pending } }
        return n
    }

    /// Only the places given get a section: items of a folder that's gone
    /// count nowhere. Checking until the first pass is done; then a problem
    /// anywhere (or a provider not running); then, while a provider it can
    /// see awaits a re-walk after the cap, "2000+" at the cap else checking;
    /// then the pending count.
    public init(
        places: [CloudProviders.CloudPlace], pending: CloudPending,
        access: (CloudProviders.CloudPlace) -> CloudProviderAccess, firstPassDone: Bool
    ) {
        var byRoot: [String: [CloudPending.Entry]] = [:]
        for entry in pending.entries { byRoot[entry.root.standardizedFileURL.path, default: []].append(entry) }
        providers = places.map { place in
            CloudProviderSummary(place: place, access: access(place),
                                 entries: byRoot[place.url.standardizedFileURL.path] ?? [],
                                 needsRescan: pending.needsRescan(place.url))
        }
        let total = providers.reduce(0) { $0 + $1.pending }
        if !firstPassDone {
            pill = .checking
        } else if providers.contains(where: \.isProblem) {
            pill = .problem
        } else if providers.contains(where: \.needsRescan) {
            // Dropped items may still be pending: never synced until re-walked.
            pill = total >= CloudPending.cap ? .syncing(CloudPending.cap + 1) : .checking
        } else {
            pill = total > 0 ? .syncing(total) : .synced
        }
    }

    /// The places followed: iCloud Drive's folder when it's there, then
    /// each folder in CloudStorage in the providers' order.
    public static func places(iCloudPresent: Bool, cloudStorage folderNames: [String], home: URL)
        -> [CloudProviders.CloudPlace]
    {
        (iCloudPresent ? [CloudProviders.iCloudDrivePlace(home: home)] : [])
            + CloudProviders.providers(in: folderNames, home: home)
    }
}

/// The links the dropdown opens.
public enum CloudLinks {
    /// `groveexplorer://open?path=<percent-encoded absolute path>`: a folder
    /// opens, a file opens its folder with it selected.
    public static func explorer(_ url: URL) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            .subtracting(CharacterSet(charactersIn: "\u{80}"..."\u{10FFFF}"))
        let path = url.standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "groveexplorer://open?path=" + path)!
    }

    /// iCloud's settings (community-known; fallback: System Settings).
    public static let iCloudSettings = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!
}

/// The bar's cloud: `$GROVE_STATE/cloud`, one line, `checking`, `synced`,
/// `syncing <n>` or `problem`. Grove Keys writes it, the bar's `cloud` item
/// reads it; no file shows a grey cloud.
public enum CloudBarFile {
    /// Next to keys.json: `$GROVE_STATE/cloud`, default `~/.local/state/grove/cloud`.
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("cloud")
    }

    /// Writes the state's line atomically, readable by the owner only,
    /// unless the file already holds it; nil removes the file (Grove Keys
    /// stopped). True when the file changed, so the bar is told only then.
    @discardableResult
    public static func update(_ state: CloudPillState?, at url: URL) throws -> Bool {
        guard let state else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                return false
            }
            return true
        }
        let line = state.line + "\n"
        guard (try? String(contentsOf: url, encoding: .utf8)) != line else { return false }
        try writeAtomically(Data(line.utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
}
