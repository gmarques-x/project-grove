import CoreGraphics
import Foundation
import ImageIO

/// Small decoded images for the gallery cards: a 2880×1864 wallpaper takes
/// ~21 MB decoded, its 640-pixel thumbnail well under 2 MB.
public enum Thumbnail {
    /// The image at `url`, decoded so its longer side is at most `maxPixel`
    /// (never enlarged); nil if it can't be read.
    public static func load(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return image
    }
}
