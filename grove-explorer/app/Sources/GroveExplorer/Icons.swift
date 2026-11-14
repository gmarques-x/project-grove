import AppKit
import CoreText
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI
import UniformTypeIdentifiers

/// The measures of an icon in the list and the sidebar.
enum IconMetrics {
    /// Icons are 16 pt (spec §10).
    static let cell = GroveSpace.s16
    /// A hidden item's icon is dimmed to this (spec §6); its name takes `hiddenInk`.
    static let hiddenOpacity: CGFloat = 0.5
    /// A hidden file's glyph is dimmed less: its strokes are thin, and at
    /// half strength the glyph is nearly gone in the light schemes.
    static let hiddenGlyphOpacity: CGFloat = 0.65
}

// MARK: Grove Icons: the font and the map

/// The Grove Icons font and map, copied into the app's resources by
/// `make-resources.sh` (the grove module does it for the installed app).
@MainActor
enum GroveIcons {
    /// The font's name once registered.
    static let fontName = "seti"
    private static var loaded = false
    /// Until the resources are read, and when they are missing: a map
    /// without glyphs (a theme with no definitions always parses), so
    /// folders are still Grove's and every file takes its macOS icon.
    private static var loadedMap = try! IconMap(themeJSON: Data(#"{"iconDefinitions":{}}"#.utf8))

    /// What to tell the developer when the resources aren't there; nil when they are.
    private(set) static var problem: String?

    /// The map; one without glyphs when the resources are missing.
    static var map: IconMap {
        load()
        return loadedMap
    }

    /// Registers the font for this process only and reads the map. Once.
    static func load() {
        guard !loaded else { return }
        loaded = true
        guard let folder = resourceFolder() else {
            problem = "Grove Icons are missing from the app's resources: run grove-explorer/app/make-resources.sh and build again"
            return
        }
        // Core Text takes the .woff as it is.
        let font = folder.appendingPathComponent("seti.woff") as CFURL
        let registered = CTFontManagerRegisterFontsForURL(font, .process, nil)
        guard registered, NSFont(name: fontName, size: IconMetrics.cell) != nil,
            let data = try? Data(contentsOf: folder.appendingPathComponent("grove-icon-theme.json")),
            let map = try? IconMap(themeJSON: data)
        else {
            problem = "Grove Icons in \(folder.path) can't be used: run grove-explorer/app/make-resources.sh and build again"
            return
        }
        loadedMap = map
    }

    /// In the installed app the two files are in Contents/Resources; in a
    /// `swift build` they are in the package's resource bundle.
    private static func resourceFolder() -> URL? {
        func holds(_ folder: URL?) -> URL? {
            folder.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("seti.woff").path) ? $0 : nil }
        }
        // The package's bundle is asked only when the app's own has nothing:
        // `Bundle.module` stops the program where there is no such bundle.
        return holds(Bundle.main.resourceURL) ?? holds(Bundle.module.resourceURL?.appendingPathComponent("Resources"))
    }
}

/// A file's Grove Icons glyph in its colour.
enum FileGlyph {
    /// The font's glyphs are drawn small in their em: 1.25× the cell fills it
    /// (the VS Code theme asks for 150% of a 13 px line for the same reason).
    static let scale: CGFloat = 1.25
    /// The glyphs sit on the baseline of an em with no descent, so a glyph
    /// centred by its line box hangs low: lifted by this part of the cell.
    static let lift: CGFloat = 0.06

    /// Draws `glyph` centred in `rect` (a flipped view's coordinates).
    @MainActor
    static func draw(_ glyph: Glyph, in rect: CGRect, opacity: CGFloat = 1) {
        guard let font = NSFont(name: GroveIcons.fontName, size: rect.height * scale),
            let color = RGB(hex: glyph.colorHex)
        else { return }
        let text = NSAttributedString(
            string: String(glyph.character),
            attributes: [.font: font, .foregroundColor: NSColor(color).withAlphaComponent(opacity)])
        let size = text.size()
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - rect.height * lift))
    }
}

// MARK: The Grove folder

/// The Grove folder's outline: a tab and a body on a 16-unit grid, with the
/// mark of a known folder cut out of the body. One path, filled once.
enum FolderPath {
    /// `rect` in coordinates that grow downwards (SwiftUI, a flipped view).
    static func path(mark: FolderMark, in rect: CGRect) -> CGPath {
        let unit = rect.width / 16
        var grid = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: unit, y: unit)
        let tab = CGPath(roundedRect: CGRect(x: 1, y: 2.5, width: 6.5, height: 5), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        let body = CGPath(roundedRect: CGRect(x: 1, y: 4.75, width: 14, height: 9), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        var folder = tab.union(body)
        if let cut = cutOut(mark) { folder = folder.subtracting(cut) }
        return folder.copy(using: &grid) ?? folder
    }

    /// Each mark is a few strokes one grid unit wide (2 px at 16 pt on a
    /// Retina screen), set on whole and half units so its edges land on
    /// pixels, inside the body (x 4…12, y 6.5…12.5). Each was accepted from a
    /// render at list size (spec §10).
    private static func cutOut(_ mark: FolderMark) -> CGPath? {
        let path = CGMutablePath()
        func stroke(_ points: [(CGFloat, CGFloat)], width: CGFloat = 1, cap: CGLineCap = .butt) {
            let line = CGMutablePath()
            line.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
            path.addPath(line.copy(strokingWithWidth: width, lineCap: cap, lineJoin: .miter, miterLimit: 4))
        }
        func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            path.addRect(CGRect(x: x, y: y, width: width, height: height))
        }
        switch mark {
        case .none:
            return nil
        case .home:
            // A house: the roof and the walls as one solid shape.
            path.addLines(between: [
                CGPoint(x: 8, y: 6.5), CGPoint(x: 12, y: 9.5), CGPoint(x: 10.5, y: 9.5), CGPoint(x: 10.5, y: 12.5),
                CGPoint(x: 5.5, y: 12.5), CGPoint(x: 5.5, y: 9.5), CGPoint(x: 4, y: 9.5),
            ])
            path.closeSubpath()
        case .developer:
            // Angle brackets: < >.
            stroke([(7, 7), (4.5, 9.5), (7, 12)])
            stroke([(9, 7), (11.5, 9.5), (9, 12)])
        case .documents:
            // Three lines of text, the last one short.
            block(4.5, 7, 7, 1)
            block(4.5, 9, 7, 1)
            block(4.5, 11, 4, 1)
        case .downloads:
            // An arrow down.
            block(7.5, 6.5, 1, 5)
            stroke([(5, 9), (8, 12), (11, 9)])
        case .applications:
            // Four squares.
            for x in [5, 8.5] as [CGFloat] {
                for y in [6.5, 10] as [CGFloat] { block(x, y, 2.5, 2.5) }
            }
        case .desktop:
            // A screen on its foot.
            block(4.5, 6.5, 7, 4.5)
            block(6.5, 12, 3, 1)
        }
        return path
    }
}

/// The Grove folder as a SwiftUI shape, as `PineShape` is.
struct FolderShape: Shape {
    var mark = FolderMark.none

    func path(in rect: CGRect) -> Path { Path(FolderPath.path(mark: mark, in: rect)) }
}

/// The Grove folder in its ink (`FolderInk`: the scheme's orange), in an icon cell.
struct FolderIcon: View {
    var mark = FolderMark.none
    @Environment(\.theme) private var theme

    var body: some View {
        FolderShape(mark: mark).fill(Color(FolderInk.color(in: theme)))
            .frame(width: IconMetrics.cell, height: IconMetrics.cell)
            .accessibilityHidden(true)
    }
}

// MARK: Which icon, and drawing it

/// What a row draws for its entry.
enum EntryIcon {
    case folder(FolderMark)
    case glyph(Glyph)
    /// What macOS gives it.
    case image(NSImage)

    /// Draws the icon in `rect` (a flipped view's coordinates).
    @MainActor
    func draw(in rect: CGRect, theme: ThemeColors, dimmed: Bool) {
        let opacity = dimmed ? IconMetrics.hiddenOpacity : 1
        switch self {
        case .folder(let mark):
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.addPath(FolderPath.path(mark: mark, in: rect))
            context.setFillColor(NSColor(FolderInk.color(in: theme)).withAlphaComponent(opacity).cgColor)
            context.fillPath()
        case .glyph(let glyph):
            FileGlyph.draw(glyph, in: rect, opacity: dimmed ? IconMetrics.hiddenGlyphOpacity : 1)
        case .image(let image):
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }
}

/// Picks each entry's icon (spec §10) and keeps macOS's icons: per path for
/// what has an icon of its own, per extension for a type.
@MainActor
final class IconCache {
    static let shared = IconCache()

    private var byPath: [String: NSImage] = [:]
    private var byExtension: [String: NSImage] = [:]
    private var custom: [String: Bool] = [:]
    private var volumes: [String: NSImage] = [:]
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func icon(for entry: Entry, light: Bool) -> EntryIcon {
        // A file with an icon of its own keeps it: that isn't in an `Entry`,
        // so it is asked here, once per file, before the map is.
        if case .file = entry.kind, hasCustomIcon(entry.url) { return .image(own(entry.url)) }
        switch GroveIcons.map.kind(for: entry, light: light, home: home) {
        case .folder(let mark): return .folder(mark)
        case .glyph(let glyph): return .glyph(glyph)
        case .system:
            switch entry.kind {
            case .package, .volume, .alias: return .image(own(entry.url))
            case .folder, .file, .symlink: return .image(ofType(entry.url.pathExtension.lowercased()))
            }
        }
    }

    /// Forgets the icons kept per path (a folder was read again: an app may
    /// have been replaced, a file given an icon).
    func forgetPaths() {
        byPath = [:]
        custom = [:]
    }

    /// A volume's own icon, for the sidebar: kept until the volumes change
    /// (`forgetVolumes`), so a row never asks the disk while it is drawn.
    func volumeIcon(_ url: URL) -> NSImage {
        if let known = volumes[url.path] { return known }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        volumes[url.path] = image
        return image
    }

    func forgetVolumes() { volumes = [:] }

    private func own(_ url: URL) -> NSImage {
        if let known = byPath[url.path] { return known }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        byPath[url.path] = image
        return image
    }

    private func ofType(_ ext: String) -> NSImage {
        if let known = byExtension[ext] { return known }
        let image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        byExtension[ext] = image
        return image
    }

    /// The Finder flag "has a custom icon", from the file's Finder info: one
    /// small attribute read, no icon loaded.
    private func hasCustomIcon(_ url: URL) -> Bool {
        if let known = custom[url.path] { return known }
        var info = [UInt8](repeating: 0, count: 32)
        let read = getxattr(url.path, XATTR_FINDERINFO_NAME, &info, info.count, 0, XATTR_NOFOLLOW)
        // The flags are the 16 bits at offset 8, big-endian; 0x0400 is kHasCustomIcon.
        let has = read == info.count && info[8] & 0x04 != 0
        custom[url.path] = has
        return has
    }
}
