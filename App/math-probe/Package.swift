// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MathProbe",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../Vendor/SwiftUIMath")],
    targets: [.executableTarget(name: "MathProbe", dependencies: [.product(name: "SwiftUIMath", package: "SwiftUIMath")])]
)
