import GroveThemesCore
import SwiftUI

/// The "Grove Themes" window: the six desktop cards (the switch log stays in
/// the CLI, `grove-themes log`; the dropdown keeps the status line).
struct GalleryView: View {
    @Environment(ThemesModel.self) private var model

    var body: some View {
        let theme = model.currentColors
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        ScrollView {
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
                                       isBusy: model.busyScheme == scheme) {
                                Task { await model.switchTo(scheme) }
                            }
                            .disabled(model.switchingDisabled)
                        }
                    }
                }
            }
            .padding(18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 640, minHeight: 320)
        .font(GroveFont.mono(12))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .task { await model.refreshRetryingWhileNotInstalled() }
    }
}
