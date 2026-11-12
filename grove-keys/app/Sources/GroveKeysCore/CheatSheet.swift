import Foundation

/// What Return does on a row of the searchable cheat sheet.
public enum CheatAction: Equatable, Sendable {
    /// Nothing to run (a key of Ghostty, the shell or macOS, a folded 1 … 9
    /// row, a launcher whose app is missing): the sheet only closes.
    case none
    /// A launcher: the app is opened or brought forward.
    case launch(bundleID: String)
    /// A binding's commands, in order.
    case run([CheatStep])

    /// The action brings something forward itself, so the app that was in
    /// front must not be given the keyboard back when the sheet closes.
    public var takesFocus: Bool {
        switch self {
        case .none: return false
        case .launch: return true
        case .run(let steps):
            return steps.contains { step in
                if case .link = step { return true }
                return false
            }
        }
    }
}

/// One command of a binding, as the app runs it.
public enum CheatStep: Equatable, Sendable {
    /// `aerospace <arguments>`.
    case aerospace([String])
    /// `exec-and-forget open grovekeys://…`: answered inside Grove Keys.
    case link(KeysURL)
    /// Any other `exec-and-forget`: its shell command.
    case shell(String)

    public init?(command: String) {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }
        guard first == "exec-and-forget" else {
            self = .aerospace(words)
            return
        }
        if words.count == 3, words[1] == "open", let link = URL(string: words[2]).flatMap(KeysURL.init) {
            self = .link(link)
            return
        }
        let shell = command.trimmingCharacters(in: .whitespaces).dropFirst(first.count)
            .trimmingCharacters(in: .whitespaces)
        guard !shell.isEmpty else { return nil }
        self = .shell(shell)
    }
}

/// A line of the sheet: the key on the left, what it does on the right.
public struct CheatRow: Equatable, Sendable, Identifiable {
    public var id: String
    /// "⌥ H", "Hyper Space", "⌥ 1 … 9".
    public var keys: String
    public var text: String
    /// What else the filter matches: the key and the command as the file
    /// has them ("alt-h focus left"), a launcher's bundle ID.
    public var detail: String
    public var action: CheatAction

    public init(id: String, keys: String, text: String, detail: String = "", action: CheatAction = .none) {
        self.id = id
        self.keys = keys
        self.text = text
        self.detail = detail
        self.action = action
    }
}

public struct CheatSection: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// One of the lists that aren't keys.toml's: the shell, macOS, Ghostty.
    public var fixed: Bool
    public var rows: [CheatRow]

    public init(id: String, title: String, fixed: Bool = false, rows: [CheatRow]) {
        self.id = id
        self.title = title
        self.fixed = fixed
        self.rows = rows
    }
}

public enum CheatSheet {
    /// Hyper (launchers, then main's `hyper-` bindings), each AeroSpace mode
    /// in the file's order (main first, without its Hyper bindings, the 1 … 9
    /// runs folded), then the fixed lists: the shell, macOS and, when
    /// `ghostty` has rows, Ghostty. A section without rows is left out.
    /// `appName` returns nil for an app that isn't installed.
    public static func sections(keys: KeysFile, ghostty: [CheatRow] = [],
                                appName: (String) -> String?) -> [CheatSection] {
        var hyper: [CheatRow] = []
        var launcherKeys: Set<String> = []
        for (key, bundleID) in keys.launch {
            launcherKeys.insert(key)
            let name = appName(bundleID)
            let short = String(bundleID.split(separator: ".").last ?? Substring(bundleID))
            hyper.append(CheatRow(
                id: "hyper/launch:" + key, keys: hyperKeys(key),
                text: name ?? short + " (not installed)", detail: bundleID,
                action: name == nil ? .none : .launch(bundleID: bundleID)))
        }

        var modes: [CheatSection] = []
        for section in keys.document.sections where section.path.count == 2 && section.path[0] == "aerospace" {
            let name = section.path[1], isMain = name == "main"
            var entries = section.entries
            if isMain {
                // A launcher wins over a Hyper binding on its key (Layers).
                for entry in entries {
                    guard let shortcut = Shortcut(aerospace: entry.key), shortcut.isHyper,
                          !launcherKeys.contains(shortcut.key) else { continue }
                    hyper.append(row(entry, id: "hyper/", keys: hyperKeys(shortcut.key)))
                }
                entries.removeAll { Shortcut(aerospace: $0.key)?.isHyper == true }
            }
            let byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            let folded = BindingRows.rows(mode: entries.map { (key: $0.key, value: $0.value) }, folded: true)
            let rows = folded.compactMap { line -> CheatRow? in
                guard let first = line.keys.first, let entry = byKey[first] else { return nil }
                let id = "mode:\(name)/"
                guard line.count > 1 else { return row(entry, id: id, keys: line.shortcuts) }
                // "Workspace 1" for the run's first key, said for all nine.
                let one = CommandWords.words(entry.value)
                let text = one.hasSuffix(" 1") ? one + " … 9" : line.action
                return CheatRow(id: id + first, keys: line.shortcuts, text: text,
                                detail: line.keys.joined(separator: " ") + " " + line.action)
            }
            let title = isMain ? "AeroSpace" : "AeroSpace · \(name.prefix(1).uppercased() + name.dropFirst()) mode"
            let mode = CheatSection(id: "mode:" + name, title: title, rows: rows)
            if isMain { modes.insert(mode, at: 0) } else { modes.append(mode) }
        }

        let all = [CheatSection(id: "hyper", title: "Hyper", rows: hyper)] + modes + [
            CheatSection(id: "shell", title: "Shell", fixed: true, rows: shell),
            CheatSection(id: "macos", title: "macOS", fixed: true, rows: macOS(keys.hyper)),
            CheatSection(id: "ghostty", title: "Ghostty", fixed: true, rows: ghostty),
        ]
        return all.filter { !$0.rows.isEmpty }
    }

    /// The rows that have every typed word in their key, their text, their
    /// detail or their section's title (the launcher's rule), in place; a
    /// section left without rows goes. Nothing typed keeps them all.
    public static func filter(_ sections: [CheatSection], _ query: String) -> [CheatSection] {
        let typed = TypedWords(query)
        guard !typed.isEmpty else { return sections }
        return sections.compactMap { section in
            var section = section
            section.rows = section.rows.filter {
                typed.areAll(in: [section.title, $0.keys, $0.text, $0.detail].joined(separator: " "))
            }
            return section.rows.isEmpty ? nil : section
        }
    }

    /// The keys fzf binds in zsh (config/zsh/conf.d/40-tools.zsh) and
    /// Ghostty's quick terminal (config/ghostty/config).
    static let shell = [
        CheatRow(id: "shell/history", keys: "⌃ R", text: "Search the history"),
        CheatRow(id: "shell/files", keys: "⌃ T", text: "Find a file"),
        CheatRow(id: "shell/folders", keys: "⌥ C", text: "Jump to a folder (left Option)"),
        CheatRow(id: "shell/quick", keys: "⌃ `", text: "Quick terminal, from anywhere"),
    ]

    /// macOS's own keys, and the two Grove Keys changes under them: ⌘Space is
    /// the Grove Launcher, not Spotlight, and the right ⌥ types characters
    /// (each while its setting in keys.toml's `[hyper]` says so).
    static func macOS(_ settings: HyperSettings) -> [CheatRow] {
        let space = settings.launcher == .cmdSpace
            ? CheatRow(id: "macos/launcher", keys: "⌘ Space", text: "Grove Launcher: apps and the Grove menu",
                       detail: "open app find search spotlight")
            : CheatRow(id: "macos/spotlight", keys: "⌘ Space", text: "Spotlight")
        var rows = [
            CheatRow(id: "macos/shot-screen", keys: "⇧⌘ 3", text: "Screenshot of the screen"),
            CheatRow(id: "macos/shot-area", keys: "⇧⌘ 4", text: "Screenshot of an area or a window"),
            CheatRow(id: "macos/shot-options", keys: "⇧⌘ 5", text: "Screenshot and recording options"),
            CheatRow(id: "macos/emoji", keys: "⌃⌘ Space", text: "Emoji and symbols"),
            space,
            CheatRow(id: "macos/lock", keys: "⌃⌘ Q", text: "Lock the screen"),
            CheatRow(id: "macos/dictation", keys: "Fn Fn", text: "Dictation (the Fn/Globe key, twice)"),
        ]
        if settings.rightOption == .characters {
            rows.append(CheatRow(id: "macos/right-option", keys: "Right ⌥ + key",
                                 text: "@ € and other characters (left ⌥: shortcuts)",
                                 detail: "right option alt symbols at euro"))
        }
        return rows
    }

    private static func hyperKeys(_ key: String) -> String {
        "Hyper " + Shortcut(modifiers: [], key: key).symbols
    }

    /// A binding's row: its trailing comment says what it does when it has
    /// one, the command in words otherwise.
    private static func row(_ entry: TomlEntry, id: String, keys: String) -> CheatRow {
        let commands: [String]
        switch entry.value {
        case .string(let command): commands = [command]
        case .array(let list): commands = list
        case .int, .bool: commands = []
        }
        let comment = (entry.trailingComment ?? "").drop { $0 == "#" || $0 == " " }
        // The sheet's own link would only put it away: Return does that anyway.
        let steps = commands.compactMap(CheatStep.init(command:)).filter { $0 != .link(.cheatSheet) }
        return CheatRow(
            id: id + entry.key, keys: keys,
            text: comment.isEmpty ? CommandWords.words(entry.value) : comment.prefix(1).uppercased() + comment.dropFirst(),
            detail: entry.key + " " + commands.joined(separator: ", "),
            action: steps.isEmpty ? .none : .run(steps))
    }
}

/// An AeroSpace command in plain words, for the cheat sheet: "focus left" is
/// "Focus left", `move-node-to-workspace 3` "Move to workspace 3". A command
/// it has no words for is shown as it is written.
public enum CommandWords {
    /// A list's commands joined by commas; the `mode main` that ends a
    /// service-mode binding isn't said.
    public static func words(_ value: TomlValue) -> String {
        switch value {
        case .string(let command):
            return words(command: command)
        case .array(let commands):
            let said = commands.filter { $0.trimmingCharacters(in: .whitespaces) != "mode main" }
            return (said.isEmpty ? commands : said).map(words(command:)).joined(separator: ", ")
        case .int(let n):
            return String(n)
        case .bool(let b):
            return String(b)
        }
    }

    public static func words(command: String) -> String {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first else { return command }
        let args = Array(words.dropFirst())
        switch (first, args.count) {
        case ("move-node-to-workspace", 1): return "Move to workspace \(args[0])"
        case ("workspace-back-and-forth", 0): return "Previous workspace"
        case ("move-workspace-to-monitor", _) where args.last == "next" || args.last == "prev":
            return "Move workspace to the \(args.last == "next" ? "next" : "previous") monitor"
        case ("mode", 1): return capitalized(args[0]) + " mode"
        case ("layout", _) where args.first == "tiles": return "Tiles layout"
        case ("layout", _) where args.first == "accordion": return "Accordion layout"
        case ("layout", 2) where Set(args) == ["floating", "tiling"]: return "Float or tile"
        case ("resize", 2) where args[1].hasPrefix("-") || args[1].hasPrefix("+"):
            // "smart" is whichever way the window is laid out.
            let what = args[0] == "smart" ? "" : args[0] + " "
            return (args[1].hasPrefix("-") ? "Shrink " : "Grow ") + what + "by \(args[1].dropFirst())"
        case ("flatten-workspace-tree", 0): return "Reset the layout"
        case ("close-all-windows-but-current", 0): return "Close the other windows"
        case ("exec-and-forget", _):
            if case .link(let link) = CheatStep(command: command), let name = linkName(link) { return name }
            return command
        default:
            // "join-with right", "reload-config": the words are the command's own.
            let plain = words.allSatisfy { word in
                word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && !word.hasPrefix("-")
            }
            return plain ? capitalized(words.joined(separator: " ").replacingOccurrences(of: "-", with: " ")) : command
        }
    }

    /// A `grovekeys://` link by name; nil for a menu row's (its id says nothing).
    static func linkName(_ link: KeysURL) -> String? {
        switch link {
        case .launcher: return "Grove Launcher"
        case .cheatSheet: return "Cheat sheet"
        case .groveMenu: return "Grove menu"
        case .appMenu: return "App menu"
        case .menu: return "Grove Keys menu"
        case .row: return nil
        }
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
