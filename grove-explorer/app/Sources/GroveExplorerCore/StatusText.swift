import Foundation

/// The words at the left of a pane's status bar.
public enum StatusText {
    /// "212 items", "1 item", the rows showing; with folders open in place
    /// (spec §16; `foldersOpen` counts one still being read)
    /// "212 items · 3 folders open". With a selection
    /// "3 of 212 selected · 48.2 MB", and no count of open folders, the
    /// size left out while it isn't known (`selectedBytes` nil: a folder
    /// still being measured is among them). Under a filter "4 of 212",
    /// where `total` is the matches and `filteredFrom` the rows that would
    /// show without it, and no count of open folders either. A selection
    /// under a filter is counted among what shows.
    public static func items(
        total: Int, foldersOpen: Int, selected: Int, selectedBytes: Int64?, filteredFrom: Int?
    ) -> String {
        if selected > 0 {
            let size = selectedBytes.map { " · " + Formatting.size($0) } ?? ""
            return "\(selected) of \(total) selected\(size)"
        }
        if let filteredFrom { return "\(total) of \(filteredFrom)" }
        let items = total == 1 ? "1 item" : "\(total) items"
        switch foldersOpen {
        case ...0: return items
        case 1: return items + " · 1 folder open"
        default: return items + " · \(foldersOpen) folders open"
        }
    }
}
