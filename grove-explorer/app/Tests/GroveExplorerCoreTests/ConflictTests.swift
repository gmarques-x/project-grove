import Foundation
@testable import GroveExplorerCore
import Testing

@Suite struct ConflictTests {
    /// `taken` as a volume that ignores case and the form of accents has it.
    private func taken(_ names: String...) -> (String) -> Bool {
        { name in names.contains { Conflict.sameName($0, name, caseSensitive: false) } }
    }

    // MARK: Free names

    @Test func theFirstFreeNameIsTheName2() {
        #expect(Conflict.freeName(for: "notes.md") { _ in false } == "notes 2.md")
        #expect(Conflict.freeName(for: "docs") { _ in false } == "docs 2")
        #expect(Conflict.freeName(for: "archive.tar.gz") { _ in false } == "archive 2.tar.gz")
    }

    @Test func takenNumbersAreSkipped() {
        #expect(Conflict.freeName(for: "notes.md") { $0 == "notes 2.md" } == "notes 3.md")
        let many = Set((2...40).map { "notes \($0).md" })
        #expect(Conflict.freeName(for: "notes.md", taken: many.contains) == "notes 41.md")
        // A gap is taken, not the end.
        #expect(Conflict.freeName(for: "docs") { ["docs 2", "docs 4"].contains($0) } == "docs 3")
    }

    @Test func aNameThatIsTakenIsNeverReturned() {
        for name in ["notes.md", "docs", "archive.tar.gz", ".env", "caf\u{E9}.txt"] {
            for count in [0, 1, 7, 150] {
                var names: Set<String> = [name]
                for _ in 0..<count {
                    names.insert(Conflict.freeName(for: name, taken: names.contains))
                }
                // Each one was new: the name itself and `count` others.
                #expect(names.count == count + 1)
            }
        }
    }

    @Test func theNumberGoesBeforeTheExtensionAndAFolderHasNone() {
        let free: (String) -> Bool = { _ in false }
        #expect(Conflict.freeName(for: "my.notes.md", taken: free) == "my.notes 2.md")
        #expect(Conflict.freeName(for: "ARCHIVE.TAR.BZ2", taken: free) == "ARCHIVE 2.TAR.BZ2")
        // Not extensions: a dot-file's name, a dot at the end, words after a dot.
        #expect(Conflict.freeName(for: ".env", taken: free) == ".env 2")
        #expect(Conflict.freeName(for: ".tar.gz", taken: free) == ".tar 2.gz")
        #expect(Conflict.freeName(for: "notes.", taken: free) == "notes. 2")
        #expect(Conflict.freeName(for: "Dr. No", taken: free) == "Dr. No 2")
        // A folder's name is not split.
        #expect(Conflict.freeName(for: "my.project", isFolder: true, taken: free) == "my.project 2")
        #expect(Conflict.freeName(for: "old.tar.gz", isFolder: true, taken: free) == "old.tar.gz 2")
    }

    @Test func aLimitedSearchGivesUp() {
        #expect(Conflict.freeName(for: "notes.md", upTo: 3) { _ in true } == nil)
        #expect(Conflict.freeName(for: "notes.md", upTo: 3) { $0 == "notes 2.md" } == "notes 3.md")
        #expect(Conflict.freeName(for: "notes.md", upTo: 3) { $0 != "notes 4.md" } == nil)
    }

    @Test func aDuplicateIsNamedCopyThenCopy2() {
        let free: (String) -> Bool = { _ in false }
        #expect(Conflict.duplicateName(for: "notes.md", isFolder: false, upTo: 9, taken: free) == "notes copy.md")
        #expect(
            Conflict.duplicateName(for: "notes.md", isFolder: false, upTo: 9) { $0 == "notes copy.md" }
                == "notes copy 2.md")
        #expect(
            Conflict.duplicateName(for: "notes.md", isFolder: false, upTo: 9) {
                ["notes copy.md", "notes copy 2.md"].contains($0)
            } == "notes copy 3.md")
        #expect(Conflict.duplicateName(for: "docs", isFolder: true, upTo: 9, taken: free) == "docs copy")
        #expect(Conflict.duplicateName(for: ".env", isFolder: false, upTo: 9, taken: free) == ".env copy")
        #expect(
            Conflict.duplicateName(for: "archive.tar.gz", isFolder: false, upTo: 9, taken: free)
                == "archive.tar copy.gz")
        #expect(Conflict.duplicateName(for: "notes.md", isFolder: false, upTo: 2) { _ in true } == nil)
    }

    // MARK: The same name (Review Focus 1)

    @Test func namesThatDifferByCapitalsAreTheSameWhereTheVolumeIgnoresCase() {
        #expect(Conflict.sameName("Notes.md", "notes.md", caseSensitive: false))
        #expect(!Conflict.sameName("Notes.md", "notes.md", caseSensitive: true))
        #expect(Conflict.sameName("notes.md", "notes.md", caseSensitive: true))
        #expect(!Conflict.sameName("notes.md", "ideas.md", caseSensitive: false))
        #expect(!Conflict.sameName("notes.md", "notes.md ", caseSensitive: false))
        #expect(!Conflict.sameName("notes.md", "notes 2.md", caseSensitive: false))
    }

    @Test func anAccentWrittenEitherWayIsTheSameName() {
        let composed = "caf\u{E9}.txt"  // é as one character
        let decomposed = "cafe\u{301}.txt"  // e and an accent
        #expect(composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        #expect(Conflict.sameName("\u{E9}", "e\u{301}", caseSensitive: true))
        #expect(Conflict.sameName("\u{E9}", "e\u{301}", caseSensitive: false))
        #expect(Conflict.sameName(composed, decomposed, caseSensitive: true))
        #expect(Conflict.sameName(composed, "CAFE\u{301}.TXT", caseSensitive: false))
        #expect(!Conflict.sameName(composed, "CAFE\u{301}.TXT", caseSensitive: true))
        #expect(!Conflict.sameName(composed, "cafe.txt", caseSensitive: false))
    }

    @Test func theKeyOfANameIsEqualExactlyForTheSameName() {
        let names = ["Notes.md", "notes.md", "NOTES.MD", "caf\u{E9}", "cafe\u{301}", "CAFE\u{301}", "cafe", "notes.md "]
        for caseSensitive in [true, false] {
            for one in names {
                for other in names {
                    let sameKey = Conflict.nameKey(one, caseSensitive: caseSensitive)
                        == Conflict.nameKey(other, caseSensitive: caseSensitive)
                    #expect(sameKey == Conflict.sameName(one, other, caseSensitive: caseSensitive))
                }
            }
        }
    }

    @Test func keepBothDoesNotCollideWithANameInOtherCapitalsOrAnotherForm() {
        // "Notes.md" is there; "notes.md" comes; "NOTES 2.MD" is there too.
        let name = Conflict.freeName(for: "notes.md", taken: taken("Notes.md", "NOTES 2.MD"))
        #expect(name == "notes 3.md")
        #expect(!taken("Notes.md", "NOTES 2.MD")(name))

        // The accent written the other way in the name that is there.
        let cafe = Conflict.freeName(
            for: "cafe\u{301}.txt", taken: taken("caf\u{E9}.txt", "caf\u{E9} 2.txt", "CAF\u{C9} 3.TXT"))
        #expect(cafe == "cafe\u{301} 4.txt")
        #expect(!taken("caf\u{E9}.txt", "caf\u{E9} 2.txt", "CAF\u{C9} 3.TXT")(cafe))
    }

    // MARK: The question

    @Test func aQuestionReadsTheSizeAndDateOfBothItems() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("grove-explorer-conflict-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let incoming = root.appendingPathComponent("incoming.md")
        let existing = root.appendingPathComponent("existing.md")
        try Data("12345".utf8).write(to: incoming)
        try Data("123".utf8).write(to: existing)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        try files.setAttributes([.modificationDate: newer], ofItemAtPath: incoming.path)
        try files.setAttributes([.modificationDate: older], ofItemAtPath: existing.path)

        #expect(
            Conflict.Question(incoming: incoming, existing: existing, remaining: 4)
                == Conflict.Question(
                    incoming: incoming, existing: existing, remaining: 4,
                    incomingSize: 5, incomingDate: newer, existingSize: 3, existingDate: older))

        // A folder has a date and no size of its own; a link is the link,
        // not what it points at; what is not there has neither.
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try files.setAttributes([.modificationDate: older], ofItemAtPath: folder.path)
        let link = root.appendingPathComponent("link")
        try files.createSymbolicLink(atPath: link.path, withDestinationPath: "/nowhere")
        let missing = root.appendingPathComponent("missing")

        let ofFolder = Conflict.Question(incoming: folder, existing: missing, remaining: 0)
        #expect(ofFolder.incomingSize == nil)
        #expect(ofFolder.incomingDate == older)
        #expect(ofFolder.existingSize == nil)
        #expect(ofFolder.existingDate == nil)
        let ofLink = Conflict.Question(incoming: link, existing: existing, remaining: 0)
        #expect(ofLink.incomingSize == Int64("/nowhere".utf8.count))
        #expect(ofLink.incomingDate != nil)
        #expect(ofLink.remaining == 0)
    }

    // MARK: The plan

    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/grove/dest/\(name)") }

    @Test func aPlanAnswersOnlyWhatItWasToldAbout() {
        var plan = ConflictPlan()
        #expect(plan.choice(for: url("a.md")) == nil)

        plan.answer(.replace, for: url("a.md"), applyToAll: false)
        plan.answer(.skip, for: url("b.md"), applyToAll: false)
        #expect(plan.choice(for: url("a.md")) == .replace)
        #expect(plan.choice(for: url("b.md")) == .skip)
        #expect(plan.choice(for: url("c.md")) == nil)

        // The same place written another way.
        #expect(plan.choice(for: URL(fileURLWithPath: "/tmp/grove/dest/../dest/a.md")) == .replace)
    }

    @Test func anAnswerForAllAnswersEveryLaterQuestion() {
        var plan = ConflictPlan()
        plan.answer(.replace, for: url("a.md"), applyToAll: false)
        plan.answer(.keepBoth, for: url("b.md"), applyToAll: true)

        #expect(plan.choice(for: url("b.md")) == .keepBoth)
        #expect(plan.choice(for: url("c.md")) == .keepBoth)
        #expect(plan.choice(for: url("d.md")) == .keepBoth)
        // What was answered before by itself keeps its answer.
        #expect(plan.choice(for: url("a.md")) == .replace)
    }

    @Test func plansWithTheSameAnswersAreEqual() {
        var one = ConflictPlan()
        var other = ConflictPlan()
        #expect(one == other)
        one.answer(.skip, for: url("a.md"), applyToAll: true)
        #expect(one != other)
        other.answer(.skip, for: url("a.md"), applyToAll: true)
        #expect(one == other)
    }
}
