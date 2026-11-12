import GroveThemesCore
import GroveUI
import SwiftUI

/// The "Grove Themes" window: the six desktop cards, then the terminal logo
/// and wallpaper rows. A CLI error is said in one line at the top, here and
/// in the dropdown; the switch log stays in the CLI (`grove-themes log`).
struct GalleryView: View {
    @Environment(ThemesModel.self) private var model
    /// The window fits its content: 760 wide and as tall as the header, the
    /// three labelled rows and the margins need, which is 763 pt (the
    /// header's 32, 8, the scheme cards, the logo and the wallpaper rows 16
    /// apart, 24 below: measured by laying the view out off screen, so the
    /// space under the last row is the side margin, 24). Never shorter, so
    /// the window keeps its size while the first `list` loads or the CLI is
    /// missing.
    static let width: CGFloat = 760
    static let height: CGFloat = 763
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var focus = State(initialValue: KeyboardFocus(layout: .gallery))

    var body: some View {
        let theme = model.currentColors
        let columns = Array(repeating: GridItem(.flexible(), spacing: GroveSpace.s12), count: 3)
        VStack(alignment: .leading, spacing: 0) {
            GroveWindowHeader("Grove Themes") { status(theme) }
            VStack(alignment: .leading, spacing: GroveSpace.s16) {
                if let error = model.error {
                    theme.marked(error.message, theme.red, size: GroveType.label)
                        .font(GroveFont.mono(GroveType.label))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: GroveSpace.s8) {
                    // Labelled as the two rows below it; not over an empty grid.
                    if model.list != nil { ChoiceRowLabel(title: "SCHEME") }
                    LazyVGrid(columns: columns, spacing: GroveSpace.s12) {
                        ForEach(model.schemes(dark: true) + model.schemes(dark: false), id: \.self) { scheme in
                            if let colors = model.colors(for: scheme) {
                                SchemeCard(scheme: scheme, colors: colors,
                                           isCurrent: scheme == model.list?.current,
                                           isBusy: model.busyScheme == scheme,
                                           isFocused: focus.wrappedValue.focused == .scheme(scheme)) {
                                    Task { await model.switchTo(scheme) }
                                }
                                .disabled(model.switchingDisabled)
                            }
                        }
                    }
                }
                if let list = model.list {
                    VStack(alignment: .leading, spacing: GroveSpace.s8) {
                        ChoiceRowLabel(title: "TERMINAL LOGO")
                        HStack(spacing: GroveSpace.s12) {
                            ForEach(list.logos, id: \.self) { logo in
                                ChoiceCard(kind: "Terminal logo", name: logo, image: logoImage(logo, scheme: list.current),
                                           isCurrent: logo == list.logo,
                                           isBusy: model.busyLogo == logo,
                                           isFocused: focus.wrappedValue.focused == .logo(logo)) {
                                    Task { await model.pickLogo(logo) }
                                }
                                .disabled(model.switchingDisabled)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: GroveSpace.s8) {
                        ChoiceRowLabel(title: "WALLPAPER")
                        HStack(spacing: GroveSpace.s12) {
                            ForEach(list.wallpapers, id: \.self) { wallpaper in
                                ChoiceCard(kind: "Wallpaper", name: wallpaper, image: wallpaperImage(wallpaper, scheme: list.current),
                                           isCurrent: wallpaper == list.wallpaper,
                                           isBusy: model.busyWallpaper == wallpaper,
                                           isFocused: focus.wrappedValue.focused == .wallpaper(wallpaper),
                                           margin: 0) {
                                    Task { await model.pickWallpaper(wallpaper) }
                                }
                                .disabled(model.switchingDisabled)
                            }
                        }
                    }
                }
            }
            // The margins every Grove window has.
            .padding(.horizontal, GroveWindow.margin)
            .padding(.top, GroveWindow.contentGap)
            .padding(.bottom, GroveWindow.margin)
        }
        // No title bar (GroveThemesApp): the header runs to the window's top
        // edge, under the window buttons.
        .frame(width: Self.width, alignment: .top)
        .frame(minHeight: Self.height, alignment: .top)
        .keyboardNavigation(focus.projectedValue, list: model.list,
                            schemesDisabled: model.switchingDisabled) { item in
            switch item {
            case .scheme(let scheme): Task { await model.switchTo(scheme) }
            case .logo(let logo): Task { await model.pickLogo(logo) }
            case .wallpaper(let wallpaper): Task { await model.pickWallpaper(wallpaper) }
            case .openWindow, .quit: break
            }
        }
        .runsUnderTitleBar()
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .background(WindowAccessor { $0.isMovableByWindowBackground = true })
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .task { await model.refreshRetryingWhileNotInstalled() }
    }

    /// The header's right: the current scheme's name, quiet, with the cards'
    /// spinner before it while a switch runs.
    private func status(_ theme: ThemeColors) -> some View {
        HStack(spacing: GroveSpace.s8) {
            if model.isBusy { ProgressView().controlSize(.small) }
            if let list = model.list { Text(StatusText.displayName(list.current)) }
        }
        .font(GroveFont.mono(GroveType.body))
        .foregroundStyle(theme.quiet)
    }
}
