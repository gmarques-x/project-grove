import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct MonthGridTests {
    static let today = CalendarDay(year: 2026, month: 11, day: 12)

    static func numbers(_ week: MonthGrid.Week) -> [Int] { week.days.map(\.date.day) }

    @Test func weekdaysCountFromMonday() {
        #expect(Self.today.weekday == 3)                                       // a Thursday
        #expect(CalendarDay(year: 1970, month: 1, day: 1).weekday == 3)
        #expect(CalendarDay(year: 2026, month: 11, day: 1).weekday == 6)       // a Sunday
        #expect(CalendarDay(year: 2027, month: 2, day: 1).weekday == 0)        // a Monday
        #expect(CalendarDay(year: 1969, month: 12, day: 31).weekday == 2)
        #expect(CalendarDay(year: 2000, month: 2, day: 29).weekday == 1)
    }

    @Test func daysAreCountedAcrossMonthsAndLeapYears() {
        #expect(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1) == CalendarDay(year: 2027, month: 1, day: 1))
        #expect(CalendarDay(year: 2028, month: 2, day: 28).adding(days: 1) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(CalendarDay(year: 2027, month: 3, day: 1).adding(days: -1) == CalendarDay(year: 2027, month: 2, day: 28))
        #expect(CalendarDay(year: 2100, month: 3, day: 1).adding(days: -1) == CalendarDay(year: 2100, month: 2, day: 28))
        #expect(CalendarDay(year: 2026, month: 1, day: 1).adding(days: 365) == CalendarDay(year: 2027, month: 1, day: 1))
    }

    @Test func weekNumbersAreISO() {
        #expect(Self.today.isoWeek == 46)
        // The week belongs to the year its Thursday is in.
        #expect(CalendarDay(year: 2026, month: 12, day: 31).isoWeek == 53)
        #expect(CalendarDay(year: 2027, month: 1, day: 1).isoWeek == 53)
        #expect(CalendarDay(year: 2027, month: 1, day: 4).isoWeek == 1)
        #expect(CalendarDay(year: 2024, month: 12, day: 30).isoWeek == 1)
        #expect(CalendarDay(year: 2026, month: 1, day: 1).isoWeek == 1)
        #expect(CalendarDay(year: 2021, month: 1, day: 3).isoWeek == 53)
    }

    @Test func novemberAsApproved() {
        let grid = MonthGrid(CalendarMonth(year: 2026, month: 11), today: Self.today)
        #expect(grid.weeks.count == 6)
        #expect(grid.weeks.map(\.number) == [44, 45, 46, 47, 48, 49])
        // Monday first; October's last days lead in, December's first follow.
        #expect(Self.numbers(grid.weeks[0]) == [26, 27, 28, 29, 30, 31, 1])
        #expect(grid.weeks[0].days.map(\.inMonth) == [false, false, false, false, false, false, true])
        #expect(Self.numbers(grid.weeks[2]) == [9, 10, 11, 12, 13, 14, 15])
        #expect(Self.numbers(grid.weeks[5]) == [30, 1, 2, 3, 4, 5, 6])
        #expect(grid.weeks[5].days.map(\.inMonth) == [true, false, false, false, false, false, false])
        #expect(grid.weeks[5].days[1].date == CalendarDay(year: 2026, month: 12, day: 1))
        // Today, once.
        let todays = grid.weeks.flatMap(\.days).filter(\.isToday)
        #expect(todays.map(\.date) == [Self.today])
        #expect(grid.weeks[2].days[3].isToday)
    }

    @Test func everyMonthIsSixWeeks() {
        // February 2027 starts on a Monday and fills four weeks: two of March follow.
        let february = MonthGrid(CalendarMonth(year: 2027, month: 2), today: Self.today)
        #expect(february.weeks.count == 6)
        #expect(Self.numbers(february.weeks[0]) == [1, 2, 3, 4, 5, 6, 7])
        #expect(Self.numbers(february.weeks[4]) == [1, 2, 3, 4, 5, 6, 7])
        #expect(february.weeks[4].days.allSatisfy { !$0.inMonth })
        #expect(february.weeks.flatMap(\.days).filter(\.inMonth).count == 28)
        #expect(february.weeks.flatMap(\.days).allSatisfy { !$0.isToday })
        // The year's turn: week 53, then 1.
        let january = MonthGrid(CalendarMonth(year: 2027, month: 1), today: Self.today)
        #expect(january.weeks.map(\.number) == [53, 1, 2, 3, 4, 5])
        #expect(Self.numbers(january.weeks[0]) == [28, 29, 30, 31, 1, 2, 3])
    }

    @Test func aNeighbouringMonthsTodayIsStillToday() {
        // December shows 30 November in its first week; were that today, it is marked there too.
        let grid = MonthGrid(CalendarMonth(year: 2026, month: 12), today: CalendarDay(year: 2026, month: 11, day: 30))
        #expect(grid.weeks[0].days[0].isToday)
        #expect(!grid.weeks[0].days[0].inMonth)
    }

    @Test func previousAndNextCrossTheYear() {
        #expect(CalendarMonth(year: 2026, month: 11).next == CalendarMonth(year: 2026, month: 12))
        #expect(CalendarMonth(year: 2026, month: 12).next == CalendarMonth(year: 2027, month: 1))
        #expect(CalendarMonth(year: 2027, month: 1).previous == CalendarMonth(year: 2026, month: 12))
        #expect(CalendarMonth(year: 2026, month: 11).previous == CalendarMonth(year: 2026, month: 10))
        #expect(CalendarMonth(Self.today) == CalendarMonth(year: 2026, month: 11))
    }
}
