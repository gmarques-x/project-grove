import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// `GroveKeys --render-panel <name> <out.png> [scheme] [left|right]`: draws
/// a bar panel on its sample data (`BarPanelData.sample`) to a PNG at 2x, on
/// a bg0 ground with a 12 pt margin, and exits. For checking a panel against
/// the approved mock-ups in a dark and a light scheme without the live UI:
/// no window is ever shown, the app is never started (activation policy
/// `.prohibited`), nothing is read from the Mac.
///
/// - `scheme`: a scheme's name as grove-themes knows it (`dark-medium`, the
///   default; `light-medium`, …), or the path of a theme file
///   (`grove-dotfiles/theme/everforest-light-medium`).
/// - `left` / `right`: draw that top corner as it follows a window border's
///   (the clock at the bar's right end, the Grove menu at its left).
@MainActor
enum BarPanelRender {
    static let margin = GroveSpace.s12

    static func run(_ arguments: [String]) -> Never {
        guard arguments.count >= 2, arguments.count <= 4 else {
            fail("usage: GroveKeys --render-panel <name> <out.png> [scheme] [left|right]")
        }
        guard let registration = BarPanels.named(arguments[0]) else {
            fail("no panel named \(arguments[0]); there are: " + BarPanels.all.map(\.name).joined(separator: ", "))
        }
        var scheme = "dark-medium", corner: String?
        for argument in arguments.dropFirst(2) {
            if argument == "left" || argument == "right" { corner = argument } else { scheme = argument }
        }
        let colors = theme(scheme)
        let radius = WindowBorders.cornerRadius(width: WindowBorders.defaultWidth)
        let shape = BarPanelShape(topLeading: corner == "left" ? radius : GroveRadius.card,
                                  topTrailing: corner == "right" ? radius : GroveRadius.card)

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let view = registration.sample()
            .environment(\.theme, colors)
            .environment(\.panelStandIns, true)
            .environment(\.barPanelShape, shape)
            .padding(margin)
            .background(Color(colors.bg0))
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let size = NSSize(width: ceil(fitting.width), height: ceil(fitting.height))
        // Far off every screen, and never ordered in.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        // SwiftUI settles its layout over a few turns of the run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { fail("cannot make the image") }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("cannot encode the image") }
        do {
            try png.write(to: URL(fileURLWithPath: arguments[1]))
        } catch {
            fail("cannot write \(arguments[1]): \(error.localizedDescription)")
        }
        print("\(arguments[1]) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        exit(0)
    }

    /// A scheme's colours: from a theme file when `scheme` is a path, else
    /// from `grove-themes list --json`.
    private static func theme(_ scheme: String) -> ThemeColors {
        if scheme.contains("/") {
            guard let text = try? String(contentsOfFile: scheme, encoding: .utf8) else { fail("\(scheme): can't be read") }
            var colors: [String: String] = [:]
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { colors[parts[0]] = parts[1] }
            }
            let light = URL(fileURLWithPath: scheme).lastPathComponent.contains("light")
            guard let theme = ThemeColors(palette: Palette(name: scheme, appearance: light ? "light" : "dark",
                                                           colors: colors)) else {
                fail("\(scheme): not a theme file")
            }
            return theme
        }
        let environment = ProcessInfo.processInfo.environment
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/grove-themes").path
        let answer = Subprocess.run(cli, ["list", "--json"], timeout: 10)
        guard answer.status == 0, let list = try? JSONDecoder().decode(SchemeList.self, from: Data(answer.output.utf8))
        else { fail("grove-themes didn't list the schemes; give a theme file's path instead") }
        guard let theme = list.palettes[scheme].flatMap(ThemeColors.init(palette:)) else {
            fail("no scheme named \(scheme); there are: " + list.schemes.joined(separator: ", "))
        }
        return theme
    }
}
