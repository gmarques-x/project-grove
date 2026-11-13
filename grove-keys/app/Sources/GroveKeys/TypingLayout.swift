import Carbon.HIToolbox
import Foundation

/// The current keyboard layout's table, for asking what a key types with
/// Option. Read on the main thread (the Text Input Sources calls are
/// main-thread only) and handed to the key tap's thread as plain bytes.
struct TypingLayout: Sendable {
    /// Posted (to every app) when another input source is chosen.
    static let changed = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    /// A `UCKeyboardLayout`.
    private let data: Data

    /// The layout of the current input source; for an input method (Pinyin,
    /// Kotoeri) the layout it types through. Nil when it has no table.
    @MainActor
    static func current() -> TypingLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return layout(of: source)
    }

    /// The layout of the installed input source with this ID
    /// (`com.apple.keylayout.Portuguese`), read without choosing it. Nil when
    /// there is none or it has no table.
    @MainActor
    static func installed(id: String) -> TypingLayout? {
        let filter = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return nil }
        return layout(of: source)
    }

    @MainActor
    private static func layout(of source: TISInputSource) -> TypingLayout? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.isEmpty ? nil : TypingLayout(data: data)
    }

    /// What the key types with Option (and Shift, Caps Lock) held; nil when
    /// the layout has nothing there. A dead key (⌥´ and ⌥~ on the Portuguese
    /// layout) gives its accent as a character of its own (¨ ˜) and doesn't
    /// wait for a letter: the tap sees one key at a time, and composing
    /// would mean taking over the next plain key press too. Composing still
    /// works as macOS does it, with the left Option or the layout's own
    /// accent keys.
    func optionText(keyCode: UInt16, shift: Bool, capsLock: Bool, keyboardType: UInt32) -> String? {
        var modifiers = optionKey
        if shift { modifiers |= shiftKey }
        if capsLock { modifiers |= alphaLock }
        return text(keyCode: keyCode, modifiers: modifiers, keyboardType: keyboardType)
    }

    /// What the key types with `modifiers` (Carbon's `shiftKey`,
    /// `optionKey`, `alphaLock`… as an event record has them) held, a dead
    /// key giving its accent alone (not composed); nil when it types
    /// nothing or the call fails. The one `UCKeyTranslate` call, for the
    /// right Option's characters and the caps' legends (`KeyboardReader`).
    func text(keyCode: UInt16, modifiers: Int, keyboardType: UInt32) -> String? {
        var deadKeys: UInt32 = 0
        var units = [UniChar](repeating: 0, count: 8)
        var count = 0
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let table = bytes.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                table.assumingMemoryBound(to: UCKeyboardLayout.self), keyCode, UInt16(kUCKeyActionDown),
                UInt32((modifiers >> 8) & 0xFF), keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeys, units.count, &count, &units)
        }
        guard status == noErr, count > 0 else { return nil }
        return String(utf16CodeUnits: units, count: count)
    }
}
