import ImageIO
import SwiftUI
import UIKit

/// Pictures of articles on disk. A picture is decoded off the main thread, no larger than the place it is
/// shown in, and kept in memory until iOS runs short of it; views never read picture files themselves.
enum ImageFiles {
    /// NSCache is thread-safe and empties itself when memory runs low.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// The picture's size in pixels, read from the file's header without decoding it.
    @concurrent
    static func pixelSize(of url: URL) async -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// The picture decoded just large enough to cover `pixels`, never larger than the file itself.
    @concurrent
    static func picture(at url: URL, covering pixels: CGSize) async -> UIImage? {
        guard let natural = await pixelSize(of: url) else { return nil }
        let scale = min(max(pixels.width / natural.width, pixels.height / natural.height), 1)
        let longest = Int((max(natural.width, natural.height) * scale).rounded(.up))
        let key = "\(url.path)#\(longest)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let picture = UIImage(cgImage: image)
        cache.setObject(picture, forKey: key, cost: image.bytesPerRow * image.height)
        return picture
    }
}

/// A picture file filling the space it is given, decoded for that space once it is known.
struct FileImage: View {
    let url: URL
    let contentMode: ContentMode
    @Environment(\.displayScale) private var displayScale
    @State private var size = CGSize.zero
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .task(id: request) {
                guard request.pixels.width > 0, request.pixels.height > 0 else { return }
                image = await ImageFiles.picture(at: url, covering: request.pixels)
            }
    }

    /// Pixels rounded up to a step, so small layout changes do not decode the picture again.
    private var request: Request {
        func pixels(_ points: CGFloat) -> CGFloat { ((points * displayScale) / 128).rounded(.up) * 128 }
        return Request(url: url, pixels: CGSize(width: pixels(size.width), height: pixels(size.height)))
    }

    private struct Request: Equatable {
        let url: URL
        let pixels: CGSize
    }
}
