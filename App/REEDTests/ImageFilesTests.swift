import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import REED

final class ImageFilesTests: XCTestCase {
    func testAnUnrotatedPhotoKeepsItsShape() throws {
        let size = try writePhoto(width: 40, height: 20, orientation: 1)
        XCTAssertEqual(ImageFiles.headerSize(of: size), CGSize(width: 40, height: 20))
    }

    func testARotatedPhotoSwapsItsSides() throws {
        let size = try writePhoto(width: 40, height: 20, orientation: 6)
        XCTAssertEqual(ImageFiles.headerSize(of: size), CGSize(width: 20, height: 40))
    }

    private func writePhoto(width: Int, height: Int, orientation: UInt32) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
