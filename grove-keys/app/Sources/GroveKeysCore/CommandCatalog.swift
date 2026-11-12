import Foundation

/// The AeroSpace commands the key editor offers (spec §7); anything else is
/// typed as free text.
public enum CommandCatalog {
    public static let entries: [(title: String, template: String)] = [
        ("workspace", "workspace N"),
        ("move-node-to-workspace", "move-node-to-workspace N"),
        ("focus left", "focus left"),
        ("focus down", "focus down"),
        ("focus up", "focus up"),
        ("focus right", "focus right"),
        ("move left", "move left"),
        ("move down", "move down"),
        ("move up", "move up"),
        ("move right", "move right"),
        ("resize −", "resize smart -50"),
        ("resize +", "resize smart +50"),
        ("layout tiles", "layout tiles horizontal vertical"),
        ("layout accordion", "layout accordion horizontal vertical"),
        ("float / tile", "layout floating tiling"),
        ("workspace back and forth", "workspace-back-and-forth"),
        ("workspace to next monitor", "move-workspace-to-monitor --wrap-around next"),
        ("service mode", "mode service"),
        ("close", "close"),
        ("reload-config", "reload-config"),
        ("fullscreen", "fullscreen"),
    ]

    /// A row of the key editor's command list.
    public struct Row: Equatable, Sendable, Identifiable {
        /// The template, or `customID`.
        public var id: String
        public var title: String
        /// The command the row writes; nil for "Custom command…".
        public var command: String?
        /// The digit a "… N" template takes on this key, else "".
        public var number: String
    }

    public static let customID = "custom"

    /// The list for `key`: every entry with its command, then "Custom command…".
    public static func rows(key: String) -> [Row] {
        entries.map { entry in
            let command = command(template: entry.template, key: key)
            return Row(id: entry.template, title: entry.title, command: command,
                       number: entry.template.hasSuffix(" N") ? String(command.split(separator: " ").last ?? "") : "")
        } + [Row(id: customID, title: "Custom command…", command: nil, number: "")]
    }

    /// The row that writes exactly `text` (spaces at the ends aside), else
    /// "Custom command…": what is typed or saved is shown where it belongs.
    public static func rowID(for text: String, in rows: [Row]) -> String {
        let typed = text.trimmingCharacters(in: .whitespaces)
        return rows.first { $0.command == typed }?.id ?? customID
    }

    /// The template with N as the key's digit (1 for any other key).
    public static func command(template: String, key: String) -> String {
        guard template.hasSuffix(" N") else { return template }
        let n = key.count == 1 && key.first!.isNumber ? key : "1"
        return String(template.dropLast()) + n
    }
}
