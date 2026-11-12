import GroveThemesCore
import GroveUI
import SwiftUI

/// The "Grove Themes" window: the six desktop cards, then the terminal logo
/// row (the switch log stays in the CLI, `grove-themes log`; the dropdown
/// keeps the status line).
struct GalleryView: View {
    @Environment(ThemesModel.self) private var model
    /// The window fits the cards: 760 wide, as tall as they need (≈ 762 pt:
    /// 44 above, two rows of ≈ 163, 12 between, the logo and wallpaper rows
    /// ≈ 166 each with their labels, 16 below), never shorter, so it keeps its
    /// size while the first `list` loads or the CLI is missing. (776 with
    /// 18 pt margins and 10 pt inside the cards: every change since is taken
    /// off as the content, laid out off screen, measured it: 758, now 744.)
    static let width: CGFloat = 760
    static let height: CGFloat = 762
    static let buttonsClearance: CGFloat = 28
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var focus = State(initialValue: KeyboardFocus(layout: .gallery))

    var body: some View {
        let theme = model.currentColors
        let columns = Array(repeating: GridItem(.flexible(), spacing: GroveSpace.s12), count: 3)
        VStack(alignment: .leading, spacing: GroveSpace.s16) {
            if let error = model.error {
                theme.marked(error.message, theme.red)
                    .font(GroveFont.mono(GroveType.label))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            if let list = model.list {
                VStack(alignment: .leading, spacing: GroveSpace.s8) {
                    ChoiceRowLabel(title: "TERMINAL LOGO")
                    HStack(spacing: GroveSpace.s12) {
                        ForEach(list.logos, id: \.self) { logo in
                            ChoiceCard(name: logo, image: logoImage(logo, scheme: list.current),
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
                            ChoiceCard(name: wallpaper, image: wallpaperImage(wallpaper, scheme: list.current),
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
        // No title bar (GroveThemesApp): the content runs to the window's top
        // edge, and the extra 28 pt keep the cards clear of the window buttons.
        .padding(GroveSpace.s16)
        .padding(.top, Self.buttonsClearance)
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
        .ignoresSafeArea(.container, edges: .top)
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .background(WindowAccessor { $0.isMovableByWindowBackground = true })
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .task { await model.refreshRetryingWhileNotInstalled() }
    }
}
