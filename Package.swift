// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Uthon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Uthon",
            path: "Sources/Uthon"
        )
    ]
)
