/// The key that opens the Grove Launcher (`launcher` in keys.toml's `[hyper]`).
public enum LauncherKey: String, Sendable {
    /// ⌘Space, taken by the key tap before Spotlight sees it.
    case cmdSpace = "cmd-space"
    /// No key: the launcher opens from the Grove menu's link only.
    case none
}

/// The launcher's key in the key tap. Pure: the flags are a `CGEventFlags`
/// raw value. Space pressed with exactly ⌘ (either one, nothing else) is
/// swallowed and opens or closes the launcher; so are that press's repeats
/// and its key-up, also when ⌘ is let go first, so no app sees half a key.
public struct LauncherChord: Sendable {
    public enum Outcome: Equatable, Sendable {
        case pass
        case swallow
        /// Swallowed, and the launcher opens or closes.
        case toggle
    }

    public static let space: UInt16 = 49
    static let modifiers = RightOption.shift | RightOption.control | RightOption.option | RightOption.command

    /// Space is down and was taken.
    private var held = false

    public init() {}

    /// `disposition`: what the Hyper machine said. Anything but `.pass` is a
    /// Hyper key (Caps Lock held + Space), not the launcher.
    public mutating func handle(_ event: KeyEvent, flags: UInt64, key: LauncherKey,
                                disposition: Disposition) -> Outcome {
        guard event.keyCode == Self.space else { return .pass }
        switch event.kind {
        case .down:
            if held { return .swallow }
            guard key == .cmdSpace, disposition == .pass, flags & Self.modifiers == RightOption.command else {
                return .pass
            }
            // A repeat of a press that began before the tap did (or before a
            // reset): kept from Spotlight, but not a new press.
            if event.isRepeat { return .swallow }
            held = true
            return .toggle
        case .up:
            guard held else { return .pass }
            held = false
            return .swallow
        }
    }

    /// The tap stopped seeing keys for a moment, or the settings changed.
    public mutating func reset() {
        held = false
    }
}
