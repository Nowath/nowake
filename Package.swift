// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nowake",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "nowake", path: "Sources/nowake")
    ]
)
