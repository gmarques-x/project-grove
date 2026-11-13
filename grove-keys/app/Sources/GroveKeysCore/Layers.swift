import Foundation
import GroveThemesCore

public enum BindingKind: Sendable {
    case workspace, focusMove, launcher, layout, mode, other

    /// Palette key name (grove-dotfiles/theme/*).
    public var tint: String {
        switch self {
        case .workspace: return "green"
        case .focusMove: return "aqua"
        case .launcher: return "blue"
        case .layout: return "yellow"
        case .mode: return "orange"
        case .other: return "fg"
        }
    }
}

public struct KeyBinding: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case launcher(bundleID: String)
        case aerospace(mode: String, key: String)
    }

    public var key: String
    /// The few letters a cap has room for: "ws 1", "← focus", "Ghostty".
    public var label: String
    /// What the key does in words, as the cheat sheet says it: "Workspace
    /// 1", "Focus left", "opens Ghostty". For the tooltip and VoiceOver.
    public var words: String
    public var kind: BindingKind
    public var source: Source
    public var conflict: Bool
    public var missingApp: Bool

    public init(key: String, label: String, words: String = "", kind: BindingKind, source: Source,
                conflict: Bool = false, missingApp: Bool = false) {
        self.key = key
        self.label = label
        self.words = words
        self.kind = kind
        self.source = source
        self.conflict = conflict
        self.missingApp = missingApp
    }
}

/// One drawn keyboard: a modifier set (or a non-main mode) and its bindings.
public struct Layer: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Keyed by the AeroSpace key name without modifiers ("1", "h", "semicolon").
    /// In a non-main mode's layer, an entry that has modifiers (alt-shift-h
    /// join-with left) would collide with a plain key of the same name, so it
    /// is keyed by the full shortcut string ("alt-shift-h"). The keyboard view
    /// shows only the bare-key entries on caps and lists the rest.
    public var bindings: [String: KeyBinding]

    public init(id: String, title: String, bindings: [String: KeyBinding] = [:]) {
        self.id = id
        self.title = title
        self.bindings = bindings
    }
}

public enum Layers {
    /// Order: Hyper, Option, Option+Shift, other modifier sets in main mode (file
    /// order), then each non-main mode. Ids: "hyper", "alt", "alt-shift", other
    /// sets as their AeroSpace prefix ("ctrl-alt"), "mode:<name>".
    /// A launcher wins over a `hyper-` binding on the same key; both are marked
    /// `conflict`, and the AeroSpace one appears only in the Bindings rows.
    /// `appName` returns nil for an app that isn't installed.
    public static func build(from keys: KeysFile, appName: (String) -> String?) -> [Layer] {
        var layers = [
            Layer(id: "hyper", title: "Hyper"),
            Layer(id: "alt", title: "Option"),
            Layer(id: "alt-shift", title: "Option+Shift"),
        ]
        func index(_ id: String, title: String) -> Int {
            if let i = layers.firstIndex(where: { $0.id == id }) { return i }
            layers.append(Layer(id: id, title: title))
            return layers.count - 1
        }

        let modes = keys.modes
        var launcherKeys: Set<String> = []
        for (key, bundleID) in keys.launch {
            let name = appName(bundleID)
            let label = name ?? String(bundleID.split(separator: ".").last ?? Substring(bundleID))
            layers[0].bindings[key] = KeyBinding(
                key: key, label: label, words: name.map { "opens " + $0 } ?? label + ", not installed",
                kind: .launcher,
                source: .launcher(bundleID: bundleID), missingApp: name == nil)
            launcherKeys.insert(key)
        }

        for mode in modes where mode.name == "main" {
            for (text, value) in mode.bindings {
                guard let sc = Shortcut(aerospace: text) else { continue }
                let (label, kind) = CommandLabel.label(value)
                let binding = KeyBinding(key: sc.key, label: label, words: CommandWords.words(value), kind: kind,
                                         source: .aerospace(mode: mode.name, key: text))
                let i: Int
                if sc.isHyper {
                    if launcherKeys.contains(sc.key) {
                        layers[0].bindings[sc.key]?.conflict = true
                        continue
                    }
                    i = 0
                } else if sc.modifiers == [.alt] {
                    i = 1
                } else if sc.modifiers == [.alt, .shift] {
                    i = 2
                } else {
                    let prefix = String(sc.aerospace.dropLast(sc.key.count + 1))
                    // Only the modifiers' glyphs, cut before the space: the key's legend never shows.
                    let written = Shortcut(modifiers: sc.modifiers, key: "x").symbols(using: .us)
                    let title = String(written.prefix { $0 != " " })
                    i = sc.modifiers.isEmpty ? index("none", title: "No modifier") : index(prefix, title: title)
                }
                layers[i].bindings[sc.key] = binding
            }
        }

        for mode in modes where mode.name != "main" {
            var layer = Layer(id: "mode:" + mode.name, title: mode.name.prefix(1).uppercased() + mode.name.dropFirst())
            for (text, value) in mode.bindings {
                let (label, kind) = CommandLabel.label(value)
                let sc = Shortcut(aerospace: text)
                let bare = sc?.modifiers.isEmpty ?? true
                let key = bare ? (sc?.key ?? text) : text
                layer.bindings[key] = KeyBinding(key: key, label: label, words: CommandWords.words(value), kind: kind,
                                                 source: .aerospace(mode: mode.name, key: text))
            }
            layers.append(layer)
        }
        return layers
    }
}

/// What VoiceOver says for a drawn key.
public enum CapWords {
    /// "T, opens Ghostty", "2, Workspace 2", "Q, free"; a modifier cap
    /// (`isModifier`) is its legend alone. The space bar's legend is empty.
    public static func spoken(legend: String, binding: KeyBinding?, isModifier: Bool = false) -> String {
        let key = legend.isEmpty ? "space" : (legend.count == 1 ? legend.uppercased() : legend)
        if isModifier { return key }
        guard let binding else { return key + ", free" }
        var words = key + ", " + (binding.words.isEmpty ? binding.label : binding.words)
        if binding.conflict { words += ", also bound in AeroSpace" }
        return words
    }
}

public enum CommandLabel {
    private static let arrows = ["left": "←", "down": "↓", "up": "↑", "right": "→"]

    public static func label(_ value: TomlValue) -> (String, BindingKind) {
        switch value {
        case .string(let s):
            return label(command: s)
        case .array(let items):
            let pick = items.first { $0.trimmingCharacters(in: .whitespaces) != "mode main" } ?? items.first
            return pick.map(label(command:)) ?? ("", .other)
        case .int(let n):
            return (String(n), .other)
        case .bool(let b):
            return (String(b), .other)
        }
    }

    private static func label(command: String) -> (String, BindingKind) {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first else { return ("", .other) }
        let args = Array(words.dropFirst())
        let dir = args.first.flatMap { arrows[$0] }
        switch first {
        case "workspace":
            if let n = args.first { return ("ws \(n)", .workspace) }
        case "move-node-to-workspace":
            if let n = args.first { return ("→ ws \(n)", .workspace) }
        case "workspace-back-and-forth":
            return ("back & forth", .workspace)
        case "move-workspace-to-monitor":
            return ("→ monitor", .workspace)
        case "focus":
            if let d = dir { return ("\(d) focus", .focusMove) }
        case "move":
            if let d = dir { return ("\(d) move", .focusMove) }
        case "join-with":
            if let d = dir { return ("join \(d)", .focusMove) }
        case "resize":
            if let amount = args.last {
                if amount.hasPrefix("-") { return ("resize −", .layout) }
                if amount.hasPrefix("+") { return ("resize +", .layout) }
            }
        case "layout":
            switch args.first {
            case "tiles": return ("tiles", .layout)
            case "accordion": return ("accordion", .layout)
            case "floating": return ("float/tile", .layout)
            default: return ("layout", .layout)
            }
        case "fullscreen":
            return ("fullscreen", .layout)
        case "mode":
            if let m = args.first { return (m, .mode) }
        case "reload-config":
            return ("reload", .mode)
        case "flatten-workspace-tree":
            return ("reset layout", .mode)
        case "close-all-windows-but-current":
            return ("close others", .mode)
        case "exec-and-forget":
            // Not "exec-and-forget": a Grove Keys link by its name, as the
            // cheat sheet has it ("Cheat sheet"); any other, what it runs.
            switch CheatStep(command: command) {
            case .link(let link):
                return (CommandWords.linkName(link) ?? "menu row", .other)
            case .shell(let shell):
                return (shell, .other)
            case .aerospace, nil:
                break
            }
        default:
            break
        }
        return (first, .other)
    }
}
