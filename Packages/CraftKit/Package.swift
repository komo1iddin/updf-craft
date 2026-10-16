// swift-tools-version: 6.0
import PackageDescription

// CraftCore.xcframework Engine/scripts/build_xcframework.sh bilan yig'iladi va
// Artifacts/ ichiga qo'yiladi (git'ga kirmaydi). docs/BUILD.md ga qarang.
let package = Package(
    name: "CraftKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CraftKit", targets: ["CraftKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "CraftCore",
            path: "Artifacts/CraftCore.xcframework"
        ),
        .target(
            name: "CraftKit",
            dependencies: ["CraftCore"],
            linkerSettings: [
                // libcraftcore.a — C++ (Apple libc++) va PDFium'ning macOS bog'liqliklari.
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
            ]
        ),
        .testTarget(
            name: "CraftKitTests",
            dependencies: ["CraftKit"]
        ),
    ]
)
