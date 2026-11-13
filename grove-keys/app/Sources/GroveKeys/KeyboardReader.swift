import Carbon.HIToolbox
import Foundation
import GroveKeysCore

/// What the Mac says about its keyboard (spec §4, §5): the characters each
/// key types on an input source, and the built-in keyboard's shape. Reads
/// only; never chooses an input source. Main thread (the Text Input Sources
/// calls are main-thread only).
@MainActor
enum KeyboardReader {
    /// The key codes read: 0–50, every key that types a character (the
    /// others keep their names).
    private static let keyCodes = UInt16(0)...50

    /// The legends of the input source with this ID, or of the current one
    /// when nil. An input source without a key table (or none with that ID)
    /// gives the US legends.
    static func legends(inputSourceID: String? = nil) -> Legends {
        let layout: TypingLayout?
        if let inputSourceID { layout = TypingLayout.installed(id: inputSourceID) } else { layout = TypingLayout.current() }
        guard let layout else { return .us }
        let keyboardType = UInt32(LMGetKbdType())
        var raw: [UInt16: RawTranslation] = [:]
        for code in keyCodes {
            raw[code] = RawTranslation(
                base: layout.text(keyCode: code, modifiers: 0, keyboardType: keyboardType),
                shift: layout.text(keyCode: code, modifiers: shiftKey, keyboardType: keyboardType))
        }
        return Legends(raw: raw)
    }

    /// ISO when macOS says the keyboard is ISO, ANSI otherwise (JIS too).
    static func detectedShape() -> KeyboardShape {
        KeyboardShape.from(layoutType: KBGetLayoutType(Int16(LMGetKbdType())))
    }
}
