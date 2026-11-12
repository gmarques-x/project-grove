import SwiftUI

/// One of Grove's icons: an SF Symbol, set like the text beside it.
///
/// Decided by the owner from comparison renders on 2026-11-12: Grove's icons
/// are SF Symbols, not characters typed in the text face (− + ▾ ✓ ↩ ●, as
/// they were until then). Key legends (⌥ ⇧ ⌘ ← ↩ in a key's name or a hint)
/// are text and stay text; Grove's own marks are shapes (`PineShape`).
///
/// One sizing rule for every icon: the system font at the size of the text
/// the icon sits beside (a `GroveType` value), weight `.medium` (`.bold`
/// where that text is bold), in the colour of the role the caller gives it,
/// inline on the text's baseline. No icon is nudged or resized on its own;
/// a symbol that looks too big or too small is a question about the rule.
///
/// A symbol is as wide as it is drawn, not one character cell: where a column
/// has to line up, the caller gives the icon a fixed frame.
///
/// `GroveIcon(.remove, size: GroveType.label)` is a view, hidden from
/// VoiceOver (the control it sits in carries the label).
/// `GroveIcon.text(.menu, size: GroveType.label)` is the same drawing as a
/// `Text`, to join to the words it belongs to with `+`.
public struct GroveIcon: View {
    /// Every icon Grove uses, named by its job; the raw value is the SF
    /// Symbol's name. A new icon is a new case here, not a symbol name in a view.
    public enum Name: String, CaseIterable, Sendable {
        /// Take a row away (a binding row's button).
        case remove = "minus"
        /// Add one ("Add binding").
        case add = "plus"
        /// This opens a menu of values (`GroveSelectPill`, a Monitors cell).
        case menu = "chevron.down"
        /// The current one of several (a launcher row, a scheme tile).
        case current = "checkmark"
        /// Return runs this (the selected row of the searchable cheat sheet).
        case run = "return"
        /// A dot that carries a colour ("on"; the dot of `ThemeColors.marked`).
        case dot = "circle.fill"

        /// The SF Symbol's name.
        public var symbol: String { rawValue }
    }

    let name: Name
    let size: CGFloat
    let weight: Font.Weight

    /// `size`: the `GroveType` size of the text beside the icon.
    public init(_ name: Name, size: CGFloat, weight: Font.Weight = .medium) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Self.text(name, size: size, weight: weight).accessibilityHidden(true)
    }

    /// The icon as text, to join to its words (`Text("Escape ") + …`). The
    /// symbol says nothing to VoiceOver; label the control it is part of.
    public nonisolated static func text(_ name: Name, size: CGFloat, weight: Font.Weight = .medium) -> Text {
        Text(Image(systemName: name.symbol)).font(.system(size: size, weight: weight)).accessibilityLabel("")
    }
}
