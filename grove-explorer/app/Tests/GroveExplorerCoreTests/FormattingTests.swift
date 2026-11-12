import Foundation
import GroveExplorerCore
import Testing

@Suite struct FormattingTests {
    // MARK: Sizes

    @Test func theMockUpsSizes() {
        #expect(Formatting.size(4_096) == "4 KB")
        #expect(Formatting.size(12_600_000) == "12.6 MB")
        #expect(Formatting.size(1_840_000_000) == "1.84 GB")
        #expect(Formatting.size(0) == "Zero KB")
    }

    /// What Finder (the system's file-size formatter) writes for each, with a
    /// decimal point: no decimals in KB, one in MB, two from GB up, zeros at
    /// the end dropped, halves rounded up, and the next unit at 1,000.
    @Test(arguments: [
        (1, "1 byte"), (2, "2 bytes"), (500, "500 bytes"), (999, "999 bytes"),
        (1_000, "1 KB"), (1_024, "1 KB"), (1_499, "1 KB"), (1_500, "2 KB"), (2_500, "3 KB"),
        (999_499, "999 KB"), (999_500, "1 MB"), (1_000_000, "1 MB"), (1_040_000, "1 MB"),
        (1_050_000, "1.1 MB"), (1_250_000, "1.3 MB"), (12_000_000, "12 MB"),
        (99_950_000, "100 MB"), (999_949_999, "999.9 MB"), (999_950_000, "1 GB"),
        (1_004_000_000, "1 GB"), (1_005_000_000, "1.01 GB"), (1_125_000_000, "1.13 GB"),
        (1_800_000_000, "1.8 GB"), (2_000_000_000, "2 GB"),
        (999_994_999_999, "999.99 GB"), (999_995_000_000, "1 TB"), (1_234_000_000_000, "1.23 TB"),
        (1_234_000_000_000_000, "1.23 PB"), (5_000_000_000_000_000_000, "5 EB"),
        (999_999_999_999_999_999, "1 EB"), (Int64.max, "9.22 EB"),
    ] as [(Int64, String)])
    func sizesAsFinderWritesThem(bytes: Int64, expected: String) {
        #expect(Formatting.size(bytes) == expected)
    }

    @Test func aSizeNeverHasADecimalComma() {
        for bytes: Int64 in [1_050_000, 12_600_000, 1_840_000_000, 999_949_999] {
            #expect(!Formatting.size(bytes).contains(","))
        }
    }

    @Test func aNegativeSizeIsWrittenAsNone() {
        #expect(Formatting.size(-1) == "Zero KB")
    }

    // MARK: Dates

    private static let lisbon = TimeZone(identifier: "Europe/Lisbon")!
    private static let british = Locale(identifier: "en_GB")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.lisbon
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func text(
        _ date: Date, now: Date, short: Bool = false, locale: Locale = british, calendar: Calendar? = nil
    ) -> String {
        Formatting.date(date, now: now, calendar: calendar ?? self.calendar, locale: locale, short: short)
    }

    @Test func theSameDayIsToday() {
        let now = at(2026, 11, 12, 10, 0)
        #expect(text(at(2026, 11, 12, 9, 41), now: now) == "Today at 09:41")
        #expect(text(at(2026, 11, 12, 0, 0), now: now) == "Today at 00:00")
        // Later the same day (a file just written, a clock a little off).
        #expect(text(at(2026, 11, 12, 23, 59), now: now) == "Today at 23:59")
    }

    @Test func theDayBeforeIsYesterday() {
        let now = at(2026, 11, 12, 10, 0)
        #expect(text(at(2026, 11, 11, 18, 2), now: now) == "Yesterday at 18:02")
        #expect(text(at(2026, 11, 11, 0, 0), now: now) == "Yesterday at 00:00")
    }

    /// It is the calendar day that counts, not how many hours ago.
    @Test func twoMinutesAgoAcrossMidnightIsYesterday() {
        #expect(text(at(2026, 11, 11, 23, 59), now: at(2026, 11, 12, 0, 1)) == "Yesterday at 23:59")
    }

    @Test func olderIsTheDateAndTheTime() {
        let now = at(2026, 11, 12, 10, 0)
        #expect(text(at(2026, 11, 9, 2, 4), now: now) == "9 Nov 2026 at 02:04")
        #expect(text(at(2026, 11, 10, 23, 59), now: now) == "10 Nov 2026 at 23:59")
        #expect(text(at(2019, 1, 31, 14, 30), now: now) == "31 Jan 2019 at 14:30")
    }

    @Test func aDateAfterTodayIsWrittenInFull() {
        #expect(text(at(2026, 11, 13, 8, 0), now: at(2026, 11, 12, 10, 0)) == "13 Nov 2026 at 08:00")
    }

    @Test func yesterdayAcrossAMonthAndAYear() {
        #expect(text(at(2026, 12, 31, 22, 0), now: at(2027, 1, 1, 9, 0)) == "Yesterday at 22:00")
        #expect(text(at(2026, 2, 28, 22, 0), now: at(2026, 3, 1, 9, 0)) == "Yesterday at 22:00")
    }

    @Test func shortDropsTheAtAndAnOlderDatesTime() {
        let now = at(2026, 11, 12, 10, 0)
        #expect(text(at(2026, 11, 12, 9, 41), now: now, short: true) == "Today 09:41")
        #expect(text(at(2026, 11, 11, 18, 2), now: now, short: true) == "Yesterday 18:02")
        #expect(text(at(2026, 11, 9, 2, 4), now: now, short: true) == "9 Nov 2026")
    }

    /// The day is the one in the calendar's time zone: 23:30 on the 11th in
    /// Lisbon is already the 12th in Tokyo.
    @Test func theCalendarsTimeZoneDecidesTheDay() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = at(2026, 11, 11, 23, 30)
        let now = at(2026, 11, 12, 10, 0)
        #expect(text(date, now: now) == "Yesterday at 23:30")
        #expect(text(date, now: now, calendar: tokyo) == "Today at 08:30")
    }

    @Test func theLocaleGivenWritesTheWordsAndTheDate() {
        let portuguese = Locale(identifier: "pt_PT")
        let now = at(2026, 11, 12, 10, 0)
        #expect(text(at(2026, 11, 12, 9, 41), now: now, locale: portuguese) == "Hoje, 09:41")
        #expect(text(at(2026, 11, 11, 18, 2), now: now, locale: portuguese) == "Ontem, 18:02")
        #expect(text(at(2026, 11, 9, 2, 4), now: now, locale: portuguese) == "09/11/2026, 02:04")
        #expect(text(at(2026, 11, 12, 9, 41), now: now, short: true, locale: portuguese) == "Hoje 09:41")
        #expect(text(at(2026, 11, 9, 2, 4), now: now, short: true, locale: portuguese) == "09/11/2026")
    }

    // MARK: Long names

    @Test func aLongNameIsCutInTheMiddleKeepingItsExtension() {
        #expect(Formatting.middleTruncated("Screenshot 2026-11-09 at 09.41.44.png", to: 22) == "Screenshot 2026…44.png")
        #expect(Formatting.middleTruncated("Screenshot 2026-11-09 at 09.41.44.png", to: 22).count == 22)
        #expect(Formatting.middleTruncated("a-very-long-archive-name.tar.gz", to: 16) == "a-very-lon…ar.gz")
    }

    @Test func aNameThatFitsIsLeftAlone() {
        #expect(Formatting.middleTruncated("notes.md", to: 8) == "notes.md")
        #expect(Formatting.middleTruncated("notes.md", to: 40) == "notes.md")
        #expect(Formatting.middleTruncated("", to: 5) == "")
    }

    @Test func oneCharacterOverIsCut() {
        #expect(Formatting.middleTruncated("notes-2026.md", to: 12) == "notes-…26.md")
    }

    @Test func aNameWithoutAnExtensionIsCutInItsMiddle() {
        #expect(Formatting.middleTruncated("a-folder-with-a-long-name", to: 11) == "a-fol…-name")
        #expect(Formatting.middleTruncated("a-folder-with-a-long-name", to: 10) == "a-fol…name")
        // A dot-file's name is not an extension, nor are words after a full stop.
        #expect(Formatting.middleTruncated(".a-long-hidden-settings-file", to: 11) == ".a-lo…-file")
        #expect(Formatting.middleTruncated("Letter to Mr. Smith and family", to: 11) == "Lette…amily")
    }

    @Test func anExtensionTooLongToKeepIsCutLikeAnyName() {
        #expect(Formatting.middleTruncated("a.averylongextension", to: 9) == "a.av…sion")
    }

    @Test func aNarrowCountKeepsWhatItCanOfTheEnd() {
        // Room for the extension and one character of the name, no more.
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 7) == "h….jpeg")
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 8) == "h…o.jpeg")
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 9) == "h…to.jpeg")
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 10) == "ho…to.jpeg")
    }

    @Test func theSmallestCounts() {
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 2) == "h…")
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 1) == "…")
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: 0) == "")
        #expect(Formatting.middleTruncated("holiday-photo.jpeg", to: -3) == "")
    }

    /// Characters as the reader sees them: an accent or an emoji is never split.
    @Test func charactersAreCountedAsSeen() {
        let name = "cafe\u{301}-👨‍👩‍👧-relato\u{301}rio-final.pdf"
        let cut = Formatting.middleTruncated(name, to: 14)
        #expect(cut == "cafe\u{301}-👨‍👩‍👧-…al.pdf")
        #expect(cut.count == 14)
    }
}
