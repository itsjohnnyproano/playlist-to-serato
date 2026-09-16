// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Setlist",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Setlist", targets: ["Setlist"])
    ],
    targets: [
        .executableTarget(name: "Setlist"),
        .testTarget(name: "SetlistTests", dependencies: ["Setlist"])
    ]
)
