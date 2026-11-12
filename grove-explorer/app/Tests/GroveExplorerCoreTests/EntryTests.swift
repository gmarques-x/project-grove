import Foundation
import GroveExplorerCore
import Testing

@Suite struct EntryTests {
    private func entry(_ path: String, kind: Entry.Kind = .file, size: Int64? = 3) -> Entry {
        let url = URL(fileURLWithPath: path)
        return Entry(
            url: url, name: url.lastPathComponent, kind: kind, size: size,
            modified: Date(timeIntervalSince1970: 1_000), isHidden: false, typeDescription: "Document"
        )
    }

    /// An entry is identified by where it is: a list keeps its selection by URL.
    @Test func idIsTheURL() {
        let notes = entry("/tmp/grove/notes.md")
        #expect(notes.id == URL(fileURLWithPath: "/tmp/grove/notes.md"))
        #expect(notes.name == "notes.md")
    }

    @Test func equalWhenEveryFieldIs() {
        #expect(entry("/tmp/a.txt") == entry("/tmp/a.txt"))
        #expect(entry("/tmp/a.txt") != entry("/tmp/b.txt"))
        #expect(entry("/tmp/a.txt") != entry("/tmp/a.txt", size: 4))
        #expect(Set([entry("/tmp/a.txt"), entry("/tmp/a.txt"), entry("/tmp/b.txt")]).count == 2)
    }

    /// A link to a folder and a link to a file are different kinds, and
    /// neither is the folder or the file it points at.
    @Test func aSymlinkSaysWhatItPointsAt() {
        #expect(Entry.Kind.symlink(toFolder: true) != .symlink(toFolder: false))
        #expect(Entry.Kind.symlink(toFolder: true) != .folder)
        #expect(entry("/tmp/link", kind: .symlink(toFolder: true)) != entry("/tmp/link", kind: .folder))
    }
}
