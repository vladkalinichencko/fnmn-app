// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "REEDCore",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [.library(name: "REEDCore", targets: ["REEDCore"])],
    targets: [
        .target(name: "REEDCore"),
        .testTarget(
            name: "REEDCoreTests",
            dependencies: ["REEDCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
