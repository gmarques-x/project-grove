import Foundation

/// What a symbolic link's row writes after its name: a quiet "→" and where
/// the link points, as the link itself says it (`readlink`, as `ls -l`
/// shows it), never resolved.
public enum LinkText {
    /// The Kind column of a link: never "Alias" (that is a Finder alias,
    /// a different thing, which keeps what macOS calls it).
    public static func kind(isBroken: Bool) -> String { isBroken ? "Broken link" : "Symbolic link" }

    /// Whether a link whose following failed with `followError` (an errno,
    /// nil when it succeeded) is broken: what it points at is missing, or
    /// the chain loops. Not being allowed to look is not broken.
    public static func isBroken(followError: Int32?) -> Bool {
        guard let followError else { return false }
        return followError != EACCES && followError != EPERM
    }

    /// The target as the row writes it: an absolute one inside `home` (or
    /// `home` itself) from "~", anything else as it is stored, a relative
    /// one staying relative.
    public static func shown(_ target: String, home: String) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard target.hasPrefix("/"), home.hasPrefix("/"), home != "/" else { return target }
        if target == home { return "~" }
        if target.hasPrefix(home + "/") { return "~" + target.dropFirst(home.count) }
        return target
    }

    /// The arrow before the target, and the space after it.
    public static let arrow = "→ "

    /// At least this many characters of a target are kept, or none.
    public static let least = 4

    /// How many characters of the name and of the target fit in the row.
    public struct Fit: Equatable, Sendable {
        public let nameLength: Int
        /// nil: the target is not drawn (and neither is its arrow).
        public let targetLength: Int?

        public init(nameLength: Int, targetLength: Int?) {
            self.nameLength = nameLength
            self.targetLength = targetLength
        }
    }

    /// What fits in `room` points of characters `advance` wide (the face is
    /// monospaced): the name whole when it can be, then `gap`, the arrow
    /// and the target, cut first (`middleCut`) and gone once fewer than
    /// `least` of its characters would be left. The name is cut only when
    /// it doesn't fit alone, as it always was.
    public static func fit(nameLength: Int, targetLength: Int, room: Double, advance: Double, gap: Double) -> Fit {
        let fits = max(Int(room / advance), 0)
        guard nameLength <= fits, targetLength > 0 else {
            return Fit(nameLength: min(nameLength, fits), targetLength: nil)
        }
        let left = room - Double(nameLength) * advance - gap
        let characters = left > 0 ? Int(left / advance) - arrow.count : 0
        guard characters >= min(targetLength, least) else { return Fit(nameLength: nameLength, targetLength: nil) }
        return Fit(nameLength: nameLength, targetLength: min(characters, targetLength))
    }

    /// `text` cut to at most `count` characters, "…" in its middle. Unlike
    /// a name's cut, no extension is kept: a path's end is no extension.
    public static func middleCut(_ text: String, to count: Int) -> String {
        let characters = Array(text)
        guard characters.count > count else { return text }
        guard count > 0 else { return "" }
        let room = count - 1
        let tail = room / 2
        let head = room - tail
        return String(characters[..<head]) + "…" + String(characters[(characters.count - tail)...])
    }
}
