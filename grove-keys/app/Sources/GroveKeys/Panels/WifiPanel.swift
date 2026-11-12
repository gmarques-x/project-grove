import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// Wi-Fi: a placeholder in the frame until its stage builds it (spec
// 2026-11-12-bar-panels-design §6). Whoever builds it replaces this file's
// model and body and nothing else: the panel is registered already
// (`BarPanels.all`), opens from its pill and closes like the others.

/// The Wi-Fi panel's state. `start()` at each opening, `stop()` at each
/// closing; `.sample` is fixed data for `--render-panel`.
@MainActor
final class WifiModel: ObservableObject, BarPanelModel {
    init(_ data: BarPanelData) {}
    func start() {}
    func stop() {}
}

struct WifiPanel: View {
    static let width: CGFloat = 320
    static let registration = BarPanelRegistration("wifi", pill: "pill.wifi", width: width,
                                                   model: WifiModel.init) { WifiPanel(model: $0) }

    @ObservedObject var model: WifiModel
    @Environment(\.theme) private var theme

    var body: some View {
        BarPanel(width: Self.width) {
            PanelHeader(.wifi, accent: theme.blue, title: "Wi-Fi")
            Text("Not built yet.").foregroundStyle(theme.quiet)
        }
    }
}
