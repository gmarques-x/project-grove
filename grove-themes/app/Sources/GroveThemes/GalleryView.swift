import GroveThemesCore
import SwiftUI

/// The "Grove Themes" window: the six desktop cards, then the terminal logo
/// row (the switch log stays in the CLI, `grove-themes log`; the dropdown
/// keeps the status line).
struct GalleryView: View {
    @Environment(ThemesModel.self) private var model
    /// The window fits the cards: 760 wide, as tall as they need (≈ 590 pt:
    /// 46 above, two rows of ≈ 164, 12 between, the logo row ≈ 170 with its
    /// label, 18 below), never shorter, so it keeps its size while the first
    /// `list` loads or the CLI is missing.
    static let width: CGFloat = 760
    static let height: CGFloat = 590
    static let buttonsClearance: CGFloat = 28
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var focus = State(initialValue: KeyboardFocus(layout: .gallery))

    var body: some View {
        let theme = model.currentColors
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        VStack(alignment: .leading, spacing: 16) {
            if let error = model.error {
                Text(error.message)
                    .font(GroveFont.mono(12))
                    .foregroundStyle(Color(theme.red))
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("TERMINAL LOGO")
                        .font(GroveFont.mono(10))
                        .tracking(0.8)
                        .foregroundStyle(Color(theme.grey1))
                    HStack(spacing: 12) {
                        ForEach(list.logos, id: \.self) { logo in
                            LogoCard(logo: logo, scheme: list.current,
                                     isCurrent: logo == list.logo,
                                     isBusy: model.busyLogo == logo,
                                     isFocused: focus.wrappedValue.focused == .logo(logo)) {
                                Task { await model.pickLogo(logo) }
                            }
                            .disabled(model.switchingDisabled)
                        }
                    }
                }
            }
        }
        // No title bar (GroveThemesApp): the content runs to the window's top
        // edge, and the extra 28 pt keep the cards clear of the window buttons.
        .padding(18)
        .padding(.top, Self.buttonsClearance)
        .frame(width: Self.width, alignment: .top)
        .frame(minHeight: Self.height, alignment: .top)
        .keyboardNavigation(focus.projectedValue, current: model.list?.current ?? "",
                            schemesDisabled: model.switchingDisabled) { item in
            switch item {
            case .scheme(let scheme): Task { await model.switchTo(scheme) }
            case .logo(let logo): Task { await model.pickLogo(logo) }
            case .openWindow, .quit: break
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .font(GroveFont.mono(12))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .background(WindowAccessor { $0.isMovableByWindowBackground = true })
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .task { await model.refreshRetryingWhileNotInstalled() }
    }
}
