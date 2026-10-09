// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuadCastControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuadCastControl",
            path: "Sources/QuadCastControl"
        )
    ]
)
