import Foundation

/// What VoiceOver is given to say for the window's own parts: the things
/// the app draws itself, which have no words of their own.
public enum Spoken {
    // MARK: A row of the list

    /// A row as one sentence: "notes.md, Markdown, 4 KB, Today at 09:41".
    /// The name, the kind, the size and the date, each as the list writes
    /// it; the date long or short as the pane's dates are (`shortDate`: a
    /// pane too narrow for the full date, or for any). A folder's size is
    /// its `total` once that is known. What the list writes as "--" is left
    /// out; a hidden item says so last.
    public static func row(
        _ entry: Entry, total: Int64?, now: Date, calendar: Calendar, locale: Locale, shortDate: Bool
    ) -> String {
        let date = entry.modified.map {
            Formatting.date($0, now: now, calendar: calendar, locale: locale, short: shortDate)
        }
        return row(entry, total: total, date: date)
    }

    /// The same from a date already written (the list keeps each row's).
    public static func row(_ entry: Entry, total: Int64?, date: String?) -> String {
        var parts = [entry.name]
        if !entry.typeDescription.isEmpty { parts.append(entry.typeDescription) }
        if let size = entry.size ?? total {
            parts.append(Formatting.size(size))
        } else if SizeWanted.isMeasured(entry) {
            parts.append("size not calculated yet")
        }
        if let date { parts.append(date) }
        if entry.isHidden { parts.append("hidden") }
        return parts.joined(separator: ", ")
    }

    // MARK: Panes, columns, tabs

    /// A pane: "Left pane, active", "Right pane". The only pane is "Pane":
    /// it always has the keys.
    public static func pane(_ side: Side, of count: Int, active: Bool) -> String {
        guard count > 1 else { return "Pane" }
        return (side == .left ? "Left pane" : "Right pane") + (active ? ", active" : "")
    }

    /// Beside a column's name: how the list is sorted by it; "" when it is not.
    public static func sorted(_ sorted: Bool, ascending: Bool) -> String {
        sorted ? (ascending ? "sorted ascending" : "sorted descending") : ""
    }

    /// A tab's close mark.
    public static func closeTab(_ title: String) -> String { "Close tab " + title }
}
