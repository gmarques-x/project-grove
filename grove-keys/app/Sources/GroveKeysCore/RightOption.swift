/// What the right Option key does (`right_option` in keys.toml's `[hyper]`).
public enum RightOptionMode: String, Sendable {
    /// It types the keyboard layout's Option characters (@ € …) and never
    /// runs a shortcut; the left Option key runs the shortcuts.
    case characters
    /// Both Option keys are alike, as macOS has them.
    case shortcuts
}

/// The rules for "the right Option key types characters". AeroSpace's hotkeys
/// can't tell the two Option keys apart and take ⌥2 before any app sees it,
/// so the key tap turns a right-Option key press into the character itself,
/// with no Option on it. Pure: the flags are a `CGEventFlags` raw value.
public enum RightOption {
    public static let shift: UInt64 = 0x2_0000
    public static let control: UInt64 = 0x4_0000
    public static let option: UInt64 = 0x8_0000
    public static let command: UInt64 = 0x10_0000
    /// The device's own bits (NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK):
    /// which of the two Option keys is down.
    public static let leftOption: UInt64 = 0x20
    public static let rightOption: UInt64 = 0x40

    /// A key-down, repeat or key-up that should become its character: only
    /// the right Option is down (with or without Shift), and the Hyper
    /// machine left the key alone. With the left Option, Command or Control
    /// it is a shortcut; with Hyper it is a Hyper key.
    public static func types(mode: RightOptionMode, flags: UInt64, disposition: Disposition) -> Bool {
        guard mode == .characters, disposition == .pass else { return false }
        guard flags & rightOption != 0, flags & option != 0 else { return false }
        return flags & (leftOption | command | control) == 0
    }

    /// The flags without Option, so no ⌥ hotkey matches the key.
    public static func withoutOption(_ flags: UInt64) -> UInt64 {
        flags & ~(option | rightOption)
    }

    /// What the layout gives for the key is something to type: not nothing,
    /// and not a control or function-key code (Tab, Return, Delete, Esc, the
    /// arrows, F1 …). Those keys stay Option combos: ⌥← still moves a word.
    public static func isText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F: return false
            case 0xF700...0xF7FF: return false  // AppKit's function-key codes
            default: return true
            }
        }
    }
}
