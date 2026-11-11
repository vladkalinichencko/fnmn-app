@testable import FNMNCore
import Foundation
import Testing

@Suite struct PackagePathTests {
    private let folder = URL(filePath: "/tmp/fnmn/article")

    @Test func aRelativeNameStaysInsideTheFolder() throws {
        #expect(LibraryFile.contained("assets/a.png", in: folder)?.path == "/tmp/fnmn/article/assets/a.png")
        #expect(LibraryFile.contained("a.png", in: folder)?.path == "/tmp/fnmn/article/a.png")
        #expect(LibraryFile.contained("./a.png", in: folder)?.path == "/tmp/fnmn/article/a.png")
    }

    @Test func aNameWithUnicodeOrSpacesStaysInside() throws {
        #expect(LibraryFile.contained("assets/café 1.png", in: folder)?.lastPathComponent == "café 1.png")
    }

    @Test func aNameThatCouldLeaveIsRefused() {
        for path in ["", "/etc/passwd", "../x.jpg", "a/../../b.jpg", "..", "a/..", "assets/../../x.jpg"] {
            #expect(LibraryFile.contained(path, in: folder) == nil, "\(path)")
        }
    }

    @Test func twoDotsInsideANameAreStillAName() {
        #expect(LibraryFile.contained("a..b.jpg", in: folder)?.lastPathComponent == "a..b.jpg")
    }
}
