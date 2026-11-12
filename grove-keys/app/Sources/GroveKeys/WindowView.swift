import AppKit
import GroveThemesCore
import GroveUI
import SwiftUI

/// The Grove Keys window (spec §7, mockup §1): no title bar, the header with
/// the name, the two tabs and the Hyper status, then the red line, the
/// permission banner and the tab.
struct WindowView: View {
    @ObservedObject var model: AppModel
    /// The keyboard's 856 pt and a 24 pt margin each side.
    static let width: CGFloat = 904
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
            VStack(alignment: .leading, spacing: GroveSpace.s12) {
                if let line = model.redLine {
                    // In light the sentence is fg and the outline carries the red.
                    Text(line)
                        .foregroundStyle(theme.ink(theme.red))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, GroveSpace.s12).padding(.vertical, GroveSpace.s8)
                        .background(theme.tintFill(theme.red, .banner), in: RoundedRectangle(cornerRadius: GroveRadius.card))
                        .lightOutline(cornerRadius: GroveRadius.card, accent: theme.red)
                }
                if !model.permissions.granted {
                    PermissionBanner(permissions: model.permissions)
                }
            }
            .padding(.horizontal, GroveSpace.s24)
            .padding(.bottom, model.redLine == nil && model.permissions.granted ? 0 : GroveSpace.s12)

            switch tab.wrappedValue {
            case .keyboard:
                KeyboardView(model: model)
            case .bindings:
                BindingsView(model: model)
            }
        }
        .frame(width: Self.width, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .font(GroveFont.mono(GroveType.label))
        .foregroundStyle(Color(theme.fg))
        .background(Color(theme.bg0).ignoresSafeArea())
        .background(WindowAccessor { $0.isMovableByWindowBackground = true })
        // No focus ring on the first tab button when the window opens (macOS
        // puts one there with "Keyboard navigation" on): only once Tab or an
        // arrow is pressed, and gone again on a click.
        .keyboardFocusRing()
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private func header(_ theme: ThemeColors) -> some View {
        HStack(spacing: 0) {
            Text("Grove Keys").font(GroveFont.lockup(15))
            // ⌘1, ⌘2.
            GroveSegmented("Tabs", segments: Tab.allCases.enumerated().map { i, t in
                GroveSegment(t, t.rawValue, shortcut: KeyEquivalent(Character(String(i + 1))))
            }, selection: tab.wrappedValue, style: .pill(.panel), role: .tabs) { tab.wrappedValue = $0 }
            .padding(.leading, GroveSpace.s24)
            Spacer()
            HStack(spacing: GroveSpace.s8) {
                Circle().fill(Color(statusDot(theme))).frame(width: 7, height: 7)
                Text(status)
            }
            .font(GroveFont.mono(GroveType.body))
            .foregroundStyle(theme.quiet)
        }
        .padding(.leading, Self.buttonsClearance)
        .padding(.trailing, GroveSpace.s16)
        .frame(height: 44)
    }

    private var status: String {
        if model.paused { return "Hyper paused" }
        if !model.keys.hyper.enabled { return "Hyper off" }
        return model.mapping ? "Hyper on" : "Hyper not running"
    }

    private func statusDot(_ theme: ThemeColors) -> RGB {
        if model.mapping { return theme.green }
        return model.needsAttention ? theme.orange : theme.dim
    }
}

/// Spec §10: a missing permission, with Open Settings. A warning: orange
/// throughout (fill, outline, words, button).
private struct PermissionBanner: View {
    let permissions: PermissionStatus
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            if !permissions.accessibility {
                line("Grove Keys needs Accessibility", Permissions.accessibilitySettings)
            }
            if !permissions.inputMonitoring {
                line("Grove Keys needs Input Monitoring", Permissions.inputMonitoringSettings)
            }
            Text("Caps Lock stays Caps Lock until both are on.")
                .foregroundStyle(Color(theme.fg))
                .font(GroveFont.mono(GroveType.body))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GroveSpace.s12).padding(.vertical, GroveSpace.s8)
        .background(theme.tintFill(theme.orange, .banner), in: RoundedRectangle(cornerRadius: GroveRadius.card))
        .lightOutline(cornerRadius: GroveRadius.card, accent: theme.orange)
    }

    private func line(_ text: String, _ url: URL) -> some View {
        HStack(spacing: GroveSpace.s12) {
            Text(text).foregroundStyle(theme.ink(theme.orange)).fontWeight(.semibold)
            Button { NSWorkspace.shared.open(url) } label: {
                Text("Open Settings")
                    .font(GroveFont.mono(GroveType.label, .semibold))
                    .foregroundStyle(Color(theme.onAccent))
                    .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s2)
                    .background(Color(theme.orange), in: RoundedRectangle(cornerRadius: GroveRadius.control))
            }
            .buttonStyle(.plain)
        }
    }
}
