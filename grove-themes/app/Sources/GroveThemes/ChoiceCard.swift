import AppKit
import GroveThemesCore
import GroveUI
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

/// Thumbnails decoded once per path, at most 640 px on the longer side (a
/// card is ≈ 336 pt wide): the cards redraw often, the files rarely change,
/// and a full-size wallpaper would hold ~21 MB per entry.
@MainActor private var imageCache: [String: NSImage] = [:]

@MainActor private func cachedImage(_ url: URL) -> NSImage? {
    if let image = imageCache[url.path] { return image }
    guard let cg = Thumbnail.load(url, maxPixel: 640) else { return nil }
    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
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
/// (1 pt) and "● on" when chosen.
struct ChoiceCard: View {
    /// What is being chosen, for VoiceOver: "Terminal logo", "Wallpaper".
    let kind: String
    let name: String
    let image: NSImage?
    let isCurrent: Bool
    let isBusy: Bool
    var isFocused = false
    /// Logos sit inside the panel with a margin; wallpapers fill its height,
    /// shown whole.
    var margin: CGFloat = GroveSpace.s8
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GroveRadius.card)
        Button(action: action) {
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                RoundedRectangle(cornerRadius: GroveRadius.control)
                    .fill(Color(theme.bg1))
                    .frame(height: 96)
                    .overlay {
                        if let image {
                            Image(nsImage: image).resizable().interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .padding(margin)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: GroveRadius.control))
                    .lightOutline(cornerRadius: GroveRadius.control)
                HStack(alignment: .firstTextBaseline) {
                    Text(choiceName(name)).modifier(SchemeNameStyle())
                    Spacer(minLength: 4)
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if isCurrent {
                        OnMark()
                    }
                }
            }
            .padding(GroveSpace.s8)
            .overlay {
                // Current: a 1 pt green line and "● on". The 2 pt green box is the focus only.
                shape.strokeBorder(isCurrent ? Color(theme.green) : theme.line, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: GroveRadius.card, outset: 5)
        .accessibilityLabel(kind + ": " + choiceName(name))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A choice in the dropdown: its name, a dot when chosen.
struct ChoicePill: View {
    /// What is being chosen, for VoiceOver: "Terminal logo", "Wallpaper".
    let kind: String
    let name: String
    let isCurrent: Bool
    let isBusy: Bool
    var isFocused = false
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GroveRadius.control)
        Button(action: action) {
            HStack(spacing: GroveSpace.s8) {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(isCurrent ? Color(theme.green) : theme.line).frame(width: 7, height: 7)
                }
                Text(choiceName(name)).font(GroveFont.mono(GroveType.label))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GroveSpace.s4)
            .background(Color(theme.bg1), in: shape)
            .overlay { shape.strokeBorder(isCurrent ? Color(theme.green) : theme.line, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .focusBox(isFocused, cornerRadius: GroveRadius.control, outset: 3)
        .accessibilityLabel(kind + ": " + choiceName(name))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A labelled row of choices ("TERMINAL LOGO", "WALLPAPER").
struct ChoiceRowLabel: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(GroveFont.mono(GroveType.finePrint))
            .tracking(0.8)
            .foregroundStyle(theme.quiet)
            .accessibilityAddTraits(.isHeader)
    }
}
