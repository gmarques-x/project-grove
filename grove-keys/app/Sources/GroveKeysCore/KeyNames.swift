/// AeroSpace key names and the matching US ANSI virtual key codes.
public enum KeyNames {
    private static let table: [(String, UInt16)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
        ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
        ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22),
        ("5", 23), ("equal", 24), ("9", 25), ("7", 26), ("minus", 27), ("8", 28),
        ("0", 29), ("rightSquareBracket", 30), ("o", 31), ("u", 32),
        ("leftSquareBracket", 33), ("i", 34), ("p", 35), ("enter", 36), ("l", 37),
        ("j", 38), ("quote", 39), ("k", 40), ("semicolon", 41), ("backslash", 42),
        ("comma", 43), ("slash", 44), ("n", 45), ("m", 46), ("period", 47),
        ("tab", 48), ("space", 49), ("backtick", 50), ("backspace", 51), ("esc", 53),
        ("left", 123), ("right", 124), ("down", 125), ("up", 126),
    ]
    private static let byName = Dictionary(uniqueKeysWithValues: table)
    private static let byCode = Dictionary(uniqueKeysWithValues: table.map { ($0.1, $0.0) })

    public static func keyCode(_ name: String) -> UInt16? { byName[name] }
    public static func name(_ keyCode: UInt16) -> String? { byCode[keyCode] }
}
