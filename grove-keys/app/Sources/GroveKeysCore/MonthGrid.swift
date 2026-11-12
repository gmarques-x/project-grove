import Foundation

/// A day of the Gregorian calendar.
public struct CalendarDay: Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Days since 1970-01-01 (negative before).
    var serial: Int {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    init(serial: Int) {
        let z = serial + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (month <= 2 ? 1 : 0), month: month, day: doy - (153 * mp + 2) / 5 + 1)
    }

    /// 0 Monday … 6 Sunday.
    public var weekday: Int {
        // 1970-01-01 was a Thursday.
        let shifted = (serial + 3) % 7
        return shifted < 0 ? shifted + 7 : shifted
    }

    /// The ISO 8601 week: the week (Monday first) belongs to the year its
    /// Thursday is in, and week 1 is the one with the year's first Thursday.
    public var isoWeek: Int {
        let thursday = CalendarDay(serial: serial - weekday + 3)
        let first = CalendarDay(year: thursday.year, month: 1, day: 1)
        return (thursday.serial - first.serial) / 7 + 1
    }

    public func adding(days: Int) -> CalendarDay { CalendarDay(serial: serial + days) }
}

/// A month of a year.
public struct CalendarMonth: Hashable, Sendable {
    public var year: Int
    /// 1...12.
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month `day` is in.
    public init(_ day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    public var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    public var next: CalendarMonth {
        month == 12 ? CalendarMonth(year: year + 1, month: 1) : CalendarMonth(year: year, month: month + 1)
    }
}

/// A month as the clock panel draws it: six weeks, Monday first, each with
/// its ISO week number; the days before the 1st and after the last are the
/// neighbouring months' own. Always six rows (a month needs four to six), so
/// the panel keeps its height from month to month.
public struct MonthGrid: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public var date: CalendarDay
        /// In the month shown, not a neighbour's.
        public var inMonth: Bool
        public var isToday: Bool
    }

    public struct Week: Equatable, Sendable {
        /// The ISO week number.
        public var number: Int
        /// Monday to Sunday.
        public var days: [Day]
    }

    public static let rows = 6

    public var month: CalendarMonth
    public var weeks: [Week]

    public init(_ month: CalendarMonth, today: CalendarDay) {
        self.month = month
        let first = CalendarDay(year: month.year, month: month.month, day: 1)
        let monday = first.adding(days: -first.weekday)
        weeks = (0..<Self.rows).map { row in
            let start = monday.adding(days: row * 7)
            return Week(number: start.isoWeek, days: (0..<7).map { offset in
                let date = start.adding(days: offset)
                return Day(date: date, inMonth: CalendarMonth(date) == month, isToday: date == today)
            })
        }
    }
}
