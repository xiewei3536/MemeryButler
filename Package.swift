// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemoryButler",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MemoryButler",
            path: "Sources/MemoryButler"
        )
    ]
)
