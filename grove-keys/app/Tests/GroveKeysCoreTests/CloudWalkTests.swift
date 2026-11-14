import CoreServices
import Darwin
import os
import Foundation
import Testing
@testable import GroveKeysCore

// Invented paths and names only (the repo is public). The walks here run on
// a fake file system, or on a temporary folder; never on a real cloud folder.

/// A file system in memory that records what was asked of it.
private final class FakeFS: CloudFileSystem, @unchecked Sendable {
    enum Node {
        case dir([String], dataless: Bool = false)
        case file(dataless: Bool = false)
        case refused
        case link
    }

    var nodes: [String: Node]
    private(set) var listed: [String] = []
    private(set) var statted: [String] = []

    init(_ nodes: [String: Node]) { self.nodes = nodes }

    func lstat(_ path: String) -> Result<CloudStat, CloudFSError> {
        statted.append(path)
        switch nodes[path] {
        case nil: return .failure(CloudFSError(code: ENOENT))
        case .refused: return .failure(CloudFSError(code: EPERM))
        case .dir(_, let dataless): return .success(CloudStat(kind: .directory, isDataless: dataless))
        case .file(let dataless): return .success(CloudStat(kind: .file, isDataless: dataless))
        case .link: return .success(CloudStat(kind: .other))
        }
    }

    func list(_ path: String) -> Result<[String], CloudFSError> {
        listed.append(path)
        switch nodes[path] {
        case .dir(let names, _): return .success(names)
        case .refused: return .failure(CloudFSError(code: EACCES))
        case nil: return .failure(CloudFSError(code: ENOENT))
        default: return .failure(CloudFSError(code: ENOTDIR))
        }
    }
}

private let root = URL(fileURLWithPath: "/Users/someone/Library/CloudStorage/OneDrive-Personal")
private func p(_ relative: String) -> String { relative.isEmpty ? root.path : root.path + "/" + relative }

/// A provider's folder: plain files, an online-only folder (dataless, with
/// contents that must never be listed), an online-only file, names never
/// synced, a .nosync folder and a link.
private func tree() -> FakeFS {
    FakeFS([
        p(""): .dir(["Notes", "Online", "photo.jpg", "online.pdf", ".DS_Store", "Thing.nosync", "link", "~$lock.docx"]),
        p("Notes"): .dir(["a.txt", "b.txt", "Deep", "draft.tmp"]),
        p("Notes/a.txt"): .file(),
        p("Notes/b.txt"): .file(),
        p("Notes/draft.tmp"): .file(),
        p("Notes/Deep"): .dir(["c.txt"]),
        p("Notes/Deep/c.txt"): .file(),
        p("Online"): .dir(["never.txt"], dataless: true),
        p("Online/never.txt"): .file(),
        p("photo.jpg"): .file(),
        p("online.pdf"): .file(dataless: true),
        p(".DS_Store"): .file(),
        p("Thing.nosync"): .dir(["inside.txt"]),
        p("Thing.nosync/inside.txt"): .file(),
        p("link"): .link,
        p("~$lock.docx"): .file(),
    ])
}

private func walkAll(_ walker: inout CloudWalker, _ fs: FakeFS, budget: Int = 1000) -> ([String], CloudWalker.Outcome) {
    var seen: [String] = []
    var outcome = CloudWalker.Outcome.more
    var steps = 0
    while outcome == .more {
        outcome = walker.step(budget: budget, fs: fs) { seen.append($0.path) }
        steps += 1
        precondition(steps < 10_000)
    }
    return (seen.sorted(), outcome)
}

struct CloudWalkDecisionTests {
    @Test func whatTheWalkDoesWithEachEntry() {
        #expect(CloudWalk.decide(name: "Notes", CloudStat(kind: .directory)) == .descend)
        #expect(CloudWalk.decide(name: "a.txt", CloudStat(kind: .file)) == .read)
        // An online-only folder can't hold local edits waiting to upload:
        // never listed (listing it would download its contents).
        #expect(CloudWalk.decide(name: "Online", CloudStat(kind: .directory, isDataless: true)) == .skip)
        // An online-only file is never pending.
        #expect(CloudWalk.decide(name: "online.pdf", CloudStat(kind: .file, isDataless: true)) == .skip)
        // Names never synced, and what's in them.
        for name in [".DS_Store", "._a.txt", "Thing.nosync", "~$lock.docx", "draft.TMP"] {
            #expect(CloudWalk.decide(name: name, CloudStat(kind: .file)) == .skip, "\(name)")
            #expect(CloudWalk.decide(name: name, CloudStat(kind: .directory)) == .skip, "\(name)")
        }
        // Links and anything else: not followed, not read.
        #expect(CloudWalk.decide(name: "link", CloudStat(kind: .other)) == .skip)
    }

    @Test func theStatFlagsSayDataless() {
        let dataless = UInt32(bitPattern: SF_DATALESS)
        #expect(CloudStat(mode: S_IFDIR | 0o755, flags: dataless) == CloudStat(kind: .directory, isDataless: true))
        #expect(CloudStat(mode: S_IFDIR | 0o755, flags: 0) == CloudStat(kind: .directory, isDataless: false))
        #expect(CloudStat(mode: S_IFREG | 0o644, flags: dataless | UInt32(UF_HIDDEN))
            == CloudStat(kind: .file, isDataless: true))
        #expect(CloudStat(mode: S_IFLNK | 0o755, flags: 0).kind == .other)
    }

    @Test func refusedAndGoneErrors() {
        #expect(CloudFSError(code: EPERM).isRefused)
        #expect(CloudFSError(code: EACCES).isRefused)
        #expect(!CloudFSError(code: ENOENT).isRefused)
        #expect(CloudFSError(code: ENOENT).isGone)
        #expect(CloudFSError(code: ENOTDIR).isGone)
        #expect(!CloudFSError(code: EPERM).isGone)
    }
}

struct CloudWalkerTests {
    @Test func walksOnlyLocalFilesAndNeverListsADatalessFolder() {
        let fs = tree()
        var walker = CloudWalker(root: root)
        let (seen, outcome) = walkAll(&walker, fs)
        #expect(outcome == .done)
        #expect(seen == [p("Notes/Deep/c.txt"), p("Notes/a.txt"), p("Notes/b.txt"), p("photo.jpg")])
        #expect(!fs.listed.contains(p("Online")))
        #expect(!fs.statted.contains(p("Online/never.txt")))
        #expect(!fs.listed.contains(p("Thing.nosync")))
        #expect(walker.skippedDataless == 2)
        #expect(walker.files == 4)
    }

    @Test func aSmallBudgetSpreadsTheWalkOverStepsWithTheSameResult() {
        let fs = tree()
        var walker = CloudWalker(root: root)
        var seen: [String] = []
        var outcome = CloudWalker.Outcome.more
        var steps = 0
        while outcome == .more {
            let before = walker.operations
            outcome = walker.step(budget: 2, fs: fs) { seen.append($0.path) }
            #expect(walker.operations - before <= 2)
            steps += 1
        }
        #expect(outcome == .done)
        #expect(steps > 5)
        #expect(seen.sorted() == [p("Notes/Deep/c.txt"), p("Notes/a.txt"), p("Notes/b.txt"), p("photo.jpg")])
        // Every lstat and every listing counts.
        #expect(walker.operations == fs.listed.count + fs.statted.count)
    }

    @Test func aRootItCantReadIsRefused() {
        let refusedAtStat = FakeFS([p(""): .refused])
        var walker = CloudWalker(root: root)
        #expect(walkAll(&walker, refusedAtStat).1 == .refused)

        // The folder is there but listing it is refused.
        final class RefusedList: CloudFileSystem, @unchecked Sendable {
            func lstat(_ path: String) -> Result<CloudStat, CloudFSError> { .success(CloudStat(kind: .directory)) }
            func list(_ path: String) -> Result<[String], CloudFSError> { .failure(CloudFSError(code: EPERM)) }
        }
        var again = CloudWalker(root: root)
        var outcome = CloudWalker.Outcome.more
        while outcome == .more { outcome = again.step(budget: 10, fs: RefusedList()) { _ in } }
        #expect(outcome == .refused)
    }

    @Test func aFolderBelowTheRootItCantReadIsLeftOut() {
        let fs = tree()
        fs.nodes[p("Notes/Deep")] = .refused
        var walker = CloudWalker(root: root)
        let (seen, outcome) = walkAll(&walker, fs)
        #expect(outcome == .done)
        #expect(seen == [p("Notes/a.txt"), p("Notes/b.txt"), p("photo.jpg")])
    }

    @Test func aRootThatIsGoneSaysSo() {
        var walker = CloudWalker(root: root)
        #expect(walkAll(&walker, FakeFS([:])).1 == .gone)
    }

    @Test func aDatalessRootIsNeverListed() {
        let fs = FakeFS([p(""): .dir(["x.txt"], dataless: true), p("x.txt"): .file()])
        var walker = CloudWalker(root: root)
        let (seen, outcome) = walkAll(&walker, fs)
        #expect(outcome == .done)
        #expect(seen.isEmpty)
        #expect(fs.listed.isEmpty)
    }

    @Test func expandingAFolderWalksOnlyBelowIt() {
        let fs = tree()
        var walker = CloudWalker(root: root, start: URL(fileURLWithPath: p("Notes")))
        let (seen, outcome) = walkAll(&walker, fs)
        #expect(outcome == .done)
        #expect(seen == [p("Notes/Deep/c.txt"), p("Notes/a.txt"), p("Notes/b.txt")])
        #expect(walker.root == root)
        // A start that's a file is read; one that's online-only, not.
        var one = CloudWalker(root: root, start: URL(fileURLWithPath: p("photo.jpg")))
        #expect(walkAll(&one, fs).0 == [p("photo.jpg")])
        var online = CloudWalker(root: root, start: URL(fileURLWithPath: p("Online")))
        #expect(walkAll(&online, fs).0.isEmpty)
        #expect(!fs.listed.contains(p("Online")))
        // One that's gone (renamed away, removed) says so.
        var gone = CloudWalker(root: root, start: URL(fileURLWithPath: p("Nowhere")))
        #expect(walkAll(&gone, fs).1 == .gone)
    }
}

struct CloudWalkRealFolderTests {
    /// A temporary folder, never a cloud one.
    private func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-walk-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func posixReadsKindsAndNames() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("l").path, withDestinationPath: "a.txt")
        let fs = CloudPOSIX()
        #expect(try fs.lstat(dir.path).get() == CloudStat(kind: .directory))
        #expect(try fs.lstat(dir.appendingPathComponent("a.txt").path).get() == CloudStat(kind: .file))
        #expect(try fs.lstat(dir.appendingPathComponent("l").path).get().kind == .other)
        #expect(try fs.list(dir.path).get().sorted() == ["a.txt", "l", "sub"])
        #expect(fs.lstat(dir.appendingPathComponent("none").path) == .failure(CloudFSError(code: ENOENT)))
        #expect(fs.list(dir.appendingPathComponent("none").path) == .failure(CloudFSError(code: ENOENT)))
    }

    @Test func posixSaysRefusedForAFolderItMayNotList() throws {
        let dir = try temp()
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        guard case .failure(let error) = CloudPOSIX().list(locked.path) else {
            Issue.record("listed a folder with no permissions")
            return
        }
        #expect(error.isRefused)
    }

    @Test func walksATemporaryTree() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        for folder in ["A", "A/B", "C"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["A/1.txt", "A/B/2.txt", "C/3.txt", "C/.DS_Store", "top.txt"] {
            try Data().write(to: dir.appendingPathComponent(file))
        }
        var walker = CloudWalker(root: dir)
        var seen: [String] = []
        var outcome = CloudWalker.Outcome.more
        while outcome == .more { outcome = walker.step(budget: 3, fs: CloudPOSIX()) { seen.append($0.path) } }
        #expect(outcome == .done)
        #expect(seen.sorted() == ["A/1.txt", "A/B/2.txt", "C/3.txt", "top.txt"].map { dir.path + "/" + $0 })
    }

    @Test func materializationIsTurnedOffForTheWalkingThreadOnly() {
        let done = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock(initialState: (turned: false, after: Int32(-1)))
        let thread = Thread {
            let turned = CloudWalk.turnOffMaterialization()
            let after = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
            result.withLock { $0 = (turned, after) }
            done.signal()
        }
        thread.start()
        done.wait()
        let (turned, after) = result.withLock { $0 }
        #expect(turned)
        #expect(after == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        // This thread is untouched.
        #expect(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
            != IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    }
}

struct CloudPaceTests {
    @Test func keepsTheRateUnderTheCap() {
        let pace = CloudPace(perSecond: 2000)
        #expect(pace.wait(done: 2000, took: 0.25) == 0.75)
        #expect(pace.wait(done: 200, took: 0) == 0.1)
        #expect(pace.wait(done: 200, took: 0.5) == 0)
        #expect(pace.wait(done: 0, took: 0) == 0)
        #expect(CloudPace.files.perSecond == 2000)
    }
}

private let other = URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs")
private let roots = CloudRoots([root, other])

private func flags(_ bits: Int...) -> UInt32 { UInt32(bits.reduce(0, |)) }

struct CloudEventsTests {
    private let file = kFSEventStreamEventFlagItemIsFile
    private let dir = kFSEventStreamEventFlagItemIsDir

    @Test func aChangedFileIsReadUnderItsRoot() {
        let events = CloudEvents.classify(path: p("Notes/a.txt"), flags: flags(file, kFSEventStreamEventFlagItemModified),
                                          roots: roots)
        #expect(events == [.read(URL(fileURLWithPath: p("Notes/a.txt")), root: root)])
        let icloud = other.path + "/Doc.pages"
        #expect(CloudEvents.classify(path: icloud, flags: flags(file, kFSEventStreamEventFlagItemCreated), roots: roots)
            == [.read(URL(fileURLWithPath: icloud), root: other)])
    }

    @Test func aRemovedFileIsReadToo() {
        // FSEvents merges flags (removed then made again, a safe save), so the
        // tracker looks: a file that's gone settles there.
        let events = CloudEvents.classify(path: p("a.txt"), flags: flags(file, kFSEventStreamEventFlagItemRemoved), roots: roots)
        #expect(events == [.read(URL(fileURLWithPath: p("a.txt")), root: root)])
    }

    @Test func aFolderThatAppearsIsExpandedAndOneThatGoesSettlesWhatWasInIt() {
        let folder = URL(fileURLWithPath: p("Unzipped"))
        #expect(CloudEvents.classify(path: folder.path, flags: flags(dir, kFSEventStreamEventFlagItemCreated), roots: roots)
            == [.expand(folder, root: root)])
        #expect(CloudEvents.classify(path: folder.path, flags: flags(dir, kFSEventStreamEventFlagItemRenamed), roots: roots)
            == [.expand(folder, root: root)])
        #expect(CloudEvents.classify(path: folder.path, flags: flags(dir, kFSEventStreamEventFlagItemRemoved), roots: roots)
            == [.gone(folder, root: root)])
        // Created and removed in one batch: look.
        #expect(CloudEvents.classify(
            path: folder.path, flags: flags(dir, kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved),
            roots: roots) == [.expand(folder, root: root)])
        // A folder's own metadata changing: folders never count.
        #expect(CloudEvents.classify(path: folder.path, flags: flags(dir, kFSEventStreamEventFlagItemXattrMod), roots: roots)
            .isEmpty)
    }

    @Test func namesNeverSyncedLeave() {
        for path in [p(".DS_Store"), p("Notes/._a.txt"), p("Thing.nosync/inside.txt"), p("~$lock.docx"), p("x.tmp")] {
            #expect(CloudEvents.classify(path: path, flags: flags(file, kFSEventStreamEventFlagItemModified), roots: roots)
                == [.gone(URL(fileURLWithPath: path), root: root)], "\(path)")
        }
    }

    @Test func droppedEventsMeanAWalkAgain() {
        for bit in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
                    kFSEventStreamEventFlagKernelDropped] {
            #expect(CloudEvents.classify(path: p("Notes"), flags: flags(bit), roots: roots)
                == [.rescan(URL(fileURLWithPath: p("Notes")), root: root)])
        }
    }

    @Test func theRootItselfMovingRereadsTheRoots() {
        #expect(CloudEvents.classify(path: root.path, flags: flags(kFSEventStreamEventFlagRootChanged), roots: roots) == [.roots])
        #expect(CloudEvents.classify(path: root.path, flags: flags(dir, kFSEventStreamEventFlagItemRemoved), roots: roots)
            == [.roots])
        #expect(CloudEvents.classify(path: root.path, flags: flags(dir, kFSEventStreamEventFlagItemXattrMod), roots: roots)
            .isEmpty)
        #expect(CloudEvents.classify(path: "/Users/someone/Elsewhere/a.txt", flags: flags(file), roots: roots).isEmpty)
        // A sibling whose name starts like the root's is not in it.
        #expect(CloudEvents.classify(path: root.path + "-Old/a.txt", flags: flags(file), roots: roots).isEmpty)
        // Links are not followed.
        #expect(CloudEvents.classify(path: p("link"), flags: flags(kFSEventStreamEventFlagItemIsSymlink), roots: roots)
            .isEmpty)
    }

    @Test func eventPathsAreResolvedButItemsKeepTheRootsSpelling() {
        // FSEvents reports real paths (/private/var for /var); the items
        // keep the place's spelling, so a walk and an event name one item once.
        let spelled = URL(fileURLWithPath: "/var/folders/someone/Cloud")
        let mapped = CloudRoots(pairs: [(real: "/private/var/folders/someone/Cloud", root: spelled)])
        #expect(CloudEvents.classify(path: "/private/var/folders/someone/Cloud/a.txt", flags: flags(file), roots: mapped)
            == [.read(URL(fileURLWithPath: "/var/folders/someone/Cloud/a.txt"), root: spelled)])
        // The public init resolves the links itself, the way FSEvents does:
        // /var/folders/… is /private/var/folders/….
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let real = CloudRoots([tmp])
        #expect(CloudRoots.realPath(tmp).hasPrefix("/private/var/"))
        #expect(real.root(of: CloudRoots.realPath(tmp) + "/x")?.root == tmp)
        #expect(real.root(of: CloudRoots.realPath(tmp) + "/x")?.relative == "x")
    }
}

struct CloudEventBatchTests {
    private func read(_ r: String) -> CloudEvent { .read(URL(fileURLWithPath: p(r)), root: root) }

    @Test func coalescesByPathInArrivalOrder() {
        var batch = CloudEventBatch()
        batch.add(read("a.txt"))
        batch.add(read("b.txt"))
        batch.add(read("a.txt"))
        #expect(batch.count == 2)
        #expect(batch.take(10) == [read("a.txt"), read("b.txt")])
        #expect(batch.isEmpty)
    }

    @Test func aReadNeverReplacesAWalk() {
        var batch = CloudEventBatch()
        let folder = URL(fileURLWithPath: p("New"))
        batch.add(.expand(folder, root: root))
        batch.add(.read(folder, root: root))
        #expect(batch.take(10) == [.expand(folder, root: root)])
        batch.add(.expand(folder, root: root))
        batch.add(.gone(folder, root: root))
        #expect(batch.take(10) == [.gone(folder, root: root)])
        batch.add(.rescan(folder, root: root))
        batch.add(.expand(folder, root: root))
        #expect(batch.take(10) == [.rescan(folder, root: root)])
    }

    @Test func takesAtMostWhatItsAskedFor() {
        var batch = CloudEventBatch()
        for i in 0..<10 { batch.add(read("\(i).txt")) }
        #expect(batch.take(4) == (0..<4).map { read("\($0).txt") })
        batch.add(read("0.txt"))
        #expect(batch.take(100) == (4..<10).map { read("\($0).txt") } + [read("0.txt")])
    }

    @Test func theRootsChangingIsOneFlag() {
        var batch = CloudEventBatch()
        batch.add(.roots)
        batch.add(.roots)
        #expect(batch.count == 0)
        #expect(batch.rootsChanged)
        #expect(!batch.isEmpty)
        _ = batch.take(10)
        #expect(!batch.rootsChanged)
        #expect(batch.isEmpty)
    }

    @Test func aBurstOfThousandsCollapsesIntoOneWalkOfTheRoot() {
        // Unzipping 50,000 files into OneDrive: the batch never holds more
        // than its limit, and what's left to do is one walk of the root.
        var batch = CloudEventBatch()
        let icloud = CloudEvent.read(other.appendingPathComponent("kept.txt"), root: other)
        batch.add(icloud)
        for i in 0..<50_000 { batch.add(read("Big/\(i).txt")) }
        #expect(batch.count <= CloudEventBatch.limit)
        let all = batch.take(.max)
        #expect(all.contains(icloud))
        #expect(all.contains(.rescan(root, root: root)))
        #expect(all.filter { if case .read(_, let r) = $0 { return r == root } else { return false } }.count
            < CloudEventBatch.limit)
        #expect(CloudEventBatch.limit == 10_000)
    }
}

struct CloudPendingContainsTests {
    @Test func saysWhetherAnItemIsKept() {
        var pending = CloudPending()
        let a = URL(fileURLWithPath: p("a.txt"))
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(!pending.contains(a))
        pending.update(a, root: root, state: .uploading, at: t0)
        #expect(pending.contains(a))
        #expect(pending.contains(URL(fileURLWithPath: p("Notes/../a.txt"))))
        pending.settle(a)
        #expect(!pending.contains(a))
    }
}
