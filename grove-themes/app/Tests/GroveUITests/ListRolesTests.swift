import Foundation
@testable import GroveThemesCore
import SwiftUI
import Testing
@testable import GroveUI

/// The list roles (a file list's three fills and the ink of hidden items):
/// in every theme file, read by `ThemeColors`, drawn through `ListRoles`.
@Suite struct ListRolesTests {
    static let roles = ["list_selected", "list_selected_inactive", "list_hover", "hidden_ink"]
    static let schemes = ["dark-hard", "dark-medium", "dark-soft", "light-hard", "light-medium", "light-soft"]

    /// A theme file's `name = #RRGGBB` lines; nil when the package isn't in
    /// the repo (the installer's tests build a copy of app/ alone).
    static func themeFile(_ scheme: String) -> [String: String]? {
        let file = GroveUITests.package.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("grove-dotfiles/theme/everforest-\(scheme)")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var colors = [String: String]()
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { colors[parts[0]] = parts[1] }
        }
        return colors
    }

    /// Each of the six theme files has the four roles, and `ThemeColors`
    /// carries them as the file wrote them.
    @Test func theRolesAreInEveryScheme() throws {
        for scheme in Self.schemes {
            guard let colors = Self.themeFile(scheme) else { return }
            for role in Self.roles {
                #expect(colors[role].flatMap(RGB.init(hex:)) != nil, "\(scheme) has no \(role)")
            }
            let appearance = scheme.hasPrefix("dark") ? "dark" : "light"
            let theme = try #require(ThemeColors(palette: Palette(name: scheme, appearance: appearance, colors: colors)))
            #expect(theme.listSelected == colors["list_selected"].flatMap(RGB.init(hex:)), "\(scheme)")
            #expect(theme.listSelectedInactive == colors["list_selected_inactive"].flatMap(RGB.init(hex:)), "\(scheme)")
            #expect(theme.listHover == colors["list_hover"].flatMap(RGB.init(hex:)), "\(scheme)")
            #expect(theme.hiddenInk == colors["hidden_ink"].flatMap(RGB.init(hex:)), "\(scheme)")
        }
    }

    /// The three fills are three colours, none of them the background, in
    /// every scheme: a pointer, a selection and the other pane's selection
    /// can be told apart. (How strong each is: grove-dotfiles' theme.bats.)
    @Test func theFillsAreThreeColoursInEveryScheme() throws {
        for scheme in Self.schemes {
            guard let colors = Self.themeFile(scheme) else { return }
            let appearance = scheme.hasPrefix("dark") ? "dark" : "light"
            let theme = try #require(ThemeColors(palette: Palette(name: scheme, appearance: appearance, colors: colors)))
            let fills = [theme.listSelected, theme.listSelectedInactive, theme.listHover]
            for (i, fill) in fills.enumerated() {
                #expect(fill != theme.bg0, "\(scheme)")
                #expect(!fills[..<i].contains(fill), "\(scheme)")
            }
        }
    }

    /// A CLI older than the roles sends none: the fills stand in as bg3, bg2
    /// and bg1 (still in order of strength) and hidden items take `dim`.
    @Test func anOlderCLIsPaletteStandsIn() throws {
        var hex = [
            "bg0": "#000000", "bg1": "#111111", "bg2": "#222222", "bg3": "#333333",
            "fg": "#EEEEEE", "grey1": "#888888", "red": "#FF0000", "orange": "#FF8800",
            "yellow": "#FFFF00", "green": "#00FF00", "aqua": "#00FFFF", "blue": "#0000FF",
            "purple": "#FF00FF", "dim": "#777777",
        ]
        for appearance in ["dark", "light"] {
            let old = try #require(ThemeColors(palette: Palette(name: "X", appearance: appearance, colors: hex)))
            #expect(old.listSelected == old.bg3)
            #expect(old.listSelectedInactive == old.bg2)
            #expect(old.listHover == old.bg1)
            #expect(old.hiddenInk == old.dim)
        }
        hex["list_selected"] = "#ABCDEF"
        hex["hidden_ink"] = ""
        let sent = try #require(ThemeColors(palette: Palette(name: "X", appearance: "light", colors: hex)))
        #expect(sent.listSelected == RGB(hex: "#ABCDEF"))
        #expect(sent.hiddenInk == sent.dim)
    }

    /// What a list draws with: the active pane's selection, the other pane's,
    /// the row under the pointer, a hidden item's name.
    @Test func theViewsColoursAreTheRoles() {
        let theme = ThemeColors.fallback
        #expect(theme.listSelectionFill(active: true) == Color(theme.listSelected))
        #expect(theme.listSelectionFill(active: false) == Color(theme.listSelectedInactive))
        #expect(theme.listHoverFill == Color(theme.listHover))
        #expect(theme.hiddenText == Color(theme.hiddenInk))
        #expect(theme.listSelected == theme.bg3)
        #expect(theme.listSelectedInactive == theme.bg2)
        #expect(theme.listHover == theme.bg1)
        #expect(theme.hiddenInk == theme.grey1)
    }
}
