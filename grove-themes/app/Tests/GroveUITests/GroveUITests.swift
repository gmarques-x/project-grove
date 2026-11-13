import Foundation
@testable import GroveThemesCore
import SwiftUI
import Testing
@testable import GroveUI

@Suite struct GroveUITests {
    /// The twenty-two colours `ThemeColors` reads from a palette.
    static let keys = ["bg0", "bg1", "bg2", "bg3", "fg", "grey1", "red", "orange", "yellow", "green", "aqua",
                       "blue", "purple", "border", "on_accent", "dim", "lockup_ink", "hover",
                       "list_selected", "list_selected_inactive", "list_hover", "hidden_ink"]

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

    /// The stand-in for a CLI that doesn't send `lockup_ink` is what all six
    /// theme files say. Skipped outside the repo, as above.
    @Test func theWordmarksInkStandInIsTheThemeFiles() throws {
        let theme = Self.package.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("grove-dotfiles/theme")
        for appearance in ["dark", "light"] {
            for contrast in ["hard", "medium", "soft"] {
                let file = theme.appendingPathComponent("everforest-\(appearance)-\(contrast)")
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
                let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("lockup_ink") })
                let hex = try #require(line.split(separator: "=").last).trimmingCharacters(in: .whitespaces)
                #expect(RGB(hex: hex) == ThemeColors.lockupInk(dark: appearance == "dark"), "\(file.lastPathComponent)")
            }
        }
    }

    /// The owner's scale: radii 4/6/10/16, spacing 2 and a 4 pt grid, text
    /// 10/11/12/13/15.
    @Test func tokensAreTheScale() {
        #expect(GroveType.scale == [10, 11, 12, 13, 15])
        #expect([GroveRadius.inline, GroveRadius.control, GroveRadius.card, GroveRadius.window] == [4, 6, 10, 16])
        #expect(GroveSpace.scale == [2, 4, 8, 12, 16, 24])
    }

    /// The soft fills keep the strengths the dark schemes were tuned on.
    @Test func tintStrengthsAreTheTunedOnes() {
        #expect(TintStrength.banner.rawValue == 0.14)
        #expect(TintStrength.cap.rawValue == 0.16)
    }

    /// Grove's icons, and the SF Symbol each one is (the owner's choice from
    /// the renders of 2026-11-12).
    @Test func theIconsAreTheseSymbols() {
        #expect(GroveIcon.Name.allCases.map(\.symbol)
            == ["minus", "plus", "chevron.down", "checkmark", "return", "circle.fill",
                // The bar's panels.
                "cpu", "memorychip", "bolt.fill", "wifi", "cable.connector", "lock.shield", "wifi.slash",
                "speaker.wave.2.fill", "speaker.fill", "speaker.wave.3.fill", "speaker.slash.fill", "calendar",
                "arrow.down", "arrow.up", "chevron.right", "chevron.left", "doc.on.doc", "arrow.clockwise",
                "laptopcomputer", "airpodspro", "display", "headphones", "airplayaudio",
             "cable.connector.horizontal", "hifispeaker", "mic", "paintpalette", "keyboard",
                "arrow.triangle.2.circlepath", "book", "info.circle", "power", "menubar.rectangle", "folder",
                // Grove Explorer.
                "chevron.up", "xmark", "eject.fill", "trash", "icloud", "cloud", "rectangle", "rectangle.split.2x1",
                "magnifyingglass", "exclamationmark.triangle.fill", "server.rack"])
    }

    /// The bar panels' outline is the palette's orange, in every scheme.
    @Test func thePanelOutlineIsThePalettesOrange() {
        #expect(ThemeColors.fallback.panelOutline == Color(ThemeColors.fallback.orange))
    }

    // MARK: WindowHeaderMetrics

    /// The buttons as macOS 27 puts them in an 800 × 600 window without a
    /// title bar: 14 pt, 9 below the top, at x = 9, 32 and 55.
    @Test func theHeaderIsMeasuredFromTheWindowsButtons() {
        let buttons = [9.0, 32, 55].map { CGRect(x: $0, y: 577, width: 14, height: 14) }
        let metrics = WindowHeaderMetrics(windowHeight: 600, buttons: buttons)
        #expect(metrics == WindowHeaderMetrics(centerY: 16, buttonsEnd: 69))
        #expect(metrics == .standard)
        #expect(metrics.bandHeight == 32)
        #expect(metrics.nameLeading == 85)
        // An older title bar: 28 pt, the buttons centred at 14 and ending at 61.
        let older = WindowHeaderMetrics(windowHeight: 400, buttons: [7.0, 27, 47].map {
            CGRect(x: $0, y: 379, width: 14, height: 14)
        })
        #expect(older == WindowHeaderMetrics(centerY: 14, buttonsEnd: 61))
        #expect(older.bandHeight == 28)
    }

    @Test func aWindowWithoutUsableButtonsWearsTheStandardHeader() {
        #expect(WindowHeaderMetrics(windowHeight: 600, buttons: []) == .standard)
        #expect(WindowHeaderMetrics(windowHeight: 600, buttons: [.zero]) == .standard)
        // Not laid out yet: the buttons at the bottom of a window with no height.
        #expect(WindowHeaderMetrics(windowHeight: 0, buttons: [CGRect(x: 9, y: 577, width: 14, height: 14)]) == .standard)
        #expect(WindowHeaderMetrics(windowHeight: 600, buttons: [CGRect(x: 700, y: 577, width: 14, height: 14)]) == .standard)
    }

    // MARK: GroveSegmented

    @Test func arrowsStepToTheNextEnabledSegmentAndStopAtTheEnds() {
        let all = [true, true, true]
        #expect(GroveSegmentedStep.index(from: 0, step: 1, enabled: all) == 1)
        #expect(GroveSegmentedStep.index(from: 1, step: -1, enabled: all) == 0)
        #expect(GroveSegmentedStep.index(from: 2, step: 1, enabled: all) == nil)
        #expect(GroveSegmentedStep.index(from: 0, step: -1, enabled: all) == nil)
        // The key editor off the Hyper layer: Launcher can't be chosen.
        #expect(GroveSegmentedStep.index(from: 1, step: -1, enabled: [false, true, true]) == nil)
        #expect(GroveSegmentedStep.index(from: 0, step: 1, enabled: [true, false, true]) == 2)
        #expect(GroveSegmentedStep.index(from: nil, step: 1, enabled: [false, true, true]) == 1)
        #expect(GroveSegmentedStep.index(from: nil, step: -1, enabled: [false, false]) == nil)
        #expect(GroveSegmentedStep.index(from: 7, step: 1, enabled: all) == 0)
        #expect(GroveSegmentedMetrics.disabledOpacity == 0.4)
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
