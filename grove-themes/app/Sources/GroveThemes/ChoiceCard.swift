import AppKit
import GroveThemesCore
import SwiftUI

/// "grove" → "Project Grove", "avatar" → "Avatar".
func choiceName(_ name: String) -> String {
    name == "grove" ? "Project Grove" : StatusText.displayName(name)
}

/// The config folder `grove-themes` renders into: `$XDG_CONFIG_HOME`, default
/// `~/.config` (a link into the grove-dotfiles checkout).
private func configFolder() -> URL {
    let env = ProcessInfo.processInfo.environment
    return env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
}

/// Images read once per path: the cards redraw often, the files rarely change.
@MainActor private var imageCache: [String: NSImage] = [:]

@MainActor private func cachedImage(_ url: URL) -> NSImage? {
    if let image = imageCache[url.path] { return image }
    guard let image = NSImage(contentsOf: url) else { return nil }
    imageCache[url.path] = image
    return image
}

/// The fastfetch image a logo shows in `scheme`, as `grove-themes` renders it:
/// `<logo>.png` on dark schemes, `<logo>-light-<contrast>.png` on light ones.
@MainActor func logoImage(_ logo: String, scheme: String) -> NSImage? {
    let parts = scheme.split(separator: "-")
    let file = parts.first == "light" && parts.count == 2 ? "\(logo)-light-\(parts[1]).png" : "\(logo).png"
    return cachedImage(configFolder().appendingPathComponent("fastfetch").appendingPathComponent(file))
}

/// A wallpaper set's picture for `scheme`: `grove-wallpapers/wallpaper-<set>-<scheme>.png`
/// beside the grove-dotfiles checkout the config folder links into.
@MainActor func wallpaperImage(_ wallpaper: String, scheme: String) -> NSImage? {
    let dotfiles = configFolder().resolvingSymlinksInPath().deletingLastPathComponent()
    let set = wallpaper == "grove" ? "project-grove" : wallpaper
    return cachedImage(dotfiles.deletingLastPathComponent()
        .appendingPathComponent("grove-wallpapers")
        .appendingPathComponent("wallpaper-\(set)-\(scheme).png"))
}

/// One choice in the gallery (a terminal logo or a wallpaper set): its image
/// on a small panel in the current scheme, then its name; green border when
/// chosen.
struct ChoiceCard: View {
    let name: String
    let image: NSImage?
    let isCurrent: Bool
    let isBusy: Bool
    var isFocused = false
    /// Wallpapers fill their panel; logos sit inside it with a margin.
    var fills = false
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
                        if let image {
                            Image(nsImage: image).resizable().interpolation(.high)
                                .aspectRatio(contentMode: fills ? .fill : .fit)
                                .padding(fills ? 0 : 10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack(alignment: .firstTextBaseline) {
                    Text(choiceName(name)).modifier(SchemeNameStyle())
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

/// A choice in the dropdown: its name, a dot when chosen.
struct ChoicePill: View {
    let name: String
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
                Text(choiceName(name)).font(GroveFont.mono(12))
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

/// A labelled row of choices ("TERMINAL LOGO", "WALLPAPER").
struct ChoiceRowLabel: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(GroveFont.mono(10))
            .tracking(0.8)
            .foregroundStyle(Color(theme.grey1))
    }
}
