import Foundation

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
    public var label: String
    public var kind: BindingKind
    public var source: Source
    public var conflict: Bool
    public var missingApp: Bool

    public init(key: String, label: String, kind: BindingKind, source: Source,
                conflict: Bool = false, missingApp: Bool = false) {
        self.key = key
        self.label = label
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
                key: key, label: label, kind: .launcher,
                source: .launcher(bundleID: bundleID), missingApp: name == nil)
            launcherKeys.insert(key)
        }

        for mode in modes where mode.name == "main" {
            for (text, value) in mode.bindings {
                guard let sc = Shortcut(aerospace: text) else { continue }
                let (label, kind) = CommandLabel.label(value)
                let binding = KeyBinding(key: sc.key, label: label, kind: kind,
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
                    let title = Shortcut(modifiers: sc.modifiers, key: "x").symbols.replacingOccurrences(of: " X", with: "")
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
                layer.bindings[key] = KeyBinding(key: key, label: label, kind: kind,
                                                 source: .aerospace(mode: mode.name, key: text))
            }
            layers.append(layer)
        }
        return layers
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
        case "mode":
            if let m = args.first { return (m, .mode) }
        case "reload-config":
            return ("reload", .mode)
        case "flatten-workspace-tree":
            return ("reset layout", .mode)
        case "close-all-windows-but-current":
            return ("close others", .mode)
        default:
            break
        }
        return (first, .other)
    }
}
