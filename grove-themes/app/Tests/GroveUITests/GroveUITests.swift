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

    // MARK: FocusRing

    func key(_ code: UInt16, _ characters: String = "", command: Bool = false, control: Bool = false,
             option: Bool = false) -> FocusRing.Event {
        .key(code: code, characters: characters, command: command, control: control, option: option)
    }

    @Test func aWindowOpensWithoutAFocusRing() {
        #expect(!FocusRing().shown)
    }

    @Test func tabAndTheArrowsShowTheRing() {
        for code: UInt16 in [48, 123, 124, 125, 126] {
            var ring = FocusRing()
            ring.handle(key(code))
            #expect(ring.shown)
        }
        var ring = FocusRing()
        ring.handle(key(48, "\u{19}"))  // ⇧Tab
        #expect(ring.shown)
        ring = FocusRing()
        ring.handle(key(38, "j", control: true))
        #expect(ring.shown)
        ring = FocusRing()
        ring.handle(key(38, "\n", control: true))  // Ctrl+J as its control character
        #expect(ring.shown)
    }

    @Test func typingAndShortcutsDoNotShowTheRing() {
        var ring = FocusRing()
        ring.handle(key(38, "j"))
        ring.handle(key(36, "\r"))
        ring.handle(key(49, " "))
        ring.handle(key(53, "\u{1B}"))
        ring.handle(key(18, "1", command: true))
        ring.handle(key(48, "\t", option: true))  // AeroSpace's ⌥Tab
        ring.handle(key(123, command: true))
        ring.handle(key(0, "a", control: true))
        #expect(!ring.shown)
    }

    @Test func aClickOrClosingTheWindowHidesTheRing() {
        var ring = FocusRing()
        ring.handle(key(48))
        ring.handle(key(38, "j"))  // typing keeps it
        #expect(ring.shown)
        ring.handle(.mouseDown)
        #expect(!ring.shown)
        ring.handle(key(125))
        #expect(ring.shown)
        ring.handle(.windowClosed)
        #expect(!ring.shown)
    }
}
