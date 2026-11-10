import GroveThemesCore
import SwiftUI

/// The "Grove Themes" window: six desktop cards and the switch log.
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
                LogView(entries: Array(model.log.prefix(5)))
            }
            .padding(18)
        }
        .frame(minWidth: 640, minHeight: 460)
        .font(GroveFont.mono(12))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .task { await model.refresh() }
    }
}
