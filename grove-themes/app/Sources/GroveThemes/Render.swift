import AppKit
import GroveThemesCore
import GroveUI
import SwiftUI

/// `GroveThemes --render <gallery|dropdown> <out.png> [scheme]`: draws the
/// gallery window or the menu-bar dropdown on fixed sample data
/// (`RenderSamples`) to a PNG at 2x and exits, for the READMEs' screenshots
/// and for checking a change in a dark and a light scheme without the live
/// app. No window or menu-bar item is ever shown, the app never starts
/// (activation policy `.prohibited`), `grove-themes` never runs and nothing
/// is set: `SampleRunner` throws on anything but `list` and `log`.
///
/// - `scheme`: a scheme's name (`dark-medium`, the default; `light-medium`,
///   …), or the path of a theme file (`grove-dotfiles/theme/everforest-light-medium`).
///   It is the current scheme in the sample, so the whole picture wears it.
@MainActor
enum Render {
    static let states = ["gallery", "dropdown"]
    static let usage = "usage: GroveThemes --render <gallery|dropdown> <out.png> [scheme]\nstates: "
        + states.joined(separator: ", ")
    /// The dropdown's width (`DropdownView`'s frame); its height is what it needs.
    static let dropdownWidth: CGFloat = 320

    /// Renders and exits when `arguments` holds `--render`; otherwise returns.
    static func runIfAsked(_ arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "--render") else { return }
        run(Array(arguments[(flag + 1)...]))
    }

    static func run(_ arguments: [String]) -> Never {
        guard arguments.count == 2 || arguments.count == 3, states.contains(arguments[0]) else { fail(usage) }
        let state = arguments[0], out = arguments[1]
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = sampleModel(scheme: arguments.count == 3 ? arguments[2] : "dark-medium")
        let colors = model.currentColors

        let view: AnyView, radius: CGFloat
        let size: CGSize
        switch state {
        case "gallery":
            size = CGSize(width: GalleryView.width, height: GalleryView.height)
            radius = GroveRadius.window
            // `runsUnderTitleBar` pulls the gallery up by the title bar's
            // height (28 pt until it measures a window; this one has no title
            // bar to measure), and the window puts it that far down, in its
            // safe area. The borderless window has none, so the render does.
            view = AnyView(GalleryView()
                .padding(.top, 28)
                .frame(width: size.width, height: size.height, alignment: .top)
                // The window's own bg0 under the header, as the window has it.
                .background(Color(colors.bg0))
                .overlay(alignment: .topLeading) { WindowButtonsStandIn() })
        default:
            let dropdown = DropdownView().environment(model).environment(\.theme, colors)
            let fitting = NSHostingView(rootView: dropdown).fittingSize
            size = CGSize(width: dropdownWidth, height: ceil(fitting.height))
            radius = GroveRadius.card
            view = AnyView(DropdownView())
        }
        let framed = view
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(colors.line, lineWidth: 1))
            .environment(model)
            .environment(\.theme, colors)
        let hosting = offscreen(framed, size: size, colors: colors)
        if let error = model.error { fail("the sample list didn't load: \(error.message)") }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { fail("cannot make the image") }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("cannot encode the image") }
        do {
            try png.write(to: URL(fileURLWithPath: out))
        } catch {
            fail("cannot write \(out): \(error.localizedDescription)")
        }
        print("\(out) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        exit(0)
    }

    /// A model on the sample list with `scheme` current, its first `list` done.
    /// The logo and wallpaper images come from the checkout: the cards look
    /// them up under `$XDG_CONFIG_HOME` (`ChoiceCard.swift`), which is set to
    /// the checkout's `grove-dotfiles/config` for this process only.
    private static func sampleModel(scheme: String) -> ThemesModel {
        guard let checkout = RenderSamples.checkout() else {
            fail("the Project Grove checkout wasn't found above the executable or the working directory")
        }
        let themes = checkout.appendingPathComponent("grove-dotfiles/theme")
        let list: SchemeList?
        if scheme.contains("/") {
            let file = URL(fileURLWithPath: scheme)
            let name = file.lastPathComponent.replacingOccurrences(of: "everforest-", with: "")
            guard RenderSamples.palette(name, file: file) != nil else { fail("\(scheme): not a theme file") }
            list = RenderSamples.list(themes: themes, current: name, extra: (name, file))
        } else {
            list = RenderSamples.list(themes: themes, current: scheme)
            if list == nil, RenderSamples.list(themes: themes, current: "dark-medium") != nil {
                fail("no scheme named \(scheme); there are: dark-hard, dark-medium, dark-soft, light-hard, light-medium, light-soft")
            }
        }
        guard let list else { fail("\(themes.path): the theme files can't be read") }
        setenv("XDG_CONFIG_HOME", checkout.appendingPathComponent("grove-dotfiles/config").path, 1)

        let model = ThemesModel(client: GroveThemesClient(runner: SampleRunner(list: list)))
        var loaded = false
        Task { @MainActor in
            await model.refresh()
            loaded = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !loaded, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard loaded, model.list != nil else {
            fail("the sample list didn't load: \(model.error?.message ?? "no answer")")
        }
        return model
    }

    /// `view` laid out and drawn in a borderless window far off every screen,
    /// never ordered in.
    private static func offscreen(_ view: some View, size: CGSize, colors: ThemeColors) -> NSView {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        // SwiftUI settles its layout, and the cards their images, over a few turns of the run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        windows.append(window)
        return hosting
    }

    /// Kept so the window outlives the call that made it.
    private static var windows: [NSWindow] = []

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

/// The window's own buttons, which the system draws on a real window: a
/// measured drawing (14 pt, from 9, as `WindowHeaderMetrics` measured), so a
/// render of the gallery looks like the window.
private struct WindowButtonsStandIn: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array([theme.red, theme.yellow, theme.green].enumerated()), id: \.offset) { button in
                Circle().fill(Color(button.element)).frame(width: 14, height: 14)
            }
        }
        .padding(.leading, 9).padding(.top, 9)
    }
}
