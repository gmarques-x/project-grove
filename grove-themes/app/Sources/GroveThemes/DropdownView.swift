import AppKit
import GroveThemesCore
import GroveUI
import SwiftUI

/// The menu bar dropdown, worn in the current scheme.
struct DropdownView: View {
    @Environment(ThemesModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var focus = State(initialValue: KeyboardFocus(layout: .dropdown))

    var body: some View {
        let theme = model.currentColors
        VStack(alignment: .leading, spacing: GroveSpace.s12) {
            header(theme)
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                row("DARK", model.schemes(dark: true), theme)
                row("LIGHT", model.schemes(dark: false), theme)
            }
            if let list = model.list {
                VStack(alignment: .leading, spacing: 6) {
                    ChoiceRowLabel(title: "TERMINAL LOGO")
                    HStack(spacing: GroveSpace.s8) {
                        ForEach(list.logos, id: \.self) { logo in
                            ChoicePill(name: logo, isCurrent: logo == list.logo,
                                       isBusy: model.busyLogo == logo,
                                       isFocused: focus.wrappedValue.focused == .logo(logo)) {
                                run(.logo(logo))
                            }
                            .disabled(model.switchingDisabled)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ChoiceRowLabel(title: "WALLPAPER")
                    HStack(spacing: GroveSpace.s8) {
                        ForEach(list.wallpapers, id: \.self) { wallpaper in
                            ChoicePill(name: wallpaper, isCurrent: wallpaper == list.wallpaper,
                                       isBusy: model.busyWallpaper == wallpaper,
                                       isFocused: focus.wrappedValue.focused == .wallpaper(wallpaper)) {
                                run(.wallpaper(wallpaper))
                            }
                            .disabled(model.switchingDisabled)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: GroveSpace.s2) {
                MenuRow(title: "Open Grove Themes…", isFocused: focus.wrappedValue.focused == .openWindow) {
                    run(.openWindow)
                }
                MenuRow(title: "Quit", isFocused: focus.wrappedValue.focused == .quit) { run(.quit) }
            }
            .padding(.top, GroveSpace.s8)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.softLine(dark: 0.18)).frame(height: 1)
            }
        }
        .padding(14)
        .frame(width: 320)
        .keyboardNavigation(focus.projectedValue, list: model.list,
                            schemesDisabled: model.switchingDisabled, activate: run)
        .font(GroveFont.mono(GroveType.heading))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { Task { await model.refreshRetryingWhileNotInstalled() } }
    }

    /// A click or Return/Space on a tile or a menu row.
    private func run(_ item: FocusGrid.Item) {
        switch item {
        case .scheme(let scheme):
            Task { await model.switchTo(scheme) }
        case .logo(let logo):
            Task { await model.pickLogo(logo) }
        case .wallpaper(let wallpaper):
            Task { await model.pickWallpaper(wallpaper) }
        case .openWindow:
            openWindow(id: "gallery")
            NSApp.activate()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func header(_ theme: ThemeColors) -> some View {
        HStack(spacing: 10) {
            PineShape()
                .fill(Color(theme.green))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: GroveSpace.s2) {
                Text("Grove Themes").font(GroveFont.mono(GroveType.title, .bold))
                if let list = model.list {
                    Text(StatusText.displayName(list.current)).modifier(SchemeNameStyle())
                }
            }
        }
    }

    private func row(_ label: String, _ schemes: [String], _ theme: ThemeColors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(GroveFont.mono(GroveType.finePrint))
                .tracking(0.8)
                .foregroundStyle(theme.quiet)
            HStack(spacing: GroveSpace.s8) {
                ForEach(schemes, id: \.self) { scheme in
                    if let colors = model.colors(for: scheme) {
                        SchemeTile(scheme: scheme, colors: colors,
                                   isCurrent: scheme == model.list?.current,
                                   isBusy: model.busyScheme == scheme,
                                   isFocused: focus.wrappedValue.focused == .scheme(scheme)) {
                            run(.scheme(scheme))
                        }
                        .disabled(model.switchingDisabled)
                    }
                }
            }
        }
    }
}

/// "Open Grove Themes…" and "Quit": menu-like rows that light up in bg2 on hover.
private struct MenuRow: View {
    let title: String
    /// The keyboard focus box is on this row.
    let isFocused: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    /// `State` used directly: see GroveThemesApp on why not `@State`.
    private var hovering = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, GroveSpace.s4)
                .background(hovering.wrappedValue ? Color(theme.bg2) : .clear, in: RoundedRectangle(cornerRadius: GroveRadius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: GroveRadius.control, outset: 0)
        .onHover { hovering.wrappedValue = $0 }
    }
}
