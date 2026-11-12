import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// Battery: a placeholder in the frame until its stage builds it (spec
// 2026-11-12-bar-panels-design §6). Whoever builds it replaces this file's
// model and body and nothing else: the panel is registered already
// (`BarPanels.all`), opens from its pill and closes like the others.

/// The Battery panel's state. `start()` at each opening, `stop()` at each
/// closing; `.sample` is fixed data for `--render-panel`.
@MainActor
final class BatteryModel: ObservableObject, BarPanelModel {
    init(_ data: BarPanelData) {}
    func start() {}
    func stop() {}
}

struct BatteryPanel: View {
    static let width: CGFloat = 300
    static let registration = BarPanelRegistration("battery", pill: "pill.battery", width: width,
                                                   model: BatteryModel.init) { BatteryPanel(model: $0) }

    @ObservedObject var model: BatteryModel
    @Environment(\.theme) private var theme

    var body: some View {
        BarPanel(width: Self.width) {
            PanelHeader(.battery, accent: theme.yellow, title: "Battery")
            Text("Not built yet.").foregroundStyle(theme.quiet)
        }
    }
}
