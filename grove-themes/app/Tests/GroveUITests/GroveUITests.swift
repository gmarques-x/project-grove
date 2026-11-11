import Foundation
@testable import GroveThemesCore
import Testing
@testable import GroveUI

@Suite struct GroveUITests {
    /// The sixteen colours `ThemeColors` reads from a palette.
    static let keys = ["bg0", "bg1", "bg2", "bg3", "fg", "grey1", "red", "orange", "yellow", "green", "aqua",
                       "blue", "purple", "border", "on_accent", "dim"]

    /// grove-themes/app.
    static let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The fallback is what `grove-themes list --json` sends for dark-medium
    /// (the fixture GroveThemesCoreTests decodes).
    @Test func fallbackIsTheCLIsDarkMedium() throws {
        let fixture = Self.package.appendingPathComponent("Tests/GroveThemesCoreTests/Fixtures/list.json")
        let list = try GroveThemesClient.decoder.decode(SchemeList.self, from: Data(contentsOf: fixture))
        let palette = try #require(list.palettes["dark-medium"])
        #expect(Set(palette.colors.keys) == Set(Self.keys))
        #expect(ThemeColors.fallback == ThemeColors(palette: palette))
        #expect(ThemeColors.fallback.isDark)
    }

    /// And what the theme file itself says. Skipped when the package isn't in
    /// the repo (the installer's tests build a copy of app/ alone).
    @Test func fallbackIsTheThemeFilesDarkMedium() throws {
        let file = Self.package.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("grove-dotfiles/theme/everforest-dark-medium")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        var colors = [String: String]()
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { colors[parts[0]] = parts[1] }
        }
        for key in Self.keys { #expect(colors[key] != nil, "\(key) is not in the theme file") }
        #expect(ThemeColors.fallback == ThemeColors(palette: Palette(name: "Dark Medium", appearance: "dark",
                                                                     colors: colors)))
    }

    /// The owner's scale: radii 4/6/10/16, spacing 2 and a 4 pt grid.
    @Test func tokensAreTheScale() {
        #expect([GroveRadius.inline, GroveRadius.control, GroveRadius.card, GroveRadius.window] == [4, 6, 10, 16])
        #expect(GroveSpace.scale == [2, 4, 8, 12, 16, 24])
    }
}
