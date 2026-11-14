// Project Grove · draws the three apps' icons: Grove Themes, Grove Keys and
// Grove Explorer, after the first Grove icon: worn paper, a faint survey ring
// and cross framing the logo's pine, the pine in patches of forest green, and
// misty wooded hills below. What the pine stands on says which app it is: a
// disc that is half day and half night, a key cap, a folder. Run from the
// repo root:
//   swiftc -O assets/app-icons/make.swift -o "$TMPDIR/grove-app-icons" && "$TMPDIR/grove-app-icons" grove-dotfiles/theme .
// It writes grove-<app>/app/Resources/AppIcon.png (1024 px; the install
// modules sips it into an .icns). The PNGs are tracked; run it again only to
// change an icon. Everything is seeded, so a rerun draws the same pixels.
import AppKit

let themeDir = CommandLine.arguments[1], root = CommandLine.arguments[2]
let side = 1024

struct RGB {
    var r, g, b: Double
    func mixed(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
    func cg(_ alpha: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// `name = #RRGGBB` from theme/everforest-<scheme>.
func palette(_ scheme: String) -> [String: RGB] {
    var colors: [String: RGB] = [:]
    let text = try! String(contentsOfFile: "\(themeDir)/everforest-\(scheme)", encoding: .utf8)
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts[1].hasPrefix("#"), let hex = UInt32(parts[1].dropFirst(), radix: 16) else { continue }
        colors[parts[0]] = RGB(r: Double((hex >> 16) & 255) / 255, g: Double((hex >> 8) & 255) / 255, b: Double(hex & 255) / 255)
    }
    return colors
}

let dark = palette("dark-medium"), light = palette("light-medium")
/// The lockup's two tones: the paper and the ink of "Project Grove".
let paper = dark["lockup_ink"]!, ink = light["lockup_ink"]!
let cream = paper.mixed(light["bg0"]!, 0.55), night = dark["bg0"]!
/// The pine's greens, darkest first: the ink warmed toward Everforest's green.
let forest = ink.mixed(dark["green"]!, 0.2), moss = ink.mixed(dark["green"]!, 0.38)
let kraft = paper.mixed(light["yellow"]!, 0.22)

// MARK: Noise

func lattice(_ x: Int, _ y: Int, _ seed: Int) -> Double {
    var h = UInt64(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h % 100_000) / 100_000
}

func noise(_ x: Double, _ y: Double, _ seed: Int) -> Double {
    let fx = floor(x), fy = floor(y)
    let ix = Int(fx), iy = Int(fy)
    var tx = x - fx, ty = y - fy
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    let a = lattice(ix, iy, seed), b = lattice(ix + 1, iy, seed)
    let c = lattice(ix, iy + 1, seed), d = lattice(ix + 1, iy + 1, seed)
    return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty
}

/// Layered noise, 0...1.
func cloud(_ x: Double, _ y: Double, octaves: Int, _ seed: Int) -> Double {
    var sum = 0.0, weight = 0.5, total = 0.0, fx = x, fy = y
    for octave in 0..<octaves {
        sum += weight * noise(fx, fy, seed &+ octave * 31)
        total += weight
        weight /= 2; fx *= 2; fy *= 2
    }
    return sum / total
}

struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 100_000) / 100_000
    }
}

// MARK: Bitmaps

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// A 1024 px context drawn top-down (y grows downward, like PineShape's path),
/// so a point's y is also its row in the pixel data.
func canvas() -> CGContext {
    let g = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    g.translateBy(x: 0, y: CGFloat(side))
    g.scaleBy(x: 1, y: -1)
    return g
}

/// An opaque image from a colour per pixel.
func image(_ color: (Double, Double) -> RGB) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: side * side * 4)
    for y in 0..<side {
        for x in 0..<side {
            let c = color(Double(x), Double(y)), at = (y * side + x) * 4
            bytes[at] = UInt8(max(0, min(1, c.r)) * 255)
            bytes[at + 1] = UInt8(max(0, min(1, c.g)) * 255)
            bytes[at + 2] = UInt8(max(0, min(1, c.b)) * 255)
        }
    }
    return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: space,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

/// Patches of a few shades, as on the first icon's pine.
func patches(_ shades: [RGB], scale: Double, seed: Int) -> CGImage {
    image { x, y in
        let v = cloud(x / scale, y / scale, octaves: 3, seed)
        let spread = min(0.999, max(0, (v - 0.3) / 0.4))
        return shades[Int(spread * Double(shades.count))]
    }
}

/// Fills the current clip with a full-canvas image.
func flood(_ g: CGContext, _ picture: CGImage) {
    g.saveGState()
    g.translateBy(x: 0, y: CGFloat(side))
    g.scaleBy(x: 1, y: -1)
    g.draw(picture, in: CGRect(x: 0, y: 0, width: side, height: side))
    g.restoreGState()
}

func fill(_ g: CGContext, _ path: CGPath, with picture: CGImage) {
    g.saveGState()
    g.addPath(path)
    g.clip()
    flood(g, picture)
    g.restoreGState()
}

/// An ink line around a shape: stroke it twice as wide, then fill over it.
func outline(_ g: CGContext, _ paths: [CGPath], width: CGFloat) {
    g.setStrokeColor(ink.cg())
    g.setLineWidth(width * 2)
    g.setLineJoin(.round)
    for path in paths { g.addPath(path) }
    g.strokePath()
}

// MARK: Shapes

/// The icon's body on Apple's grid: 824 of 1024, corners 185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
let ringCenter = CGPoint(x: 512, y: 446)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// The logo's pine (PineShape's 40 × 40 path), `height` tall, standing on
/// `base`, and the two cuts between its tiers that the lockup's pine has.
func pine(centerX: CGFloat, base: CGFloat, height: CGFloat) -> (tree: CGPath, cuts: CGPath, unit: CGFloat) {
    let points: [(CGFloat, CGFloat)] = [
        (20, 2), (27, 12), (23, 12), (30, 21), (25, 21), (33, 31), (22, 31), (22, 38),
        (18, 38), (18, 31), (7, 31), (15, 21), (10, 21), (17, 12), (13, 12),
    ]
    let unit = height / 36
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: centerX + (x - 20) * unit, y: base - (38 - y) * unit) }
    let tree = CGMutablePath()
    tree.addLines(between: points.map { point($0.0, $0.1) })
    tree.closeSubpath()
    let cuts = CGMutablePath()
    cuts.addLines(between: [point(16, 12.6), point(20, 7), point(24, 12.6)])
    cuts.addLines(between: [point(14, 22.25), point(20, 14.75), point(26, 22.25)])
    return (tree, cuts, unit)
}

/// The pine in patches of `shades`, its cuts showing `under`.
func drawPine(_ g: CGContext, centerX: CGFloat, base: CGFloat, height: CGFloat, shades: CGImage, under: RGB) {
    let (tree, cuts, unit) = pine(centerX: centerX, base: base, height: height)
    fill(g, tree, with: shades)
    g.saveGState()
    g.addPath(tree)
    g.clip()
    g.addPath(cuts)
    g.setStrokeColor(under.cg())
    g.setLineWidth(unit * 0.8)
    g.setLineJoin(.miter)
    g.strokePath()
    g.restoreGState()
}

/// A spruce of the hills: ragged tiers, each a little wider than the last.
func spruce(centerX: CGFloat, base: CGFloat, height: CGFloat, random: inout Seeded) -> CGPath {
    let tiers = 5 + Int(random.next() * 4), lean = CGFloat(random.next() - 0.5) * height * 0.06
    let tier = height * 0.92 / CGFloat(tiers), top = base - height
    var left: [CGPoint] = [], right: [CGPoint] = []
    for index in 0..<tiers {
        let grow = CGFloat(index + 1) / CGFloat(tiers), y = top + tier * CGFloat(index + 1)
        let middle = centerX + lean * (1 - grow)
        for sign in [-1.0, 1.0] as [CGFloat] {
            let reach = height * 0.25 * grow * CGFloat(0.75 + 0.5 * random.next())
            let tip = CGPoint(x: middle + sign * reach, y: y + tier * CGFloat(random.next() - 0.3) * 0.3)
            let notch = CGPoint(x: middle + sign * reach * 0.42, y: y - tier * 0.12)
            if sign < 0 { left += [tip, notch] } else { right += [tip, notch] }
        }
    }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: centerX + lean, y: top))
    for point in left { path.addLine(to: point) }
    path.addLine(to: CGPoint(x: centerX - height * 0.025, y: base))
    path.addLine(to: CGPoint(x: centerX + height * 0.025, y: base))
    for point in right.reversed() { path.addLine(to: point) }
    path.closeSubpath()
    return path
}

// MARK: The ground all three share

/// One ridge: an uneven skyline, spruces along it, and mist lying at its foot.
func ridge(_ g: CGContext, top: CGFloat, roll: CGFloat, trees: ClosedRange<CGFloat>?, step: CGFloat, tone: RGB,
           mist: Double, seed: Int) {
    var random = Seeded(state: UInt64(seed) &* 977 &+ 5)
    func skyline(_ x: CGFloat) -> CGFloat {
        top + roll * CGFloat(cloud(Double(x) / 210, Double(seed), octaves: 4, seed) - 0.5) * 2
    }
    let land = CGMutablePath()
    land.move(to: CGPoint(x: body.minX, y: body.maxY))
    for x in stride(from: body.minX, through: body.maxX, by: 4) { land.addLine(to: CGPoint(x: x, y: skyline(x))) }
    land.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
    if let trees {
        var x = body.minX - 10
        while x < body.maxX + 10 {
            // Stands and gaps: the wood thins where the noise is low.
            let dense = cloud(Double(x) / 120, 3, octaves: 2, seed &+ 9)
            if dense > 0.28 {
                let tall = trees.lowerBound + (trees.upperBound - trees.lowerBound) * CGFloat(random.next() * (0.4 + dense))
                land.addPath(spruce(centerX: x, base: skyline(x) + tall * 0.08, height: tall, random: &random))
            }
            x += step * CGFloat(0.35 + 0.9 * random.next())
        }
    }
    g.addPath(land)
    g.setFillColor(tone.cg())
    g.fillPath(using: .winding)
    let haze = CGGradient(colorsSpace: space, colors: [paper.cg(0), paper.cg(mist)] as CFArray, locations: [0, 1])!
    g.saveGState()
    g.addPath(land)
    g.clip()
    g.drawLinearGradient(haze, start: CGPoint(x: 0, y: top - roll), end: CGPoint(x: 0, y: top + 90), options: [])
    g.restoreGState()
}

func ground(_ g: CGContext, seed: Int) {
    // The paper: cloudy, with darker stains and a paler sky.
    flood(g, image { x, y in
        let wash = cloud(x / 240, y / 240, octaves: 4, seed)
        let stain = max(0, cloud(x / 130, y / 130, octaves: 3, seed &+ 3) - 0.56) * 1.6
        let sky = max(0, 1 - y / 700) * 0.35
        return paper.mixed(cream, sky + (wash - 0.5) * 0.5).mixed(forest, stain * 0.5)
    })

    // The survey ring and its cross: fine ink, with ticks, behind everything.
    g.setStrokeColor(ink.cg(0.3))
    g.setLineWidth(2.5)
    g.strokeEllipse(in: CGRect(x: ringCenter.x - 316, y: ringCenter.y - 316, width: 632, height: 632))
    g.setLineWidth(1.5)
    g.strokeEllipse(in: CGRect(x: ringCenter.x - 330, y: ringCenter.y - 330, width: 660, height: 660))
    g.setLineWidth(2)
    for (dx, dy) in [(1.0, 0.0), (0.0, 1.0)] as [(CGFloat, CGFloat)] {
        g.move(to: CGPoint(x: ringCenter.x - dx * 372, y: ringCenter.y - dy * 372))
        g.addLine(to: CGPoint(x: ringCenter.x + dx * 372, y: ringCenter.y + dy * 372))
        for mark in stride(from: -360.0, through: 360.0, by: 40.0) as StrideThrough<CGFloat> {
            let reach: CGFloat = Int(mark) % 120 == 0 ? 9 : 5
            g.move(to: CGPoint(x: ringCenter.x + dx * mark - dy * reach, y: ringCenter.y + dy * mark - dx * reach))
            g.addLine(to: CGPoint(x: ringCenter.x + dx * mark + dy * reach, y: ringCenter.y + dy * mark + dx * reach))
        }
    }
    g.strokePath()

    // Far mountains, then four wooded ridges, each nearer, darker and taller.
    ridge(g, top: 668, roll: 58, trees: nil, step: 0, tone: paper.mixed(forest, 0.16), mist: 0.7, seed: seed &+ 1)
    ridge(g, top: 716, roll: 30, trees: 22...52, step: 20, tone: paper.mixed(forest, 0.3), mist: 0.55, seed: seed &+ 2)
    ridge(g, top: 762, roll: 26, trees: 34...78, step: 26, tone: paper.mixed(forest, 0.5), mist: 0.45, seed: seed &+ 3)
    ridge(g, top: 812, roll: 24, trees: 50...110, step: 34, tone: paper.mixed(forest, 0.74), mist: 0.3, seed: seed &+ 4)
    ridge(g, top: 874, roll: 20, trees: 70...150, step: 46, tone: forest.mixed(ink, 0.55), mist: 0, seed: seed &+ 5)
}

// MARK: The three marks

let greens = patches([ink, forest, forest, moss], scale: 46, seed: 5)
let papers = patches([cream, paper, cream.mixed(paper, 0.5)], scale: 46, seed: 6)
let olives = patches([forest, moss, ink.mixed(forest, 0.5)], scale: 60, seed: 7)
let nights = patches([night, night.mixed(ink, 0.6), night.mixed(ink, 0.3)], scale: 70, seed: 8)
let creams = patches([cream, cream.mixed(paper, 0.5), cream], scale: 80, seed: 9)
let krafts = patches([kraft, kraft.mixed(paper, 0.5), kraft.mixed(forest, 0.1)], scale: 80, seed: 10)

/// Grove Themes: the pine on a disc, half day and half night.
func themesMark(_ g: CGContext) {
    let radius: CGFloat = 232
    let disc = CGRect(x: ringCenter.x - radius, y: ringCenter.y - radius, width: radius * 2, height: radius * 2)
    let round = CGPath(ellipseIn: disc, transform: nil)
    outline(g, [round], width: 9)
    let halves: [(CGRect, CGImage, CGImage, RGB)] = [
        (CGRect(x: disc.minX, y: disc.minY, width: radius, height: radius * 2), creams, greens, cream),
        (CGRect(x: disc.midX, y: disc.minY, width: radius, height: radius * 2), nights, papers, night),
    ]
    for (half, ground, shades, under) in halves {
        g.saveGState()
        g.addPath(round)
        g.clip()
        g.clip(to: half)
        flood(g, ground)
        drawPine(g, centerX: ringCenter.x, base: ringCenter.y + 164, height: 330, shades: shades, under: under)
        g.restoreGState()
    }
}

/// Grove Keys: the pine as the legend of a key cap.
func keysMark(_ g: CGContext) {
    let cap = rounded(CGRect(x: 296, y: 232, width: 432, height: 436), 80)
    let top = rounded(CGRect(x: 338, y: 256, width: 348, height: 344), 56)
    outline(g, [cap], width: 9)
    fill(g, cap, with: olives)
    outline(g, [top], width: 5)
    fill(g, top, with: creams)
    drawPine(g, centerX: 512, base: 556, height: 262, shades: greens, under: cream)
}

/// Grove Explorer: the pine on a folder.
func explorerMark(_ g: CGContext) {
    let tab = rounded(CGRect(x: 278, y: 250, width: 214, height: 120), 34)
    let back = rounded(CGRect(x: 278, y: 296, width: 468, height: 366), 40)
    let front = rounded(CGRect(x: 278, y: 356, width: 468, height: 306), 40)
    outline(g, [tab, back], width: 9)
    fill(g, tab, with: olives)
    fill(g, back, with: olives)
    outline(g, [front], width: 5)
    fill(g, front, with: krafts)
    drawPine(g, centerX: 512, base: 632, height: 244, shades: greens, under: kraft)
}

// MARK: Wear

/// The drawing, worn: every edge wobbles a little, the print is uneven, and
/// the sheet has grain. `source` and the result are top-down RGBA rows.
func worn(_ source: CGContext, seed: Int) -> CGImage {
    let pixels = source.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
    func sample(_ x: Double, _ y: Double, _ channel: Int) -> Double {
        let cx = max(0, min(Double(side - 2), x)), cy = max(0, min(Double(side - 2), y))
        let ix = Int(cx), iy = Int(cy), tx = cx - Double(ix), ty = cy - Double(iy)
        func at(_ px: Int, _ py: Int) -> Double { Double(pixels[(py * side + px) * 4 + channel]) / 255 }
        return (at(ix, iy) * (1 - tx) + at(ix + 1, iy) * tx) * (1 - ty) + (at(ix, iy + 1) * (1 - tx) + at(ix + 1, iy + 1) * tx) * ty
    }
    return image { x, y in
        let dx = (cloud(x / 22, y / 22, octaves: 2, seed &+ 40) - 0.5) * 5 + (noise(x / 4, y / 4, seed &+ 41) - 0.5) * 1.6
        let dy = (cloud(x / 22, y / 22, octaves: 2, seed &+ 42) - 0.5) * 5 + (noise(x / 4, y / 4, seed &+ 43) - 0.5) * 1.6
        var c = RGB(r: sample(x + dx, y + dy, 0), g: sample(x + dx, y + dy, 1), b: sample(x + dx, y + dy, 2))
        // Uneven print: dark areas let the paper through in places.
        let darkness = 1 - (c.r + c.g + c.b) / 3
        let thin = max(0, cloud(x / 36, y / 36, octaves: 3, seed &+ 44) - 0.5) * 2
        c = c.mixed(paper, thin * darkness * 0.24)
        let blotch = cloud(x / 70, y / 70, octaves: 4, seed &+ 45) - 0.5
        let grain = noise(x / 1.6, y / 1.6, seed &+ 46) - 0.5
        let fibre = noise(x / 9, y / 1.2, seed &+ 47) - 0.5
        let shade = 1 + blotch * 0.2 + grain * 0.13 + fibre * 0.05
        return RGB(r: c.r * shade, g: c.g * shade, b: c.b * shade)
    }
}

func render(_ app: String, seed: Int, mark: (CGContext) -> Void) {
    let drawing = canvas()
    ground(drawing, seed: seed)
    mark(drawing)
    let sheet = worn(drawing, seed: seed)

    let g = canvas()
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    g.addPath(bodyPath)
    g.setFillColor(paper.cg())
    g.fillPath()
    g.restoreGState()

    g.saveGState()
    g.addPath(bodyPath)
    g.clip()
    flood(g, sheet)
    // Specks, scratches and fold lines on top of the print.
    var random = Seeded(state: UInt64(seed) &+ 101)
    for index in 0..<2600 {
        let tone = index % 3 == 0 ? cream : ink
        g.setFillColor(tone.cg(0.08 + 0.22 * random.next()))
        let size = CGFloat(0.8 + 2.6 * random.next() * random.next())
        g.fillEllipse(in: CGRect(x: body.minX + body.width * CGFloat(random.next()),
                                 y: body.minY + body.height * CGFloat(random.next()), width: size, height: size))
    }
    for _ in 0..<40 {
        var point = CGPoint(x: body.minX + body.width * CGFloat(random.next()), y: body.minY + body.height * CGFloat(random.next()))
        var angle = 2 * Double.pi * random.next()
        g.setStrokeColor((random.next() < 0.4 ? cream : ink).cg(0.1 + 0.14 * random.next()))
        g.setLineWidth(CGFloat(0.8 + random.next()))
        g.move(to: point)
        for _ in 0..<(4 + Int(random.next() * 10)) {
            angle += (random.next() - 0.5) * 0.7
            point = CGPoint(x: point.x + CGFloat(cos(angle)) * 14, y: point.y + CGFloat(sin(angle)) * 14)
            g.addLine(to: point)
        }
        g.strokePath()
    }
    // Aged, darker edges, as if handled.
    let edge = CGGradient(colorsSpace: space, colors: [ink.cg(0), ink.cg(0.1), ink.cg(0.42)] as CFArray, locations: [0.6, 0.86, 1])!
    g.drawRadialGradient(edge, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                         endCenter: CGPoint(x: 512, y: 512), endRadius: 590, options: [])
    g.addPath(rounded(body.insetBy(dx: 3, dy: 3), 182))
    g.setStrokeColor(ink.cg(0.7))
    g.setLineWidth(6)
    g.strokePath()
    g.addPath(rounded(body.insetBy(dx: 15, dy: 15), 170))
    g.setStrokeColor(ink.cg(0.22))
    g.setLineWidth(2)
    g.strokePath()
    g.restoreGState()

    let file = "\(root)/grove-\(app)/app/Resources/AppIcon.png"
    try! FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: g.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
    print(file)
}

render("themes", seed: 11, mark: themesMark)
render("keys", seed: 23, mark: keysMark)
render("explorer", seed: 37, mark: explorerMark)
