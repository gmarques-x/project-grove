import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The names a calendar is written with. The user's language says how a
/// month and a weekday are called; nothing else of the region is followed
/// (the week starts on Monday, weeks are ISO, the day comes before the month).
struct ClockNames: Equatable {
    /// January first.
    var months: [String]
    /// Monday first, in full.
    var weekdays: [String]
    /// Monday first, one letter each (the grid's header).
    var letters: [String]

    /// English, for the sample render.
    static let english = ClockNames(
        months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                 "November", "December"],
        weekdays: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
        letters: ["M", "T", "W", "T", "F", "S", "S"])

    /// In the user's language. Anything Foundation doesn't give in full
    /// (twelve months, seven days) falls back to English.
    static func current(_ locale: Locale = .current) -> ClockNames {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        // Foundation's weeks start on Sunday.
        func mondayFirst(_ symbols: [String]) -> [String] { Array(symbols.dropFirst()) + symbols.prefix(1) }
        let months = calendar.standaloneMonthSymbols, days = calendar.standaloneWeekdaySymbols
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        guard months.count == 12, days.count == 7, letters.count == 7 else { return .english }
        return ClockNames(months: months, weekdays: mondayFirst(days), letters: mondayFirst(letters))
    }

    /// "November 2026".
    func title(_ month: CalendarMonth) -> String {
        Self.capitalized(months[month.month - 1]) + " \(month.year)"
    }

    /// "Thursday 12 November".
    func spelled(_ day: CalendarDay) -> String {
        Self.capitalized("\(weekdays[day.weekday]) \(day.day) \(months[day.month - 1])")
    }

    /// Some languages write months and days in lower case; a title and the
    /// start of a line take a capital all the same.
    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// The clock panel's state: which month is shown, and what today is.
@MainActor
final class ClockModel: ObservableObject, BarPanelModel {
    @Published private(set) var today: CalendarDay
    @Published private(set) var month: CalendarMonth
    let names: ClockNames
    /// The sample's day; nil when live.
    private let fixed: CalendarDay?
    private var midnight: Timer?

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            fixed = nil
            names = .current()
        case .sample:
            // The day the mock-ups were approved on.
            fixed = CalendarDay(year: 2026, month: 11, day: 12)
            names = .english
        }
        let today = fixed ?? Self.now()
        self.today = today
        month = CalendarMonth(today)
    }

    var grid: MonthGrid { MonthGrid(month, today: today) }

    /// Opens on the current month every time.
    func start() {
        showToday()
        // Left open over midnight, today moves on. Half a minute is fine
        // enough, and nothing runs while the panel is closed.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = self.fixed ?? Self.now()
                if now != self.today { self.today = now }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnight = timer
    }

    func stop() {
        midnight?.invalidate()
        midnight = nil
    }

    func showPrevious() { month = month.previous }
    func showNext() { month = month.next }

    func showToday() {
        today = fixed ?? Self.now()
        month = CalendarMonth(today)
    }

    /// ← and → change the month; Home or T comes back to today.
    func key(_ key: BarPanelKey) -> Bool {
        switch key {
        case .left: showPrevious()
        case .right: showNext()
        case .home, .character("t"): showToday()
        default: return false
        }
        return true
    }

    /// Today in the Mac's time zone.
    private static func now() -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return CalendarDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}

/// The clock's panel (variant A of the approved mock-ups): the month with
/// its chevrons, the grid with ISO week numbers, today spelt out below.
struct ClockPanel: View {
    static let registration = BarPanelRegistration("clock", pill: "pill.clock", width: width,
                                                   model: ClockModel.init) { ClockPanel(model: $0) }

    /// One day's cell, a measured drawing: two digits of body text and room
    /// for today's disc.
    static let cell = CGSize(width: 28, height: 24)
    /// The week column and seven days between the panel's insets: 248.
    static let width = cell.width * 8 + 2 * PanelMetrics.inset
    /// Today's disc, inside its cell.
    static let disc = cell.height - GroveSpace.s2

    @ObservedObject var model: ClockModel
    @Environment(\.theme) private var theme

    var body: some View {
        let grid = model.grid
        BarPanel(width: Self.width) {
            PanelHeader(title: model.names.title(model.month)) {
                HStack(spacing: GroveSpace.s4) {
                    chevron(.back, "Previous month", model.showPrevious)
                    chevron(.forward, "Next month", model.showNext)
                }
                // The second chevron's drawing, not its frame, ends on the inset.
                .padding(.trailing, -GroveSpace.s4)
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    cell { Text("wk") }
                    ForEach(Array(model.names.letters.enumerated()), id: \.offset) { index, letter in
                        cell { Text(letter) }.accessibilityLabel(model.names.weekdays[index])
                    }
                }
                .font(GroveFont.mono(GroveType.finePrint))
                .foregroundStyle(theme.quiet)
                ForEach(grid.weeks, id: \.days.first?.date) { week in
                    GridRow {
                        cell { Text("\(week.number)").font(GroveFont.mono(GroveType.finePrint)) }
                            .foregroundStyle(theme.quiet)
                            .accessibilityLabel("Week \(week.number)")
                        ForEach(week.days, id: \.date) { day in
                            cell { self.day(day) }
                        }
                    }
                }
            }
            PanelRule()
            PanelRows {
                PanelRow(action: model.showToday) {
                    Text(model.names.spelled(model.today))
                    Spacer(minLength: GroveSpace.s8)
                    Text("week \(model.today.isoWeek)").foregroundStyle(theme.quiet)
                }
                .help("Back to today (Home or T); ← and → change the month")
            }
        }
    }

    /// A day's number: fg in the month shown, fainter for a neighbour's,
    /// and today on a green disc in the on-accent ink.
    private func day(_ day: MonthGrid.Day) -> some View {
        Text("\(day.date.day)")
            .font(GroveFont.mono(GroveType.body, day.isToday ? .bold : .regular))
            .foregroundStyle(day.isToday ? Color(theme.onAccent) : day.inMonth ? Color(theme.fg) : theme.quiet(dark: 0.7))
            .frame(width: Self.disc, height: Self.disc)
            .background(day.isToday ? Color(theme.green) : .clear, in: Circle())
            .accessibilityLabel(model.names.spelled(day.date))
            .accessibilityAddTraits(day.isToday ? .isSelected : [])
    }

    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: Self.cell.width, height: Self.cell.height)
    }

    private func chevron(_ icon: GroveIcon.Name, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GroveIcon(icon, size: GroveType.label)
                .foregroundStyle(theme.quiet)
                .frame(width: GroveSpace.s16, height: GroveSpace.s16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
