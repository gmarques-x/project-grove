import AppKit
import GroveThemesCore
import SwiftUI

/// "grove" → "Project Grove", "avatar" → "Avatar".
func logoName(_ logo: String) -> String {
    logo == "grove" ? "Project Grove" : StatusText.displayName(logo)
}

/// The fastfetch image a logo shows in `scheme`, as `grove-themes` renders it:
/// `<logo>.png` on dark schemes, `<logo>-light-<contrast>.png` on light ones,
/// in `$XDG_CONFIG_HOME/fastfetch` (default `~/.config/fastfetch`).
func logoImage(_ logo: String, scheme: String) -> NSImage? {
    let env = ProcessInfo.processInfo.environment
    let config = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    let parts = scheme.split(separator: "-")
    let file = parts.first == "light" && parts.count == 2 ? "\(logo)-light-\(parts[1]).png" : "\(logo).png"
    return NSImage(contentsOf: config.appendingPathComponent("fastfetch").appendingPathComponent(file))
}

/// One terminal logo in the gallery: the image on a small terminal in the
/// current scheme, then its name; green border when chosen.
struct LogoCard: View {
    let logo: String
    let scheme: String
    let isCurrent: Bool
    let isBusy: Bool
    var isFocused = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(theme.bg1))
                    .frame(height: 96)
                    .overlay {
                        if let image = logoImage(logo, scheme: scheme) {
                            Image(nsImage: image).resizable().interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .padding(10)
                        }
                    }
                HStack(alignment: .firstTextBaseline) {
                    Text(logoName(logo)).modifier(SchemeNameStyle())
                    Spacer(minLength: 4)
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if isCurrent {
                        Text("● on").font(GroveFont.mono(12)).foregroundStyle(Color(theme.green))
                    }
                }
            }
            .padding(10)
            .overlay {
                shape.strokeBorder(isCurrent ? Color(theme.green) : Color(theme.bg3),
                                   lineWidth: isCurrent ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: 10, outset: 5)
    }
}

/// A logo in the dropdown: its name, a dot when chosen.
struct LogoPill: View {
    let logo: String
    let isCurrent: Bool
    let isBusy: Bool
    var isFocused = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(isCurrent ? Color(theme.green) : Color(theme.bg3)).frame(width: 7, height: 7)
                }
                Text(logoName(logo)).font(GroveFont.mono(12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(theme.bg1), in: shape)
            .overlay { shape.strokeBorder(isCurrent ? Color(theme.green) : Color(theme.bg3), lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: 6, outset: 3)
    }
}
