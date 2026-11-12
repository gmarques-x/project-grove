import Foundation

/// One entry the Bindings tab edits: a `[launch]` key or a binding in an
/// `[aerospace.<mode>]` table (its key text as written, e.g. "cmd-ctrl-alt-shift-t").
public enum BindingSlot: Hashable, Sendable {
    case launcher(key: String)
    case binding(mode: String, key: String)

    /// Where a recorded shortcut goes: a launcher row takes the key alone
    /// (Hyper is implied), a binding row the whole shortcut.
    /// False for a main-mode binding without ⌃, ⌥ or ⌘ (see `Shortcut.isSafeForMain`).
    public var isSafe: Bool {
        guard case .binding(let mode, let key) = self, mode == "main" else { return true }
        return Shortcut(aerospace: key)?.isSafeForMain ?? false
    }

    public static func recorded(_ shortcut: Shortcut, launcher: Bool, mode: String) -> BindingSlot {
        launcher ? .launcher(key: shortcut.key) : .binding(mode: mode, key: shortcut.aerospace)
    }
}

extension Shortcut {
    /// A main-mode binding is live in every app: without ⌃, ⌥ or ⌘ (a bare or
    /// shift-only key) AeroSpace would take that key from typing everywhere.
    public var isSafeForMain: Bool {
        !modifiers.isDisjoint(with: [.ctrl, .alt, .cmd])
    }

    /// ⌘Q and ⌘W are not recorded: while a row is recording they cancel it
    /// and go on to the app (quit, close the window), so recording can't
    /// trap the two keys that leave.
    public var leavesRecorder: Bool {
        modifiers == [.cmd] && (key == "q" || key == "w")
    }

    // NSEvent.ModifierFlags raw values (Core doesn't import AppKit).
    private static let flagBits: [(UInt, Modifier)] = [
        (1 << 17, .shift), (1 << 18, .ctrl), (1 << 19, .alt), (1 << 20, .cmd),
    ]

    /// From a key-down's virtual keycode and modifier flags, as the recorder
    /// sees it. Caps Lock, Fn and device bits are ignored; all four modifiers
    /// make a `hyper-` shortcut. Nil for a key with no AeroSpace name.
    public init?(keyCode: UInt16, flags: UInt) {
        guard let name = KeyNames.name(keyCode) else { return nil }
        let mods = Set(Self.flagBits.filter { flags & $0.0 != 0 }.map(\.1))
        self.init(modifiers: mods, key: name)
    }
}

extension Layers {
    /// Main-mode bindings with all four modifiers whose key also has a
    /// launcher: the launcher wins, so they never fire. Raw toml keys.
    public static func conflictingAerospaceKeys(_ keys: KeysFile) -> Set<String> {
        let launchers = Set(keys.launch.map(\.key))
        let main = keys.modes.first { $0.name == "main" }?.bindings ?? []
        return Set(main.compactMap { b in
            guard let sc = Shortcut(aerospace: b.key), sc.isHyper, launchers.contains(sc.key) else { return nil }
            return b.key
        })
    }

    /// The launcher keys on the other side of `conflictingAerospaceKeys`.
    public static func conflictingLaunchKeys(_ keys: KeysFile) -> Set<String> {
        Set(conflictingAerospaceKeys(keys).compactMap { Shortcut(aerospace: $0)?.key })
    }
}

extension BindingRows {
    /// The action text as typed in a row: "a, b" is a list, one item a string,
    /// nothing (or only commas) nil.
    public static func value(fromText text: String) -> TomlValue? {
        let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch items.count {
        case 0: return nil
        case 1: return .string(items[0])
        default: return .array(items)
        }
    }
}

extension HyperSettings {
    /// A millisecond field's text: a whole number ≥ 0, optionally followed by "ms".
    public static func milliseconds(_ text: String) -> Int? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("ms") { t = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        guard !t.isEmpty, t.allSatisfy(\.isASCII), t.allSatisfy(\.isNumber) else { return nil }
        return Int(t)
    }
}

public enum Monitors {
    public static let fixed = ["main", "secondary", "built-in"]

    /// A workspace's menu: AeroSpace's names, each connected display, then any
    /// saved target that isn't connected now; no duplicates.
    public static func choices(displays: [String], current: [String]) -> [String] {
        var seen: Set<String> = []
        return (fixed + displays + current).filter { seen.insert($0).inserted }
    }
}

extension KeysFile {
    private func entries(_ mode: String) -> [(key: String, value: TomlValue)] {
        modes.first { $0.name == mode }?.bindings ?? []
    }

    /// What already uses `slot`'s shortcut in its layer, other than `except`.
    /// The Hyper layer holds both the launchers and the main mode's `hyper-`
    /// bindings; spelled-out modifiers match `hyper-`.
    public func clashes(_ slot: BindingSlot, except: BindingSlot?) -> [BindingSlot] {
        var out: [BindingSlot] = []
        switch slot {
        case .launcher(let key):
            out += launch.filter { $0.key == key }.map { .launcher(key: $0.key) }
            out += entries("main").filter { Shortcut(aerospace: $0.key).map { $0.isHyper && $0.key == key } ?? false }
                .map { .binding(mode: "main", key: $0.key) }
        case .binding(let mode, let text):
            let wanted = Shortcut(aerospace: text)
            out += entries(mode).filter { $0.key == text || (wanted != nil && Shortcut(aerospace: $0.key) == wanted) }
                .map { .binding(mode: mode, key: $0.key) }
            if mode == "main", let wanted, wanted.isHyper {
                out += launch.filter { $0.key == wanted.key }.map { .launcher(key: $0.key) }
            }
        }
        return out.filter { $0 != except }
    }

    /// Gives an entry a new shortcut where it stands, after removing what it
    /// replaces. Launchers move to launchers, bindings within their mode; an
    /// unsafe main-mode shortcut changes nothing.
    public mutating func move(_ from: BindingSlot, to: BindingSlot, replacing: [BindingSlot]) {
        guard from != to, to.isSafe else { return }
        remove(replacing.filter { $0 != from })
        switch (from, to) {
        case (.launcher(let a), .launcher(let b)):
            rename(["launch"], a, to: b)
        case (.binding(let m, let a), .binding(let n, let b)) where m == n:
            rename(["aerospace", m], a, to: b)
        default:
            break
        }
    }

    /// A new binding from the row's text ("a, b" is a list); blank, or an
    /// unsafe main-mode shortcut, adds nothing.
    public mutating func add(_ slot: BindingSlot, command: String, replacing: [BindingSlot]) {
        guard case .binding(let mode, let key) = slot, slot.isSafe,
              let value = BindingRows.value(fromText: command) else { return }
        remove(replacing.filter { $0 != slot })
        setBinding(mode: mode, key: key, value: value)
    }

    public mutating func add(_ slot: BindingSlot, bundleID: String, replacing: [BindingSlot]) {
        guard case .launcher(let key) = slot, !bundleID.isEmpty else { return }
        remove(replacing.filter { $0 != slot })
        setLaunch(key: key, bundleID: bundleID)
    }

    /// A binding's new action text; blank changes nothing.
    public mutating func setCommand(_ slot: BindingSlot, _ text: String) {
        guard case .binding(let mode, let key) = slot, let value = BindingRows.value(fromText: text) else { return }
        setBinding(mode: mode, key: key, value: value)
    }

    public mutating func remove(_ slots: [BindingSlot]) {
        for slot in slots {
            switch slot {
            case .launcher(let key): removeLaunch(key: key)
            case .binding(let mode, let key): removeBinding(mode: mode, key: key)
            }
        }
    }
}
