import Foundation

/// The words at the left of a pane's status bar.
public enum StatusText {
    /// "212 items", "1 item"; with a selection "3 of 212 selected · 48.2 MB",
    /// the size left out while it isn't known (`selectedBytes` nil: a folder
    /// still being measured is among them); under a filter "4 of 212", where
    /// `total` is what the filter shows and `filteredFrom` what the folder
    /// holds. A selection under a filter is counted among what shows.
    public static func items(total: Int, selected: Int, selectedBytes: Int64?, filteredFrom: Int?) -> String {
        if selected > 0 {
            let size = selectedBytes.map { " · " + Formatting.size($0) } ?? ""
            return "\(selected) of \(total) selected\(size)"
        }
        if let filteredFrom { return "\(total) of \(filteredFrom)" }
        return total == 1 ? "1 item" : "\(total) items"
    }
}
