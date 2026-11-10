import Foundation

public enum Hex {
    /// "#RRGGBB" → components in 0…1; anything else → nil.
    public static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 7, hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        return (red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255)
    }
}
