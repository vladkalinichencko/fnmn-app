// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FNMNCore",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [.library(name: "FNMNCore", targets: ["FNMNCore"])],
    targets: [
        .target(name: "FNMNCore"),
        .testTarget(
            name: "FNMNCoreTests",
            dependencies: ["FNMNCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
