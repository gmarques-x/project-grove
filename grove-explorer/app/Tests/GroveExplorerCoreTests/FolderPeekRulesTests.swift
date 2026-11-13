import Foundation
import GroveExplorerCore
import Testing

/// Which folders are looked into, and which answers a new listing makes
/// out of date (in memory: nothing on disk).
@Suite struct FolderPeekRulesTests {
    private func entry(_ path: String, _ kind: Entry.Kind = .folder, modified: Double = 0) -> Entry {
        let url = URL(fileURLWithPath: path, isDirectory: kind == .folder)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: nil, modified: Date(timeIntervalSince1970: modified),
            isHidden: false, typeDescription: "")
    }

    private func row(_ entry: Entry, depth: Int = 0, fold: TreeRow.Fold = .none) -> TreeItem {
        .row(TreeRow(entry: entry, depth: depth, fold: fold, isContext: false))
    }

    @Test func theClosedFoldersOfTheRowsNotYetLookedIntoInRowOrder() {
        let items: [TreeItem] = [
            row(entry("/t/b")), row(entry("/t/a"), fold: .open), row(entry("/t/a/x"), depth: 1),
            row(entry("/t/a/y"), depth: 1, fold: .closed), row(entry("/t/c"), fold: .loading),
            .loading(under: URL(fileURLWithPath: "/t/c"), depth: 1), row(entry("/t/App.app", .package)),
            row(entry("/t/L", .symlink(toFolder: true))), row(entry("/t/f.txt", .file)),
        ]
        // An open folder's chevron is its listing's; y was looked into
        // already (however its key is spelled).
        let wanted = FolderPeek.wanted(items, known: [URL(fileURLWithPath: "/t/a/y/"): true])
        #expect(wanted.map(\.path) == ["/t/b", "/t/a/x"])
    }

    @Test func anAnswerGoesWhenItsFolderChangedOrWent() {
        let old = [entry("/t/same", modified: 1), entry("/t/written", modified: 1), entry("/t/gone"),
            entry("/t/now-a-file", modified: 1), entry("/t/f.txt", .file)]
        let new = [entry("/t/same", modified: 1), entry("/t/written", modified: 2), entry("/t/now-a-file", .file, modified: 1),
            entry("/t/new"), entry("/t/f.txt", .file, modified: 5)]
        let outdated = FolderPeek.outdated(old: old, new: new)
        #expect(Set(outdated.map(\.path)) == ["/t/written", "/t/gone", "/t/now-a-file"])
    }
}
