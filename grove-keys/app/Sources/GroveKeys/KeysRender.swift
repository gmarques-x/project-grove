import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// `GroveKeys --render-keys <keyboard|cheatsheet> <out.png> [scheme] [iso|ansi] [inputSourceID]`:
/// draws the Keyboard tab or the Hyper cheat sheet on the sample keys.toml
/// (the tests' fixture, with a few launchers so the Hyper layer has bound
/// caps) to a PNG at 2x, and exits. The same conventions as
/// `--render-panel`: no window is shown, the app is never started
/// (activation policy `.prohibited`), the Caps Lock mapping is never touched.
///
/// - `scheme`: a scheme's name (`dark-medium`, the default) or a theme file's path.
/// - `iso` / `ansi`: the shape macOS would report (the sample's setting is
///   auto); the current keyboard's when left out.
/// - `inputSourceID`: the legends of that installed input source
///   (`com.apple.keylayout.Portuguese`), read without choosing it; the
///   current input source's when left out.
@MainActor
enum KeysRender {
    static func run(_ arguments: [String]) -> Never {
        let usage = "usage: GroveKeys --render-keys <keyboard|cheatsheet> <out.png> [scheme] [iso|ansi] [inputSourceID]"
        guard arguments.count >= 2, arguments.count <= 5, ["keyboard", "cheatsheet"].contains(arguments[0]) else {
            fail(usage)
        }
        var scheme = "dark-medium", shape: KeyboardShape?, inputSourceID: String?
        for argument in arguments.dropFirst(2) {
            if let s = KeyboardShape(rawValue: argument) {
                shape = s
            } else if !argument.contains("/"), argument.contains(".") {
                // An input source ID; a theme file's path has a slash.
                inputSourceID = argument
            } else {
                scheme = argument
            }
        }
        let colors = BarPanelRender.theme(scheme)
        NSApplication.shared.setActivationPolicy(.prohibited)

        let model = AppModel.shared
        model.showSample(keys: sample(), colors: colors,
                         legends: KeyboardReader.legends(inputSourceID: inputSourceID),
                         detectedShape: shape ?? KeyboardReader.detectedShape())
        let view: AnyView
        if arguments[0] == "keyboard" {
            // The tab as the window holds it, without the header.
            view = AnyView(
                KeyboardView(model: model)
                    .frame(width: WindowView.width, alignment: .top)
                    .font(GroveFont.mono(GroveType.label))
                    .foregroundStyle(Color(colors.fg))
                    .background(Color(colors.bg0))
                    .environment(\.theme, colors))
        } else {
            // The card alone, on bg0 (the scrim needs something behind it).
            view = AnyView(
                CheatSheetView(model: model)
                    .padding(BarPanelRender.margin)
                    .background(Color(colors.bg0)))
        }
        BarPanelRender.write(view, dark: colors.isDark, to: arguments[1])
        exit(0)
    }

    /// The tests' keys.toml, beside these sources, with launchers on the
    /// keys whose legends differ most between layouts.
    private static func sample() -> KeysFile {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Tests/GroveKeysCoreTests/Fixtures/keys.toml").standardizedFileURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("\(url.path): can't be read") }
        var keys: KeysFile
        do { keys = try KeysFile(text: text) } catch { fail("\(url.lastPathComponent) line \(error.line): \(error.message)") }
        for (key, app) in [("t", "com.apple.Terminal"), ("s", "com.apple.Safari"), ("1", "com.apple.Notes"),
                           ("semicolon", "com.apple.finder"), ("quote", "com.apple.mail"),
                           ("backtick", "com.apple.TextEdit"), ("enter", "com.apple.Music")] {
            keys.setLaunch(key: key, bundleID: app)
        }
        return keys
    }
}
