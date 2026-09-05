// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pix2PixStudio",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pix2PixStudio", targets: ["Pix2PixStudio"])
    ],
    targets: [
        .executableTarget(
            name: "Pix2PixStudio",
            path: "Sources/Pix2PixStudio",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
