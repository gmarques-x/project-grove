import Foundation
import GroveThemesCore
import Testing
@testable import GroveKeysCore

// Invented paths and names only (the repo is public).
private let home = URL(fileURLWithPath: "/Users/someone")
private let iCloud = CloudProviders.iCloudDrivePlace(home: home)
private let oneDrive = CloudProviders.place(
    "OneDrive-Personal", CloudProviders.provider(folderName: "OneDrive-Personal")!, home: home)
private let dropbox = CloudProviders.place(
    "Dropbox", CloudProviders.provider(folderName: "Dropbox")!, home: home)
private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func values(
    ubiquitous: Bool = true, directory: Bool = false, uploading: Bool = false, uploaded: Bool = true,
    downloading: Bool = false, status: CloudItemValues.DownloadingStatus? = .current,
    uploadError: String? = nil, downloadError: String? = nil, conflicts: Bool = false
) -> CloudItemValues {
    CloudItemValues(
        isUbiquitous: ubiquitous, isDirectory: directory, isUploading: uploading, isUploaded: uploaded,
        isDownloading: downloading, downloadingStatus: status, uploadError: uploadError,
        downloadError: downloadError, hasConflicts: conflicts)
}

private func file(_ place: CloudProviders.CloudPlace, _ relative: String) -> URL {
    place.url.appendingPathComponent(relative)
}

struct CloudItemStateTests {
    @Test func aSyncedFileIsSettled() {
        #expect(CloudItemState(values()) == .settled)
        #expect(CloudItemState(values(ubiquitous: false, uploaded: false, status: nil)) == .settled)
    }

    @Test func uploadingAndNotYetUploadedArePending() {
        #expect(CloudItemState(values(uploading: true, uploaded: false)) == .uploading)
        #expect(CloudItemState(values(uploaded: false)) == .notUploaded)
        // Not ubiquitous: "not uploaded" means nothing.
        #expect(CloudItemState(values(ubiquitous: false, uploaded: false)) == .settled)
        #expect(CloudItemState(values(uploading: true, uploaded: false)).isPending)
        #expect(CloudItemState(values(uploaded: false)).isPending)
    }

    @Test func onlyADownloadUnderWayIsPending() {
        #expect(CloudItemState(values(downloading: true, status: .notDownloaded)) == .downloading)
        #expect(CloudItemState(values(downloading: true)).isPending)
        // Online-only is normal, and a newer version on the server not being
        // fetched isn't pending either.
        #expect(CloudItemState(values(status: .notDownloaded)) == .settled)
        #expect(CloudItemState(values(status: .downloaded)) == .settled)
    }

    @Test func errorsAndConflictsAreProblems() {
        #expect(CloudItemState(values(uploading: true, uploadError: "Upload failed")) == .problem("Upload failed"))
        #expect(CloudItemState(values(downloadError: "Download failed")) == .problem("Download failed"))
        #expect(CloudItemState(values(conflicts: true)) == .problem("unresolved conflict"))
        #expect(CloudItemState(values(conflicts: true)).isProblem)
        #expect(!CloudItemState(values(conflicts: true)).isPending)
        // An empty message still says something.
        #expect(CloudItemState(values(uploadError: "")) == .problem("couldn't upload"))
        #expect(CloudItemState(values(downloadError: " ")) == .problem("couldn't download"))
    }

    @Test func foldersNeverCount() {
        #expect(CloudItemState(values(directory: true, uploading: true, uploaded: false)) == .settled)
        #expect(CloudItemState(values(directory: true, downloading: true)) == .settled)
        #expect(CloudItemState(values(directory: true, uploadError: "x")) == .settled)
    }

    @Test func readsAPlainFileFreshAsSettled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("note.txt").path
        try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        let read = try CloudItemValues.read(path: path)
        #expect(read.isUbiquitous == false)
        #expect(read.isDirectory == false)
        #expect(CloudItemState(read) == .settled)
        #expect(try CloudItemValues.read(path: dir.path).isDirectory)
        #expect(throws: (any Error).self) { try CloudItemValues.read(path: dir.appendingPathComponent("gone").path) }
    }

    @Test func readsEveryKeyItNeeds() {
        let keys = CloudItemValues.keys
        for key: URLResourceKey in [.isUbiquitousItemKey, .isDirectoryKey, .ubiquitousItemIsUploadingKey,
                                    .ubiquitousItemIsUploadedKey, .ubiquitousItemIsDownloadingKey,
                                    .ubiquitousItemDownloadingStatusKey, .ubiquitousItemUploadingErrorKey,
                                    .ubiquitousItemDownloadingErrorKey, .ubiquitousItemHasUnresolvedConflictsKey] {
            #expect(keys.contains(key))
        }
    }
}

struct CloudIgnoreTests {
    @Test(arguments: [".DS_Store", "._Report.pages", "._", "build.nosync", "~$Budget.xlsx", "~$", "draft.tmp",
                      "DRAFT.TMP", "cache.NoSync"])
    func ignored(_ name: String) {
        #expect(CloudIgnore.ignores(name: name))
    }

    @Test(arguments: ["Report.pages", "notes.txt", "tmp", "nosync", "a.tmp.txt", ".txt.bak",
                      "DS_Store", "x~$y", ".ds_store2"])
    func kept(_ name: String) {
        #expect(!CloudIgnore.ignores(name: name))
    }

    @Test func anythingInsideANosyncFolderIsIgnored() {
        let root = oneDrive.url
        #expect(CloudIgnore.ignores(root.appendingPathComponent("Code/app.nosync/lib/index.js"), root: root))
        #expect(CloudIgnore.ignores(root.appendingPathComponent("Docs/.DS_Store"), root: root))
        #expect(!CloudIgnore.ignores(root.appendingPathComponent("Docs/plan.txt"), root: root))
        // Only the part below the root is looked at.
        let odd = URL(fileURLWithPath: "/tmp/x.nosync/root")
        #expect(!CloudIgnore.ignores(odd.appendingPathComponent("plan.txt"), root: odd))
    }
}

/// `expire` outside `#expect` (the macro can't mutate).
private func expired(_ pending: inout CloudPending, _ now: Date) -> Bool { pending.expire(at: now) }

struct CloudPendingTests {
    @Test func settledItemsNeverJoinAndLeaveWhenTheySettle() {
        var pending = CloudPending()
        let a = file(oneDrive, "Docs/a.txt")
        pending.update(a, root: oneDrive.url, state: .settled, at: t0)
        #expect(pending.count == 0)
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0)
        #expect(pending.count == 1)
        #expect(pending.entries.map(\.state) == [.uploading])
        pending.update(a, root: oneDrive.url, state: .settled, at: t0 + 5)
        #expect(pending.count == 0)
        // settle: the item is gone (deleted, or now ignored).
        pending.update(a, root: oneDrive.url, state: .notUploaded, at: t0 + 6)
        pending.settle(a)
        #expect(pending.isEmpty)
    }

    @Test func problemsStayInTheSet() {
        var pending = CloudPending()
        let a = file(iCloud, "a.txt")
        pending.update(a, root: iCloud.url, state: .problem("Upload failed"), at: t0)
        #expect(pending.entries.map(\.state) == [.problem("Upload failed")])
        #expect(pending.pendingCount == 0)
    }

    @Test func rereadsEvery5SecondsFor2MinutesThenEvery60() {
        var pending = CloudPending()
        let a = file(oneDrive, "a.txt")
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0)
        #expect(pending.due(at: t0 + 4.9).isEmpty)
        #expect(pending.due(at: t0 + 5) == [a])
        #expect(pending.nextRead == t0 + 5)
        // Re-read with no change, up to the 2 minutes: still every 5 s.
        var now = t0
        while now < t0 + 115 {
            now += 5
            pending.update(a, root: oneDrive.url, state: .uploading, at: now)
        }
        #expect(pending.nextRead == now + 5)
        // Past 2 minutes without a change: every 60 s.
        now = t0 + 120
        pending.update(a, root: oneDrive.url, state: .uploading, at: now)
        #expect(pending.nextRead == now + 60)
        #expect(pending.due(at: now + 59).isEmpty)
        #expect(pending.due(at: now + 60) == [a])
        // A change starts the 5 s reads again.
        pending.update(a, root: oneDrive.url, state: .notUploaded, at: now + 60)
        #expect(pending.nextRead == now + 65)
        #expect(CloudPending.fastInterval == 5 && CloudPending.fastPeriod == 120 && CloudPending.slowInterval == 60)
    }

    @Test func dueIsInPathOrderAndEmptyHasNoNextRead() {
        var pending = CloudPending()
        #expect(pending.nextRead == nil)
        let b = file(oneDrive, "b.txt"), a = file(oneDrive, "a.txt")
        pending.update(b, root: oneDrive.url, state: .uploading, at: t0)
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0 + 1)
        #expect(pending.due(at: t0 + 10) == [a, b])
        #expect(pending.nextRead == t0 + 5)
    }

    @Test func pending30MinutesWithNoChangeIsAProblem() {
        var pending = CloudPending()
        let a = file(oneDrive, "a.txt"), b = file(oneDrive, "b.txt")
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0)
        pending.update(b, root: oneDrive.url, state: .uploading, at: t0 + 600)
        var now = t0
        while now < t0 + 1790 {
            now += 60
            pending.update(a, root: oneDrive.url, state: .uploading, at: min(now, t0 + 1799))
        }
        #expect(!expired(&pending, t0 + 1799))
        #expect(pending.entries.map(\.state) == [.uploading, .uploading])
        #expect(expired(&pending, t0 + 1800))
        #expect(pending.entries.map(\.state) == [.problem("not uploading for 30 min"), .uploading])
        #expect(CloudPending.stuckMessage == "not uploading for 30 min")
        #expect(pending.pendingCount == 1)
        // Nothing more to expire: no change.
        #expect(!expired(&pending, t0 + 1801))
        // Re-read the same: still stuck (the next 60 s read doesn't clear it).
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0 + 1860)
        #expect(pending.entries.first?.state == .problem("not uploading for 30 min"))
        // It moves: no longer stuck.
        pending.update(a, root: oneDrive.url, state: .notUploaded, at: t0 + 1900)
        #expect(pending.entries.first?.state == .notUploaded)
        // It settles: gone.
        pending.update(a, root: oneDrive.url, state: .settled, at: t0 + 1960)
        #expect(pending.entries.map(\.url) == [b])
    }

    @Test func aStuckDownloadSaysNotDownloading() {
        var pending = CloudPending()
        let d = file(iCloud, "d.txt"), n = file(iCloud, "n.txt")
        pending.update(d, root: iCloud.url, state: .downloading, at: t0)
        pending.update(n, root: iCloud.url, state: .notUploaded, at: t0)
        #expect(expired(&pending, t0 + 1800))
        #expect(pending.entries.map(\.state)
            == [.problem("not downloading for 30 min"), .problem("not uploading for 30 min")])
        #expect(CloudPending.stuckDownloadMessage == "not downloading for 30 min")
    }

    @Test func aFileEventWithTheSameStateIsNoChange() {
        // A provider rewriting an item's metadata makes file events while
        // the upload stays stuck: only a different state is a change.
        var pending = CloudPending()
        let a = file(oneDrive, "a.txt")
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0)
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0 + 1000)
        #expect(expired(&pending, t0 + 1800))
        pending.update(a, root: oneDrive.url, state: .uploading, at: t0 + 1900)
        #expect(pending.entries.first?.state == .problem(CloudPending.stuckMessage))
        // A different state is.
        pending.update(a, root: oneDrive.url, state: .notUploaded, at: t0 + 2000)
        #expect(pending.entries.first?.state == .notUploaded)
        #expect(pending.nextRead == t0 + 2005)
    }

    @Test func aProblemFromTheProviderNeverExpires() {
        var pending = CloudPending()
        let a = file(oneDrive, "a.txt")
        pending.update(a, root: oneDrive.url, state: .problem("Upload failed"), at: t0)
        #expect(!expired(&pending, t0 + 7200))
        #expect(pending.entries.first?.state == .problem("Upload failed"))
    }

    @Test func cappedAt2000() {
        var pending = CloudPending()
        for n in 0..<CloudPending.cap {
            pending.update(file(oneDrive, "f\(n).txt"), root: oneDrive.url, state: .uploading, at: t0)
        }
        #expect(pending.count == 2000)
        #expect(!pending.overflowed)
        pending.update(file(oneDrive, "one-more.txt"), root: oneDrive.url, state: .uploading, at: t0)
        #expect(pending.count == 2000)
        #expect(pending.overflowed)
        // Ones already in still update.
        pending.update(file(oneDrive, "f0.txt"), root: oneDrive.url, state: .notUploaded, at: t0 + 1)
        #expect(pending.entries.first(where: { $0.url.lastPathComponent == "f0.txt" })?.state == .notUploaded)
        // Room again: still over, the dropped file was never kept; only a
        // re-walk of its root clears it.
        pending.update(file(oneDrive, "f0.txt"), root: oneDrive.url, state: .settled, at: t0 + 2)
        #expect(pending.overflowed)
        #expect(pending.rootsNeedingRescan == [oneDrive.url])
        #expect(pending.hasRoom)
        pending.rescanned(root: oneDrive.url)
        #expect(!pending.overflowed)
        #expect(pending.rootsNeedingRescan.isEmpty)
        #expect(CloudPillState.syncing(CloudPending.cap + 1).countText == "2000+")
        #expect(CloudPillState.syncing(2000).countText == "2000")
    }

    @Test func overflowIsKeptPerRoot() {
        var pending = CloudPending()
        for n in 0..<CloudPending.cap {
            pending.update(file(oneDrive, "f\(n).txt"), root: oneDrive.url, state: .uploading, at: t0)
        }
        pending.update(file(iCloud, "dropped.txt"), root: iCloud.url, state: .uploading, at: t0)
        #expect(pending.rootsNeedingRescan == [iCloud.url])
        #expect(pending.needsRescan(iCloud.url))
        #expect(!pending.needsRescan(oneDrive.url))
        #expect(!pending.hasRoom)
        // Re-walking another root clears nothing.
        pending.rescanned(root: oneDrive.url)
        #expect(pending.rootsNeedingRescan == [iCloud.url])
        // A vanished root takes its flag with it.
        pending.removeRoot(iCloud.url)
        #expect(pending.rootsNeedingRescan.isEmpty)
        pending.update(file(iCloud, "dropped.txt"), root: iCloud.url, state: .uploading, at: t0)
        pending.retainRoots([oneDrive.url])
        #expect(pending.rootsNeedingRescan.isEmpty)
    }

    @Test func aVanishedProviderDropsItsItems() {
        var pending = CloudPending()
        pending.update(file(iCloud, "a.txt"), root: iCloud.url, state: .uploading, at: t0)
        pending.update(file(oneDrive, "b.txt"), root: oneDrive.url, state: .problem("Upload failed"), at: t0)
        pending.update(file(oneDrive, "c.txt"), root: oneDrive.url, state: .uploading, at: t0)
        pending.retainRoots([iCloud.url])
        #expect(pending.entries.map(\.url) == [file(iCloud, "a.txt")])
        pending.update(file(oneDrive, "c.txt"), root: oneDrive.url, state: .uploading, at: t0)
        pending.removeRoot(oneDrive.url)
        #expect(pending.entries.map(\.url) == [file(iCloud, "a.txt")])
    }
}

struct CloudSummaryTests {
    private func summary(
        _ pending: CloudPending, places: [CloudProviders.CloudPlace] = [iCloud, oneDrive],
        access: [String: CloudProviderAccess] = [:], firstPassDone: Bool = true
    ) -> CloudSummary {
        CloudSummary(places: places, pending: pending, access: { access[$0.url.path] ?? .ok }, firstPassDone: firstPassDone)
    }

    @Test func nothingPendingIsSynced() {
        let s = summary(CloudPending())
        #expect(s.pill == .synced)
        #expect(s.providers.map(\.statusLine) == ["Up to date", "Up to date"])
        #expect(s.providers.map(\.place) == [iCloud, oneDrive])
        #expect(s.providers.map(\.id) == [iCloud.url.path, oneDrive.url.path])
        #expect(s.providers.allSatisfy { $0.rows.isEmpty })
    }

    @Test func checkingUntilTheFirstPassIsDone() {
        var pending = CloudPending()
        pending.update(file(iCloud, "a.txt"), root: iCloud.url, state: .problem("x"), at: t0)
        #expect(summary(pending, firstPassDone: false).pill == .checking)
        #expect(summary(CloudPending(), firstPassDone: false).pill == .checking)
    }

    @Test func pendingFilesAreSyncingWithTheirCount() {
        var pending = CloudPending()
        for n in 0..<3 { pending.update(file(oneDrive, "u\(n).txt"), root: oneDrive.url, state: .uploading, at: t0) }
        pending.update(file(oneDrive, "n.txt"), root: oneDrive.url, state: .notUploaded, at: t0)
        pending.update(file(iCloud, "d.txt"), root: iCloud.url, state: .downloading, at: t0)
        let s = summary(pending)
        #expect(s.pill == .syncing(5))
        #expect(s.count == 5)
        #expect(s.providers.map(\.statusLine) == ["Downloading 1 file", "Uploading 4 files"])
        #expect(s.providers.map(\.uploading) == [0, 4])
        #expect(s.providers.map(\.downloading) == [1, 0])
    }

    @Test func overTheCapCountsAs2000Plus() {
        var pending = CloudPending()
        for n in 0...CloudPending.cap {
            pending.update(file(oneDrive, "f\(n).txt"), root: oneDrive.url, state: .uploading, at: t0)
        }
        let s = summary(pending)
        #expect(s.pill == .syncing(2001))
        #expect(s.pill.line == "syncing 2000+")
    }

    @Test func afterAnOverflowItIsNeverSyncedUntilRescanned() {
        var pending = CloudPending()
        for n in 0...CloudPending.cap {
            pending.update(file(oneDrive, "f\(n).txt"), root: oneDrive.url, state: .uploading, at: t0)
        }
        // Draining below the cap: the dropped one may still be pending.
        pending.settle(file(oneDrive, "f0.txt"))
        #expect(summary(pending).pill == .checking)
        #expect(summary(pending).providers.last?.needsRescan == true)
        // Drained to nothing: still not synced.
        for n in 1..<CloudPending.cap { pending.settle(file(oneDrive, "f\(n).txt")) }
        #expect(pending.isEmpty)
        #expect(summary(pending).pill == .checking)
        // The root re-walked: synced.
        pending.rescanned(root: oneDrive.url)
        #expect(summary(pending).pill == .synced)
        #expect(summary(pending).providers.last?.needsRescan == false)
    }

    @Test func aProviderItCantSeeDoesntHoldThePillOverTheCap() {
        var pending = CloudPending()
        for n in 0...CloudPending.cap {
            pending.update(file(oneDrive, "f\(n).txt"), root: oneDrive.url, state: .uploading, at: t0)
        }
        let s = summary(pending, access: [oneDrive.url.path: .cantSee])
        #expect(s.pill == .synced)
        #expect(s.pill.line == "synced")
        // A visible root over the cap while the set is under it: checking.
        var other = CloudPending()
        for n in 0..<CloudPending.cap {
            other.update(file(oneDrive, "f\(n).txt"), root: oneDrive.url, state: .uploading, at: t0)
        }
        other.update(file(iCloud, "dropped.txt"), root: iCloud.url, state: .uploading, at: t0)
        #expect(summary(other).pill == .syncing(2001))
        #expect(summary(other, access: [oneDrive.url.path: .cantSee]).pill == .checking)
    }

    @Test func aProblemAnywhereIsAProblem() {
        var pending = CloudPending()
        pending.update(file(oneDrive, "u.txt"), root: oneDrive.url, state: .uploading, at: t0)
        pending.update(file(iCloud, "p.txt"), root: iCloud.url, state: .problem("Upload failed"), at: t0)
        let s = summary(pending)
        #expect(s.pill == .problem)
        #expect(s.count == 1)
        #expect(s.providers.map(\.statusLine) == ["1 problem", "Uploading 1 file"])
        pending.update(file(iCloud, "q.txt"), root: iCloud.url, state: .problem("Upload failed"), at: t0)
        pending.update(file(iCloud, "r.txt"), root: iCloud.url, state: .uploading, at: t0)
        // Worst first: the problems, not the uploads.
        #expect(summary(pending).providers.first?.statusLine == "2 problems")
        #expect(summary(pending).providers.first?.problems == 2)
    }

    @Test func notRunningIsAProblemAndSaysSo() {
        let s = summary(CloudPending(), access: [oneDrive.url.path: .notRunning])
        #expect(s.pill == .problem)
        #expect(s.providers.map(\.statusLine) == ["Up to date", "OneDrive isn't running"])
        let other = CloudProviders.place(
            "OneDrive-Contoso", CloudProviders.provider(folderName: "OneDrive-Contoso")!, home: home)
        #expect(summary(CloudPending(), places: [other], access: [other.url.path: .notRunning]).providers.first?.statusLine
            == "OneDrive isn't running")
    }

    @Test func aProviderItCantSeeIsLeftOutOfThePill() {
        var pending = CloudPending()
        pending.update(file(oneDrive, "p.txt"), root: oneDrive.url, state: .problem("x"), at: t0)
        pending.update(file(oneDrive, "u.txt"), root: oneDrive.url, state: .uploading, at: t0)
        let s = summary(pending, access: [oneDrive.url.path: .cantSee])
        #expect(s.pill == .synced)
        #expect(s.providers.last?.statusLine == "Grove Keys can't see OneDrive's files")
        #expect(s.providers.last?.rows.isEmpty == true)
    }

    @Test func aVanishedProviderLeavesNoSectionOrProblem() {
        var pending = CloudPending()
        pending.update(file(oneDrive, "p.txt"), root: oneDrive.url, state: .problem("Upload failed"), at: t0)
        pending.update(file(oneDrive, "u.txt"), root: oneDrive.url, state: .uploading, at: t0)
        // OneDrive's folder is gone (signed out): only iCloud is listed.
        let s = summary(pending, places: [iCloud])
        #expect(s.providers.map(\.place) == [iCloud])
        #expect(s.pill == .synced)
        #expect(s.count == 0)
    }

    @Test func fiveRowsProblemsFirstThenTheMostRecentInIdOrder() {
        var pending = CloudPending()
        // Older pending files, then newer ones, then two problems.
        for (n, name) in ["e", "d", "c", "b", "a", "f"].enumerated() {
            pending.update(file(oneDrive, "Docs/\(name).txt"), root: oneDrive.url, state: .uploading,
                           at: t0 + TimeInterval(n))
        }
        pending.update(file(oneDrive, "z.txt"), root: oneDrive.url, state: .problem("Upload failed"), at: t0)
        pending.update(file(oneDrive, "y.txt"), root: oneDrive.url, state: .problem("Upload failed"), at: t0 + 1)
        let rows = summary(pending).providers.last!.rows
        #expect(rows.count == 5)
        // Problems first (by id), then the three newest pending (a, b, f), by id.
        #expect(rows.map(\.name) == ["y.txt", "z.txt", "a.txt", "b.txt", "f.txt"])
        #expect(rows.map(\.problem) == ["Upload failed", "Upload failed", nil, nil, nil])
        #expect(rows.map(\.folder) == ["OneDrive", "OneDrive", "Docs", "Docs", "Docs"])
        #expect(rows.first?.id == file(oneDrive, "y.txt").path)
        #expect(CloudProviderSummary.rowLimit == 5)

        // A shown row changing state (and its problem's words changing)
        // doesn't move any row, nor does a hidden one changing pull it in.
        pending.update(file(oneDrive, "Docs/e.txt"), root: oneDrive.url, state: .notUploaded, at: t0 + 100)
        pending.update(file(oneDrive, "Docs/a.txt"), root: oneDrive.url, state: .notUploaded, at: t0 + 100)
        pending.update(file(oneDrive, "Docs/b.txt"), root: oneDrive.url, state: .downloading, at: t0 + 100)
        pending.update(file(oneDrive, "z.txt"), root: oneDrive.url, state: .problem("Disk full"), at: t0 + 100)
        let after = summary(pending).providers.last!.rows
        #expect(after.map(\.id) == rows.map(\.id))
        #expect(after.map(\.state)
            == [.problem("Upload failed"), .problem("Disk full"), .notUploaded, .downloading, .uploading])
    }

    @Test func aStuckRowSaysSo() {
        var pending = CloudPending()
        pending.update(file(iCloud, "Notes/x.txt"), root: iCloud.url, state: .uploading, at: t0)
        pending.expire(at: t0 + 1800)
        let row = summary(pending).providers.first!.rows.first!
        #expect(row.problem == "not uploading for 30 min")
        #expect(row.folder == "Notes")
        #expect(row.url == file(iCloud, "Notes/x.txt"))
    }

    @Test func providerApps() {
        #expect(CloudProviderSummary.bundleID(for: oneDrive) == "com.microsoft.OneDrive")
        #expect(CloudProviderSummary.bundleID(for: iCloud) == nil)
        #expect(CloudProviderSummary.bundleID(for: dropbox) == nil)
        let work = CloudProviders.place(
            "OneDrive-Contoso", CloudProviders.provider(folderName: "OneDrive-Contoso")!, home: home)
        #expect(CloudProviderSummary.bundleID(for: work) == "com.microsoft.OneDrive")
        // The folder says who the provider is, not the words shown.
        let renamed = CloudProviders.CloudPlace(
            url: home.appendingPathComponent("Library/CloudStorage/Box-OneDrive"), title: "OneDrive",
            kind: .provider("OneDrive"))
        #expect(CloudProviderSummary.bundleID(for: renamed) == nil)
        let elsewhere = CloudProviders.CloudPlace(
            url: home.appendingPathComponent("Documents/OneDrive-Personal"), title: "OneDrive",
            kind: .provider("OneDrive"))
        #expect(CloudProviderSummary.bundleID(for: elsewhere) == nil)
        #expect(CloudProviderSummary.hasSettings(oneDrive))
        #expect(CloudProviderSummary.hasSettings(iCloud))
        #expect(!CloudProviderSummary.hasSettings(dropbox))
        #expect(CloudProviderSummary.name(of: iCloud) == "iCloud Drive")
        #expect(CloudProviderSummary.name(of: oneDrive) == "OneDrive")
    }
}

struct CloudWordsTests {
    @Test(arguments: [
        (0, 0, 0, "Up to date"), (3, 1, 0, "Uploading 3 files · Downloading 1"), (1, 0, 0, "Uploading 1 file"),
        (0, 2, 0, "Downloading 2 files"), (0, 1, 0, "Downloading 1 file"), (1, 1, 0, "Uploading 1 file · Downloading 1"),
        (3, 1, 1, "1 problem"), (0, 0, 4, "4 problems"),
    ])
    func statusLine(_ uploading: Int, _ downloading: Int, _ problems: Int, _ line: String) {
        #expect(CloudWords.status(uploading: uploading, downloading: downloading, problems: problems) == line)
    }

    @Test func copy() {
        #expect(CloudWords.notRunning("OneDrive") == "OneDrive isn't running")
        #expect(CloudWords.cantSee("OneDrive") == "Grove Keys can't see OneDrive's files")
        #expect(CloudWords.openInExplorer == "Open in Grove Explorer")
        #expect(CloudWords.settings == "Settings…")
        #expect(CloudWords.oneDriveSettingsFallback == "Open OneDrive's settings from its activity window")
    }

    @Test func pillLines() {
        #expect(CloudPillState.checking.line == "checking")
        #expect(CloudPillState.synced.line == "synced")
        #expect(CloudPillState.syncing(12).line == "syncing 12")
        #expect(CloudPillState.problem.line == "problem")
        #expect(CloudPillState.syncing(0).countText == "0")
    }

    @Test func links() {
        #expect(CloudLinks.explorer(URL(fileURLWithPath: "/Users/someone/My Docs/a&b=c+d#e?.txt")).absoluteString
            == "groveexplorer://open?path=%2FUsers%2Fsomeone%2FMy%20Docs%2Fa%26b%3Dc%2Bd%23e%3F.txt")
        #expect(CloudLinks.iCloudSettings.absoluteString
            == "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")
        // Round trip through URLComponents, as Grove Explorer reads it.
        let link = CloudLinks.explorer(URL(fileURLWithPath: "/tmp/ä ö/x%y.txt"))
        let path = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        #expect(path == "/tmp/ä ö/x%y.txt")
    }

    @Test func placesAreICloudFirstThenEachProvider() {
        let places = CloudSummary.places(iCloudPresent: true, cloudStorage: ["OneDrive-Personal", ".hidden", "Dropbox"],
                                         home: home)
        #expect(places.map(\.title) == ["iCloud Drive", "Dropbox", "OneDrive"])
        #expect(CloudSummary.places(iCloudPresent: false, cloudStorage: [], home: home).isEmpty)
    }
}

struct CloudBarFileTests {
    @Test func pathIsBesideTheOtherState() {
        #expect(CloudBarFile.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/cloud")
        #expect(CloudBarFile.url(environment: [:], home: home).path == "/Users/someone/.local/state/grove/cloud")
    }

    @Test func writesOnlyWhenTheStateChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = CloudBarFile.url(environment: ["GROVE_STATE": dir.path], home: URL(fileURLWithPath: "/nowhere"))

        #expect(try CloudBarFile.update(.checking, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "checking\n")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.02)
        #expect(try !CloudBarFile.update(.checking, at: url))
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)
        #expect(try CloudBarFile.update(.syncing(3), at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "syncing 3\n")
        #expect(try !CloudBarFile.update(.syncing(3), at: url))
        #expect(try CloudBarFile.update(.syncing(2001), at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "syncing 2000+\n")
        #expect(try CloudBarFile.update(.problem, at: url))
        #expect(try CloudBarFile.update(.synced, at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "synced\n")
        // nil removes it (Grove Keys stopped); already gone is no change.
        #expect(try CloudBarFile.update(nil, at: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try !CloudBarFile.update(nil, at: url))
    }
}
