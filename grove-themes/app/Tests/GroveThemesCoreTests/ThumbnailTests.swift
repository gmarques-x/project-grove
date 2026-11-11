import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GroveThemesCore

@Suite struct ThumbnailTests {
    /// Writes a plain WIDTH×HEIGHT PNG to a temp file.
    func png(width: Int, height: Int) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString).png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    @Test func aLargeImageIsDecodedSmall() throws {
        let url = try png(width: 2880, height: 1864)
        let thumb = try #require(Thumbnail.load(url, maxPixel: 640))
        #expect(max(thumb.width, thumb.height) == 640)
        #expect(thumb.width == 640)
        #expect(thumb.height == 414)
    }

    @Test func aSmallImageIsNotEnlarged() throws {
        let url = try png(width: 300, height: 200)
        let thumb = try #require(Thumbnail.load(url, maxPixel: 640))
        #expect(thumb.width == 300)
        #expect(thumb.height == 200)
    }

    @Test func aMissingFileIsNil() {
        #expect(Thumbnail.load(URL(fileURLWithPath: "/no/such/file.png"), maxPixel: 640) == nil)
    }
}
