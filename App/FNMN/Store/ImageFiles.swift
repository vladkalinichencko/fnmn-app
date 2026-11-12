import CryptoKit
import ImageIO
import SwiftUI
import UIKit

enum ImageFiles {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()
    private static let diskFolder = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "FNMN/thumbs")

    @concurrent
    static func pixelSize(of url: URL) async -> CGSize? {
        headerSize(of: url)
    }

    nonisolated static func headerSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: width)
    }

    @concurrent
    static func picture(at url: URL, covering pixels: CGSize) async -> UIImage? {
        let key = "\(url.path)#\(Int(pixels.width))x\(Int(pixels.height))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let small = max(pixels.width, pixels.height) <= 1024
        if small, let disk = diskImage(key: key) {
            cache.setObject(disk, forKey: key, cost: pixelCost(disk))
            return disk
        }
        guard let natural = await pixelSize(of: url) else {
            return nil
        }
        let scale = min(max(pixels.width / natural.width, pixels.height / natural.height), 1)
        let longest = Int((max(natural.width, natural.height) * scale).rounded(.up))
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let picture = UIImage(cgImage: image)
        cache.setObject(picture, forKey: key, cost: image.bytesPerRow * image.height)
        if small {
            writeDisk(picture, key: key)
        }
        return picture
    }

    private nonisolated static func pixelCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }

    private nonisolated static func diskURL(_ key: NSString) -> URL {
        let digest = SHA256.hash(data: Data((key as String).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskFolder.appending(path: "\(digest).img")
    }

    private nonisolated static func diskImage(key: NSString) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(key)) else {
            return nil
        }
        return UIImage(data: data)
    }

    private nonisolated static func writeDisk(_ image: UIImage, key: NSString) {
        let hasAlpha: Bool
        switch image.cgImage?.alphaInfo {
        case .premultipliedLast, .premultipliedFirst, .last, .first:
            hasAlpha = true
        default:
            hasAlpha = false
        }
        guard let data = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 0.9) else {
            return
        }
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        try? data.write(to: diskURL(key), options: .atomic)
    }
}

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

    private var request: Request {
        func pixels(_ points: CGFloat) -> CGFloat { ((points * displayScale) / 128).rounded(.up) * 128 }
        return Request(url: url, pixels: CGSize(width: pixels(size.width), height: pixels(size.height)))
    }

    private struct Request: Equatable {
        let url: URL
        let pixels: CGSize
    }
}
