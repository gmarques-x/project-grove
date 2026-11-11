import AppKit
import GroveThemesCore
import SwiftUI

/// The Grove Keys window (spec §7, mockup §1): no title bar, the header with
/// the name, the two tabs and the Hyper status, then the red line, the
/// permission banner and the tab.
struct WindowView: View {
    @ObservedObject var model: AppModel
    static let width: CGFloat = 900
    /// Clears the window buttons, which sit over the header.
    private static let buttonsClearance: CGFloat = 78

    enum Tab: String, CaseIterable {
        case keyboard = "Keyboard", bindings = "Bindings"
    }

    /// `State` used directly: the Command Line Tools ship no SwiftUI macros.
    private var tab = State(initialValue: Tab.keyboard)

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        let theme = model.colors
        VStack(alignment: .leading, spacing: 0) {
            header(theme)
            VStack(alignment: .leading, spacing: 10) {
                if let line = model.redLine {
                    Text(line)
                        .foregroundStyle(Color(theme.red))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(theme.red).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
                if !model.permissions.granted {
                    PermissionBanner(permissions: model.permissions)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, model.redLine == nil && model.permissions.granted ? 0 : 10)

            switch tab.wrappedValue {
            case .keyboard:
                KeyboardView(model: model)
            case .bindings:
                Text("The Bindings tab is still being built.")
                    .foregroundStyle(Color(theme.grey1))
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .frame(width: Self.width, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .font(GroveFont.mono(12))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .background(WindowAccessor { $0.isMovableByWindowBackground = true })
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private func header(_ theme: ThemeColors) -> some View {
        HStack(spacing: 0) {
            Text("Grove Keys").font(GroveFont.lockup(15))
            HStack(spacing: 4) {
                ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                    let on = tab.wrappedValue == t
                    Button { tab.wrappedValue = t } label: {
                        Text(t.rawValue)
                            .foregroundStyle(Color(on ? theme.fg : theme.grey1))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(on ? Color(theme.bg3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
            }
            .padding(3)
            .background(Color(theme.bg1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.leading, 22)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Color(statusDot(theme))).frame(width: 7, height: 7)
                Text(model.host.isEmpty ? status : "\(status) · \(model.host)")
            }
            .font(GroveFont.mono(11.5))
            .foregroundStyle(Color(theme.grey1))
        }
        .padding(.leading, Self.buttonsClearance)
        .padding(.trailing, 14)
        .frame(height: 44)
    }

    private var status: String {
        if model.paused { return "Hyper paused" }
        if !model.keys.hyper.enabled { return "Hyper off" }
        return model.mapping ? "Hyper on" : "Hyper not running"
    }

    private func statusDot(_ theme: ThemeColors) -> RGB {
        if model.mapping { return theme.green }
        return model.needsAttention ? theme.orange : theme.grey1
    }
}

/// Spec §10: a missing permission, with Open Settings.
private struct PermissionBanner: View {
    let permissions: PermissionStatus
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !permissions.accessibility {
                line("Grove Keys needs Accessibility", Permissions.accessibilitySettings)
            }
            if !permissions.inputMonitoring {
                line("Grove Keys needs Input Monitoring", Permissions.inputMonitoringSettings)
            }
            Text("Caps Lock stays Caps Lock until both are on.")
                .foregroundStyle(Color(theme.fg))
                .font(GroveFont.mono(11.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(theme.yellow).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private func line(_ text: String, _ url: URL) -> some View {
        HStack(spacing: 12) {
            Text(text).foregroundStyle(Color(theme.orange)).fontWeight(.semibold)
            Button { NSWorkspace.shared.open(url) } label: {
                Text("Open Settings")
                    .font(GroveFont.mono(11.5, .semibold))
                    .foregroundStyle(Color(theme.bg0))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color(theme.orange), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
