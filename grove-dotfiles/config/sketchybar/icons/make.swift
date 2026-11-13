// Grove bar · draws the bar's symbol icons: Apple's SF Symbols in the scheme's
// colours, one PNG per state, for the dark and the light schemes (the accents
// are the same in hard, medium and soft). Run from grove-dotfiles:
//   swiftc -O config/sketchybar/icons/make.swift -o "$TMPDIR/grove-icons" && "$TMPDIR/grove-icons" theme config/sketchybar/icons
// The PNGs are tracked; run it again only to change an icon. 44 px squares,
// shown at 22 pt (image scale 0.5). The pine is drawn elsewhere; the
// Bluetooth rune, which isn't a symbol, is drawn here as a path.
import AppKit

let themeDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]

/// `name = #RRGGBB` from theme/everforest-<scheme>.
func palette(_ scheme: String) -> [String: NSColor] {
    var colors: [String: NSColor] = [:]
    let text = try! String(contentsOfFile: "\(themeDir)/everforest-\(scheme)", encoding: .utf8)
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts[1].hasPrefix("#"), let hex = UInt32(parts[1].dropFirst(), radix: 16) else { continue }
        colors[parts[0]] = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                                   blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    return colors
}

/// One symbol, centred in a 22 pt square at 2x. `value` lights part of a
/// variable symbol (the Wi-Fi fan's arcs, the speaker's waves).
func draw(_ symbol: String, value: Double? = nil, color: NSColor, to file: String) {
    let base = value.map { NSImage(systemSymbolName: symbol, variableValue: $0, accessibilityDescription: nil) }
        ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    let look = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium).applying(.init(paletteColors: [color]))
    guard let image = base?.withSymbolConfiguration(look) else { fatalError("no symbol \(symbol)") }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = image.size
    image.draw(in: NSRect(x: (22 - size.width) / 2, y: (22 - size.height) / 2, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(file)"))
}

/// A level icon: `empty` drawn whole (dimmed by `emptyAlpha`), then `full`
/// over the part of it that `level` (0 to 1) covers, from the bottom or from
/// the left. Centred in a 22 pt square at 2x.
func drawLevel(empty: String, emptyAlpha: CGFloat, full: String, level: Double, fromBottom: Bool, color: NSColor, to file: String) {
    let look = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium).applying(.init(paletteColors: [color]))
    guard let back = NSImage(systemSymbolName: empty, accessibilityDescription: nil)?.withSymbolConfiguration(look),
          let front = NSImage(systemSymbolName: full, accessibilityDescription: nil)?.withSymbolConfiguration(look)
    else { fatalError("no symbol \(empty) or \(full)") }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func frame(_ image: NSImage) -> NSRect {
        NSRect(x: (22 - image.size.width) / 2, y: (22 - image.size.height) / 2, width: image.size.width, height: image.size.height)
    }
    back.draw(in: frame(back), from: .zero, operation: .sourceOver, fraction: emptyAlpha)
    let box = frame(front)
    let part = fromBottom
        ? NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height * level)
        : NSRect(x: box.minX, y: box.minY, width: box.width * level, height: box.height)
    NSBezierPath(rect: part).addClip()
    front.draw(in: box)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(file)"))
}

/// The Bluetooth rune, which SF Symbols doesn't offer: the spine and its two
/// arrowheads as one stroke of the symbols' medium weight, as tall as the
/// Wi-Fi fan's image, centred in a 22 pt square at 2x. `connected` adds a dot
/// on each side; `struck` crosses it out as the `.slash` symbols do (a clear
/// gap around the line).
func drawRune(color: NSColor, connected: Bool = false, struck: Bool = false, to file: String) {
    let look = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    guard let fan = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?.withSymbolConfiguration(look)
    else { fatalError("no symbol wifi") }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let weight: CGFloat = 1.6
    let h = fan.size.height - weight, w = h * 0.27
    let cx: CGFloat = 11, top = 11 + h / 2, bottom = 11 - h / 2
    func stroke(_ points: [NSPoint], width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
    color.set()
    stroke([NSPoint(x: cx - w, y: top - h * 0.25), NSPoint(x: cx + w, y: top - h * 0.75), NSPoint(x: cx, y: bottom),
            NSPoint(x: cx, y: top), NSPoint(x: cx + w, y: top - h * 0.25), NSPoint(x: cx - w, y: top - h * 0.75)],
           width: weight)
    if connected {
        for x in [cx - w - 3, cx + w + 3] {
            NSBezierPath(ovalIn: NSRect(x: x - weight * 0.75, y: 11 - weight * 0.75, width: weight * 1.5, height: weight * 1.5)).fill()
        }
    }
    if struck {
        let slash = [NSPoint(x: cx - w - 1.5, y: top), NSPoint(x: cx + w + 1.5, y: bottom)]
        context.cgContext.setBlendMode(.clear)
        stroke(slash, width: weight * 2.2)
        context.cgContext.setBlendMode(.normal)
        stroke(slash, width: weight)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(file)"))
}

for appearance in ["dark", "light"] {
    let c = palette("\(appearance)-medium")
    let blue = c["blue"]!, yellow = c["yellow"]!, green = c["green"]!, red = c["red"]!, aqua = c["aqua"]!, off = c["grey2"]!
    // Wi-Fi: one, two or three arcs by signal; other ways of being online; off.
    for (level, value) in [(1, 0.2), (2, 0.5), (3, 1.0)] {
        draw("wifi", value: value, color: blue, to: "wifi-\(level)-\(appearance).png")
    }
    draw("wifi.slash", color: off, to: "wifi-off-\(appearance).png")
    draw("cable.connector", color: blue, to: "eth-\(appearance).png")
    draw("lock.shield", color: blue, to: "vpn-\(appearance).png")
    // Bluetooth, beside the fan in its pill: off, on, a device connected.
    drawRune(color: off, struck: true, to: "bt-off-\(appearance).png")
    drawRune(color: blue, to: "bt-on-\(appearance).png")
    drawRune(color: blue, connected: true, to: "bt-connected-\(appearance).png")
    for step in 0...10 {
        let level = Double(step) / 10
        // Battery: a bolt's outline, filled from the bottom with the charge;
        // red when it runs low.
        drawLevel(empty: "bolt", emptyAlpha: 1, full: "bolt.fill", level: level, fromBottom: true, color: yellow,
                  to: "bolt-\(step)-\(appearance).png")
        if step <= 2 {
            drawLevel(empty: "bolt", emptyAlpha: 1, full: "bolt.fill", level: level, fromBottom: true, color: red,
                      to: "bolt-low-\(step)-\(appearance).png")
        }
        // Volume: a faint speaker with its waves, filled from the left with the level.
        drawLevel(empty: "speaker.wave.3.fill", emptyAlpha: 0.3, full: "speaker.wave.3.fill", level: level, fromBottom: false,
                  color: green, to: "vol-\(step)-\(appearance).png")
    }
    draw("speaker.slash.fill", color: off, to: "vol-mute-\(appearance).png")
    draw("cpu", color: aqua, to: "cpu-\(appearance).png")
    draw("memorychip", color: aqua, to: "mem-\(appearance).png")
}
