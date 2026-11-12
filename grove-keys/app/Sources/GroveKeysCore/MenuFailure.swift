import Foundation

/// Something a menu, the launcher or the cheat sheet was asked to do and
/// couldn't. These happen with no Grove window in front, so the app says
/// them in a notification (title "Grove", one line) as well as in the log.
public enum MenuFailure: Equatable, Sendable {
    /// A row's command that could not be started.
    case cannotStart(row: String, reason: String)
    /// An `open` row whose text names nothing that can be opened.
    case nothingToOpen(row: String, target: String)
    /// `grovekeys://menu/<id>` for an id the Grove menu doesn't have.
    case unknownRow(id: String)
    /// The Lock row, when neither way of locking worked.
    case cannotLock(reason: String)
    /// A row of the front app's menu that is no longer there.
    case menuItemGone(path: [String])

    public static let title = "Grove"

    /// One line naming the row and the reason.
    public var body: String {
        let text: String
        switch self {
        case .cannotStart(let row, let reason):
            text = "\"\(row)\" couldn't start: \(reason)"
        case .nothingToOpen(let row, let target):
            text = "\"\(row)\" has nothing to open: \(target.isEmpty ? "its open line is empty" : target)"
        case .unknownRow(let id):
            text = "No row \"\(id)\" in the Grove menu"
        case .cannotLock(let reason):
            text = "\"Lock\" couldn't lock the screen: \(reason)"
        case .menuItemGone(let path):
            text = "\"\(path.last ?? "The menu item")\" is no longer in the app's menu"
                + (path.count > 1 ? " (\(path.dropLast().joined(separator: " › ")))" : "")
        }
        return Self.oneLine(text)
    }

    /// A reason may come from the system with line breaks, or be very long.
    static func oneLine(_ text: String, limit: Int = 160) -> String {
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > limit ? flat.prefix(limit - 1) + "…" : flat
    }
}
