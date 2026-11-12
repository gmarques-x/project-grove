import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// CPU & memory: a placeholder in the frame until its stage builds it (spec
// 2026-11-12-bar-panels-design §6). Whoever builds it replaces this file's
// model and body and nothing else: the panel is registered already
// (`BarPanels.all`), opens from its pill and closes like the others.

/// The CPU & memory panel's state. `start()` at each opening, `stop()` at each
/// closing; `.sample` is fixed data for `--render-panel`.
@MainActor
final class SystemModel: ObservableObject, BarPanelModel {
    init(_ data: BarPanelData) {}
    func start() {}
    func stop() {}
}

struct SystemPanel: View {
    static let width: CGFloat = 320
    static let registration = BarPanelRegistration("system", pill: "pill.sys", width: width,
                                                   model: SystemModel.init) { SystemPanel(model: $0) }

    @ObservedObject var model: SystemModel
    @Environment(\.theme) private var theme

    var body: some View {
        BarPanel(width: Self.width) {
            PanelHeader(.cpu, accent: theme.aqua, title: "CPU & memory")
            Text("Not built yet.").foregroundStyle(theme.quiet)
        }
    }
}
