// swift-tools-version: 6.0

import PackageDescription

// swiftui-math by Guille Gonzalez (MIT), commit 0b5c2cfaaec8d6193db206f675048eeb5ce95f71,
// with one addition: `\underbrace{…}` draws a brace under its base, the way KaTeX stacks it.
let package = Package(
  name: "swiftui-math",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "SwiftUIMath", targets: ["SwiftUIMath"])
  ],
  targets: [
    .target(
      name: "SwiftUIMath",
      dependencies: [],
      resources: [.copy("mathFonts.bundle")]
    )
  ]
)
