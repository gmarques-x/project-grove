import Foundation
import GroveExplorerCore
import Testing

/// What VoiceOver is given to say for the window's own parts.
@Suite struct SpokenTests {
    private static let london = Locale(identifier: "en_GB")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(2026, 11, 12, 9, 45) }

    private func entry(
        _ name: String, _ kind: Entry.Kind = .file, size: Int64? = nil, modified: Date? = nil, hidden: Bool = false,
        type: String = "Document"
    ) -> Entry {
        Entry(
            url: URL(fileURLWithPath: "/tmp/" + name), name: name, kind: kind, size: size, modified: modified,
            isHidden: hidden, typeDescription: type)
    }

    private func row(_ entry: Entry, total: Int64? = nil, short: Bool = false) -> String {
        Spoken.row(entry, total: total, now: now, calendar: calendar, locale: Self.london, shortDate: short)
    }

    // MARK: A row of the list

    @Test func aFileIsItsNameKindSizeAndDate() {
        let notes = entry("notes.md", size: 4_096, modified: at(2026, 11, 12, 9, 41), type: "Markdown")
        #expect(row(notes) == "notes.md, Markdown, 4 KB, Today at 09:41")
    }

    /// The date is said as the list writes it: in full in a wide pane, the
    /// short way where the pane's dates are short (and where it shows none).
    @Test func theDateIsLongOrShortAsTheListsIs() {
        let today = entry("a.txt", size: 1, modified: at(2026, 11, 12, 9, 41))
        let yesterday = entry("b.txt", size: 1, modified: at(2026, 11, 11, 18, 2))
        let older = entry("c.txt", size: 1, modified: at(2026, 11, 9, 2, 4))
        #expect(row(today, short: true) == "a.txt, Document, 1 byte, Today 09:41")
        #expect(row(yesterday) == "b.txt, Document, 1 byte, Yesterday at 18:02")
        #expect(row(yesterday, short: true) == "b.txt, Document, 1 byte, Yesterday 18:02")
        #expect(row(older) == "c.txt, Document, 1 byte, 9 Nov 2026 at 02:04")
        #expect(row(older, short: true) == "c.txt, Document, 1 byte, 9 Nov 2026")
    }

    @Test func aFoldersSizeIsItsTotalOnceKnown() {
        let folder = entry("grove-keys", .folder, modified: at(2026, 11, 10, 12, 0), type: "Folder")
        #expect(row(folder, total: 214_300_000) == "grove-keys, Folder, 214.3 MB, 10 Nov 2026 at 12:00")
        #expect(row(folder) == "grove-keys, Folder, size not calculated yet, 10 Nov 2026 at 12:00")
        let app = entry("Ghostty.app", .package, modified: at(2026, 11, 10, 12, 0), type: "Application")
        #expect(row(app) == "Ghostty.app, Application, size not calculated yet, 10 Nov 2026 at 12:00")
    }

    /// What the list writes as "--" is not said at all.
    @Test func whatHasNoSizeOrDateLeavesItOut() {
        #expect(row(entry("Backup", .volume, type: "Volume")) == "Backup, Volume")
        #expect(row(entry("link", .symlink(toFolder: true), type: "Alias")) == "link, Alias")
        #expect(row(entry("odd", size: 12, type: "")) == "odd, 12 bytes")
    }

    @Test func aHiddenItemSaysSoLast() {
        let ignore = entry(".gitignore", size: 300, modified: at(2026, 11, 12, 8, 0), hidden: true)
        #expect(row(ignore) == ".gitignore, Document, 300 bytes, Today at 08:00, hidden")
    }

    /// The app has the date written already (it keeps each row's): the same words.
    @Test func theRowFromADateAlreadyWritten() {
        let notes = entry("notes.md", size: 4_096, modified: at(2026, 11, 12, 9, 41), type: "Markdown")
        #expect(Spoken.row(notes, total: nil, date: "Today at 09:41") == row(notes))
        #expect(Spoken.row(notes, total: nil, date: nil) == "notes.md, Markdown, 4 KB")
    }

    // MARK: Panes, columns, tabs

    @Test func aPaneSaysWhichItIsAndWhetherItHasTheKeys() {
        #expect(Spoken.pane(.left, of: 2, active: true) == "Left pane, active")
        #expect(Spoken.pane(.right, of: 2, active: false) == "Right pane")
        #expect(Spoken.pane(.right, of: 2, active: true) == "Right pane, active")
        // The only pane always has the keys: nothing to tell apart.
        #expect(Spoken.pane(.left, of: 1, active: true) == "Pane")
    }

    @Test func aColumnSaysHowItIsSorted() {
        #expect(Spoken.sorted(true, ascending: true) == "sorted ascending")
        #expect(Spoken.sorted(true, ascending: false) == "sorted descending")
        #expect(Spoken.sorted(false, ascending: true) == "")
    }

    @Test func aTabsCloseMarkNamesItsTab() {
        #expect(Spoken.closeTab("Downloads") == "Close tab Downloads")
    }
}
