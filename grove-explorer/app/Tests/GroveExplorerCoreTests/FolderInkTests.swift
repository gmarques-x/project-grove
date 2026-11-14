import Foundation
import GroveExplorerCore
import GroveThemesCore
import Testing

/// The Grove folder's colour: the scheme's orange (the owner's pick,
/// 2026-11-14; it was the palette's blue), in the list, the sidebar and the
/// path bar alike.
struct FolderInkTests {
    /// A scheme's palette, read from grove-dotfiles/theme as grove-themes has it.
    private func theme(_ scheme: String) throws -> ThemeColors {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("grove-dotfiles/theme/everforest-\(scheme)")
        var colors: [String: String] = [:]
        for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].hasPrefix("#"), parts[1].hasPrefix("#") else { continue }
            colors[parts[0]] = String(parts[1].prefix(7))
        }
        let palette = Palette(name: scheme, appearance: scheme.hasPrefix("light") ? "light" : "dark", colors: colors)
        return try #require(ThemeColors(palette: palette))
    }

    @Test(arguments: ["dark-medium", "light-medium", "dark-hard", "light-soft"])
    func foldersAreTheSchemesOrange(scheme: String) throws {
        let theme = try theme(scheme)
        #expect(FolderInk.color(in: theme) == theme.orange)
        #expect(FolderInk.color(in: theme) != theme.blue)
    }
}
