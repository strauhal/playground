// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioReactive",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AudioReactive", targets: ["AudioReactive"])],
    targets: [.executableTarget(name: "AudioReactive", path: "Sources/AudioReactive")]
)
