// One-off recorder for the legends test fixtures (not part of any target).
//
//   swift scripts/record-legends.swift --list
//   swift scripts/record-legends.swift com.apple.keylayout.US > Tests/GroveKeysCoreTests/Fixtures/legends-US.json
//
// For the input source with the given ID, prints what `UCKeyTranslate` gives
// for key codes 0–50 (every one has a name in `KeyNames`) with no modifiers
// and with Shift, dead keys not composed, as
// `{ "<keyCode>": { "base": "…", "shift": "…" }, … }`. Reads layouts by ID;
// never changes the selected input source.
import Carbon.HIToolbox
import Foundation

struct RawTranslation: Codable {
    var base: String?
    var shift: String?
}

func sources(_ properties: [CFString: Any]) -> [TISInputSource] {
    let list = TISCreateInputSourceList(properties as CFDictionary, true)?.takeRetainedValue()
    return (list as? [TISInputSource]) ?? []
}

func string(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

func translate(_ data: Data, keyCode: UInt16, modifiers: Int, keyboardType: UInt32) -> String? {
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
    guard status == noErr else { return nil }
    return String(utf16CodeUnits: units, count: count)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args == ["--list"] {
    let layouts = sources([kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any])
    for s in layouts {
        print(string(s, kTISPropertyInputSourceID) ?? "?", "\t", string(s, kTISPropertyLocalizedName) ?? "")
    }
    exit(args.isEmpty ? 1 : 0)
}

let keyboardType = UInt32(LMGetKbdType())
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

for id in args {
    guard let source = sources([kTISPropertyInputSourceID: id as CFString]).first,
          let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
        FileHandle.standardError.write("no key layout for \(id)\n".data(using: .utf8)!)
        exit(1)
    }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    var lines: [String] = []
    for code in UInt16(0)...50 {
        let raw = RawTranslation(
            base: translate(data, keyCode: code, modifiers: 0, keyboardType: keyboardType),
            shift: translate(data, keyCode: code, modifiers: shiftKey, keyboardType: keyboardType))
        let value = String(data: try encoder.encode(raw), encoding: .utf8)!
        lines.append("  \"\(code)\": \(value)")
    }
    print("{\n" + lines.joined(separator: ",\n") + "\n}")
}
