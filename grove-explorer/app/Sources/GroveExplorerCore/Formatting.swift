import Foundation

/// The list's texts for a size, a date and a name too long for its column.
public enum Formatting {
    // MARK: Size

    /// From the second on, each is 1,000 of the one before, with the number
    /// of decimals Finder gives it.
    private static let units: [(name: String, decimals: Int)] = [
        ("KB", 0), ("MB", 1), ("GB", 2), ("TB", 2), ("PB", 2), ("EB", 2),
    ]

    /// A size as Finder writes it: "Zero KB", "512 bytes", "4 KB", "12.6 MB",
    /// "1.84 GB". Decimal units (1 KB is 1,000 bytes), halves rounded up,
    /// zeros at the end dropped. Always a decimal point, whatever the user's
    /// locale: the digits are put together here, not by a number formatter.
    public static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Zero KB" }
        guard bytes >= 1_000 else { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }

        var unit: Int64 = 1_000
        for (index, (name, decimals)) in units.enumerated() {
            let scale: Int64 = decimals == 0 ? 1 : decimals == 1 ? 10 : 100
            // bytes × scale ÷ unit, rounded; the product can pass 64 bits.
            let product = bytes.multipliedFullWidth(by: scale)
            var (scaled, remainder) = unit.dividingFullWidth(product)
            if remainder >= unit - remainder { scaled += 1 }

            // 999.95 MB rounds to 1,000.0: that is written as 1 GB.
            if scaled >= 1_000 * scale, index < units.count - 1 {
                unit *= 1_000
                continue
            }
            // The decimals, as many digits as the unit has, less the zeros at the end.
            var fraction = String(scaled % scale + scale).dropFirst()
            while fraction.last == "0" { fraction.removeLast() }
            return "\(scaled / scale)\(fraction.isEmpty ? "" : ".")\(fraction) \(name)"
        }
        return "\(bytes) bytes"  // Not reached: the last unit always returns.
    }

    // MARK: Date

    /// A date as Finder writes it: "Today at 09:41", "Yesterday at 18:02",
    /// otherwise the date and the time ("9 Nov 2026 at 02:04"), in the words
    /// and the order of `locale`. `short` is for a narrow column: "Today
    /// 09:41", and the date alone for an older one ("9 Nov 2026").
    ///
    /// The day is `calendar`'s, in its time zone, counted from `now`; a date
    /// after today is written in full.
    public static func date(
        _ date: Date, now: Date, calendar: Calendar, locale: Locale, short: Bool
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        func text(date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style) -> String {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            return formatter.string(from: date)
        }

        guard let day = dayWord(for: date, now: now, calendar: calendar, locale: locale) else {
            return text(date: .medium, time: short ? .none : .short)
        }
        let time = text(date: .none, time: .short)
        if short { return "\(day) \(time)" }

        // What the locale puts between a date and a time (" at ", ", "),
        // read off a full date written by the same formatter.
        let full = text(date: .medium, time: .short)
        let dateAlone = text(date: .medium, time: .none)
        var joiner = ", "
        if full.count >= dateAlone.count + time.count, full.hasPrefix(dateAlone), full.hasSuffix(time) {
            joiner = String(full.dropFirst(dateAlone.count).dropLast(time.count))
        }
        return day + joiner + time
    }

    /// "Today" or "Yesterday" in the locale's words, nil for any other day.
    private static func dayWord(
        for date: Date, now: Date, calendar: Calendar, locale: Locale
    ) -> String? {
        let daysAgo: Int
        if calendar.isDate(date, inSameDayAs: now) {
            daysAgo = 0
        } else if let dayBefore = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: dayBefore)
        {
            daysAgo = 1
        } else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: DateComponents(day: -daysAgo))
    }

    // MARK: Long names

    /// How many characters of the name are kept just before its extension.
    private static let keptBeforeExtension = 2

    /// A name cut to at most `count` characters with "…" in place of what is
    /// left out. The end kept is the extension and the two characters before
    /// it ("Screenshot 2026…44.png"), the start gets the rest. A name with no
    /// extension, or with one too long to keep, is cut in its middle.
    public static func middleTruncated(_ name: String, to count: Int) -> String {
        let characters = Array(name)
        guard characters.count > count else { return name }
        guard count > 0 else { return "" }
        let room = count - 1  // The "…" takes one.

        var tail = room / 2
        if let dot = extensionDot(in: characters) {
            let withExtension = characters.count - dot
            // Kept only when a character of the start still fits before it.
            if withExtension < room {
                tail = min(withExtension + keptBeforeExtension, room - 1)
            }
        }
        let head = room - tail
        return String(characters[..<head]) + "…" + String(characters[(characters.count - tail)...])
    }

    /// Where the dot of the extension is: the last one, when it isn't the
    /// first character (a dot-file), has something after it, and what follows
    /// has no space ("Mr. Smith" has no extension).
    private static func extensionDot(in characters: [Character]) -> Int? {
        guard let dot = characters.lastIndex(of: "."), dot > 0, dot < characters.count - 1,
            !characters[(dot + 1)...].contains(where: \.isWhitespace)
        else { return nil }
        return dot
    }
}
